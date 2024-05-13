import Foundation
import FirebladeMath
import MetalKit
import DeltaCore

public enum RendererError: LocalizedError {
  case getMetalDevice
  case makeRenderCommandQueue
  case camera(Error)
  case skyBoxRenderer(Error)
  case worldRenderer(Error)
  case guiRenderer(Error)
  case screenRenderer(Error)
  case depthState(Error)
  case unknown(Error)
  
  public var errorDescription: String? {
    switch self {
      case .getMetalDevice:
        return "Failed to get metal device"
      case .makeRenderCommandQueue:
        return "Failed to make render command queue"
      case .camera(let cameraError):
        return "Failed to create camera: \(cameraError.labeledLocalizedDescription)"
      case .skyBoxRenderer(let skyBoxError):
        return "Failed to create sky box renderer: \(skyBoxError.labeledLocalizedDescription)"
      case .worldRenderer(let worldError):
        return "Failed to create world renderer: \(worldError.labeledLocalizedDescription)"
      case .guiRenderer(let guiError):
        return "Failed to create GUI renderer: \(guiError.labeledLocalizedDescription)"
      case .screenRenderer(let screenError):
        return "Failed to create Screen renderer: \(screenError.labeledLocalizedDescription)"
      case .depthState(let depthError):
        return "Failed to create depth state: \(depthError.labeledLocalizedDescription)"
      case .unknown(let error):
        return "Failed with an unknown error \(error.labeledLocalizedDescription)"
    }
  }
}

extension Error {
  public var labeledLocalizedDescription: String? {
    "\(String(describing: self)) - \(self.localizedDescription)"
  }
}

/// Coordinates the rendering of the game (e.g. blocks and entities).
public final class RenderCoordinator: NSObject, MTKViewDelegate {
  // MARK: Public properties

  /// Statistics that measure the renderer's current performance.
  public var statistics: RenderStatistics

  // MARK: Private properties

  /// The client to render.
  private var client: Client

  /// The renderer for the world's sky box.
  private var skyBoxRenderer: SkyBoxRenderer

  /// The renderer for the current world. Only renders blocks.
  private var worldRenderer: WorldRenderer

  /// The renderer for rendering the GUI.
  private var guiRenderer: GUIRenderer

  /// The renderer for rendering on screen. Can perform upscaling.
  private var screenRenderer: ScreenRenderer

  /// The camera that is rendered from.
  private var camera: Camera

  /// The device used to render.
  private var device: MTLDevice

  /// The depth stencil state. It's the same for every renderer so it's just made once here.
  private var depthState: MTLDepthStencilState

  /// The command queue.
  private var commandQueue: MTLCommandQueue

  /// The time that the cpu started encoding the previous frame.
  private var previousFrameStartTime: Double = 0

  /// The current frame capture state (`nil` if no capture is in progress).
  private var captureState: CaptureState?

  /// The renderer profiler.
  private var profiler = Profiler<RenderingMeasurement>("Rendering")

  /// The number of frames rendered so far.
  private var frameCount = 0

  /// The longest a frame has taken to encode so far.
  private var longestFrame: Double = 0
  
  // MARK: Init

  /// Creates a render coordinator.
  /// - Parameter client: The client to render for.
  public required init(_ client: Client) throws {
    guard let device = MTLCreateSystemDefaultDevice() else {
      throw RendererError.getMetalDevice
    }

    guard let commandQueue = device.makeCommandQueue() else {
      throw RendererError.makeRenderCommandQueue
    }

    self.client = client
    self.device = device
    self.commandQueue = commandQueue

    // Setup camera
    do {
      camera = try Camera(device)
    } catch {
      throw RendererError.camera(error)
    }

    do {
      skyBoxRenderer = try SkyBoxRenderer(
        client: client,
        device: device,
        commandQueue: commandQueue
      )
    } catch {
      throw RendererError.skyBoxRenderer(error)
    }

    do {
      worldRenderer = try WorldRenderer(
        client: client,
        device: device,
        commandQueue: commandQueue,
        profiler: profiler
      )
    } catch {
      throw RendererError.worldRenderer(error)
    }

    do {
      guiRenderer = try GUIRenderer(
        client: client,
        device: device,
        commandQueue: commandQueue,
        profiler: profiler
      )
    } catch {
      throw RendererError.guiRenderer(error)
    }

    do {
      screenRenderer = try ScreenRenderer(
        client: client,
        device: device,
        profiler: profiler
      )
    } catch {
      throw RendererError.screenRenderer(error)
    }

    // Create depth stencil state
    do {
      depthState = try MetalUtil.createDepthState(device: device)
    } catch {
      throw RendererError.depthState(error)
    }

    statistics = RenderStatistics(gpuCountersEnabled: false)

    super.init()
  }

  // MARK: Render

  public func draw(in view: MTKView) {
    let time = CFAbsoluteTimeGetCurrent()
    let frameTime = time - previousFrameStartTime
    previousFrameStartTime = time

    profiler.push(.updateRenderTarget)
    do {
      try screenRenderer.updateRenderTarget(for: view)
    } catch {
      log.error("Failed to update render target: \(error)")
      client.eventBus.dispatch(ErrorEvent(error: error, message: "Failed to update render target"))
      return
    }

    profiler.pop()

    // Fetch offscreen render pass descriptor from ScreenRenderer
    let renderPassDescriptor = screenRenderer.renderDescriptor


    // The CPU start time if vsync was disabled
    let cpuStartTime = CFAbsoluteTimeGetCurrent()

    profiler.push(.updateCamera)
    // Create world to clip uniforms buffer
    let uniformsBuffer = getCameraUniforms(view)
    profiler.pop()

    // When the render distance is above 2, move the fog 1 chunk closer to conceal
    // more of the world edge.
    let renderDistance = max(client.configuration.render.renderDistance - 1, 2)

    let fogColor = client.game.world.getFogColor(
      forViewerWithRay: camera.ray,
      withRenderDistance: renderDistance
    )

    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
      red: Double(fogColor.x),
      green: Double(fogColor.y),
      blue: Double(fogColor.z),
      alpha: 1
    )

    profiler.push(.createRenderCommandEncoder)
    // Create command buffer
    guard let commandBuffer = commandQueue.makeCommandBuffer() else {
      log.error("Failed to create command buffer")
      client.eventBus.dispatch(ErrorEvent(
        error: RenderError.failedToCreateCommandBuffer,
        message: "RenderCoordinator failed to create command buffer"
      ))
      return
    }

    // Create render encoder
    guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
      log.error("Failed to create render encoder")
      client.eventBus.dispatch(ErrorEvent(
        error: RenderError.failedToCreateRenderEncoder,
        message: "RenderCoordinator failed to create render encoder"
      ))
      return
    }
    profiler.pop()

    profiler.push(.skyBox)
    do {
      try skyBoxRenderer.render(
        view: view,
        encoder: renderEncoder,
        commandBuffer: commandBuffer,
        worldToClipUniformsBuffer: uniformsBuffer,
        camera: camera
      )
    } catch {
      log.error("Failed to render sky box: \(error)")
      client.eventBus.dispatch(ErrorEvent(error: error, message: "Failed to render sky box"))
      return
    }
    profiler.pop()

    // Configure the render encoder
    renderEncoder.setDepthStencilState(depthState)
    renderEncoder.setFrontFacing(.counterClockwise)
    renderEncoder.setVertexBuffer(uniformsBuffer, offset: 0, index: 1)

    switch client.configuration.render.mode {
      case .normal:
        renderEncoder.setCullMode(.front)
      case .wireframe:
        renderEncoder.setCullMode(.none)
        renderEncoder.setTriangleFillMode(.lines)
    }

    profiler.push(.world)
    do {
      try worldRenderer.render(
        view: view,
        encoder: renderEncoder,
        commandBuffer: commandBuffer,
        worldToClipUniformsBuffer: uniformsBuffer,
        camera: camera
      )
    } catch {
      log.error("Failed to render world: \(error)")
      client.eventBus.dispatch(ErrorEvent(error: error, message: "Failed to render world"))
      return
    }
    profiler.pop()

    profiler.push(.gui)
    do {
      try guiRenderer.render(
        view: view,
        encoder: renderEncoder,
        commandBuffer: commandBuffer,
        worldToClipUniformsBuffer: uniformsBuffer,
        camera: camera
      )
    } catch {
      log.error("Failed to render GUI: \(error)")
      client.eventBus.dispatch(ErrorEvent(error: error, message: "Failed to render GUI"))
      return
    }
    profiler.pop()

    profiler.push(.commitToGPU)
    // Finish measurements for render statistics
    let cpuFinishTime = CFAbsoluteTimeGetCurrent()

    // Finish encoding the frame
    guard let drawable = view.currentDrawable else {
      log.warning("Failed to get current drawable")
      return
    }

    renderEncoder.endEncoding()

    profiler.push(.waitForRenderPassDescriptor)
    // Get current render pass descriptor
    guard let renderPassDescriptor = view.currentRenderPassDescriptor else {
      log.error("Failed to get the current render pass descriptor")
      client.eventBus.dispatch(ErrorEvent(
        error: RenderError.failedToGetCurrentRenderPassDescriptor,
        message: "RenderCoordinator failed to get the current render pass descriptor"
      ))
      return
    }
    profiler.pop()

    guard let quadRenderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
      log.error("Failed to create quad render encoder")
      client.eventBus.dispatch(ErrorEvent(
        error: RenderError.failedToCreateRenderEncoder,
        message: "RenderCoordinator failed to create render encoder"
      ))
      return
    }

    profiler.push(.renderOnScreen)
    do {
      try screenRenderer.render(
        view: view,
        encoder: quadRenderEncoder,
        commandBuffer: commandBuffer,
        worldToClipUniformsBuffer: uniformsBuffer,
        camera: camera
      )
    } catch {
      log.error("Failed to perform on-screen rendering: \(error)")
      client.eventBus.dispatch(ErrorEvent(error: error, message: "Failed to perform on-screen rendering pass."))
      return
    }
    profiler.pop()

    quadRenderEncoder.endEncoding()
    commandBuffer.present(drawable)

    let cpuElapsed = cpuFinishTime - cpuStartTime
    statistics.addMeasurement(
      frameTime: frameTime,
      cpuTime: cpuElapsed,
      gpuTime: nil
    )

    // Update statistics in gui
    guiRenderer.gui.renderStatistics = statistics

    commandBuffer.commit()
    profiler.pop()

    // Update frame capture state and stop current capture if necessary
    captureState?.framesRemaining -= 1
    if let captureState = captureState, captureState.framesRemaining == 0 {
      let captureManager = MTLCaptureManager.shared()
      captureManager.stopCapture()
      client.eventBus.dispatch(FinishFrameCaptureEvent(file: captureState.outputFile))

      self.captureState = nil
    }

    frameCount += 1
    profiler.endTrial()

    if frameCount % 60 == 0 {
      longestFrame = cpuElapsed
      // profiler.printSummary()
      profiler.clear()
    }
  }

  /// Captures the specified number of frames into a GPU trace file.
  public func captureFrames(count: Int, to file: URL) throws {
    let captureManager = MTLCaptureManager.shared()

    guard captureManager.supportsDestination(.gpuTraceDocument) else {
      throw RenderError.gpuTraceNotSupported
    }

    let captureDescriptor = MTLCaptureDescriptor()
    captureDescriptor.captureObject = device
    captureDescriptor.destination = .gpuTraceDocument
    captureDescriptor.outputURL = file

    do {
      try captureManager.startCapture(with: captureDescriptor)
    } catch {
      throw RenderError.failedToStartCapture(error)
    }

    captureState = CaptureState(framesRemaining: count, outputFile: file)
  }

  // MARK: Helper

  public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { }

  /// Gets the camera uniforms for the current frame.
  /// - Parameter view: The view that is being rendered to. Used to get aspect ratio.
  /// - Returns: A buffer containing the uniforms.
  private func getCameraUniforms(_ view: MTKView) -> MTLBuffer {
    let aspect = Float(view.drawableSize.width / view.drawableSize.height)
    camera.setAspect(aspect)

    let effectiveFovY = client.configuration.render.fovY * client.game.fovMultiplier()
    camera.setFovY(MathUtil.radians(from: effectiveFovY))

    client.game.accessPlayer { player in
      var eyePosition = Vec3f(player.position.smoothVector)
      eyePosition.y += 1.625 // TODO: don't hardcode this, use the player's eye height

      var cameraPosition = Vec3f(repeating: 0)

      var pitch = player.rotation.smoothPitch
      var yaw = player.rotation.smoothYaw

      switch player.camera.perspective {
        case .thirdPersonRear:
          cameraPosition.z += 3
          cameraPosition = (Vec4f(cameraPosition, 1) * MatrixUtil.rotationMatrix(x: pitch) * MatrixUtil.rotationMatrix(y: Float.pi + yaw)).xyz
          cameraPosition += eyePosition
        case .thirdPersonFront:
          pitch = -pitch
          yaw += Float.pi

          cameraPosition.z += 3
          cameraPosition = (Vec4f(cameraPosition, 1) * MatrixUtil.rotationMatrix(x: pitch) * MatrixUtil.rotationMatrix(y: Float.pi + yaw)).xyz
          cameraPosition += eyePosition
        case .firstPerson:
          cameraPosition = eyePosition
      }

      camera.setPosition(cameraPosition)
      camera.setRotation(xRot: pitch, yRot: yaw)
    }

    camera.cacheFrustum()
    return camera.getUniformsBuffer()
  }
}
