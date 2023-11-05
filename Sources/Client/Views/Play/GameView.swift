import SwiftUI
import DeltaCore
import DeltaRenderer
import Combine

enum GameState {
  case connecting
  case loggingIn
  case downloadingChunks(numberReceived: Int, total: Int)
  case playing
  case gpuFrameCaptureComplete(file: URL)
}

enum OverlayState {
  case menu
  case settings
}

class Box<T> {
  var value: T

  init(_ initialValue: T) {
    self.value = initialValue
  }
}

class GameViewModel: ObservableObject {
  @Published var state = StateWrapper<GameState>(initial: .connecting)
  @Published var overlayState = StateWrapper<OverlayState>(initial: .menu)
  @Published var showInGameMenu = false

  @Binding var inputCaptured: Bool

  var client: Client
  var inputDelegate: ClientInputDelegate
  var renderCoordinator: RenderCoordinator
  var downloadedChunksCount = Box(0)
  var serverDescriptor: ServerDescriptor
  var storage: StorageDirectory?
  var managedConfig: ManagedConfig

  var cancellables: [AnyCancellable] = []

  init(
    client: Client,
    inputDelegate: ClientInputDelegate,
    renderCoordinator: RenderCoordinator,
    serverDescriptor: ServerDescriptor,
    inputCaptured: Binding<Bool>,
    managedConfig: ManagedConfig
  ) {
    self.client = client
    self.inputDelegate = inputDelegate
    self.renderCoordinator = renderCoordinator
    self.serverDescriptor = serverDescriptor
    _inputCaptured = inputCaptured
    self.managedConfig = managedConfig

    watch(state)
    watch(overlayState)
  }

  func registerEventHandler(using modal: Modal, appState: StateWrapper<AppState>) {
    client.eventBus.registerHandler { [weak self] event in
      guard let self = self else { return }
      do {
        try self.handleClientEvent(event)
      } catch {
        modal.error(error)
        appState.update(to: .serverList)
      }
    }
  }

  func watch<T: ObservableObject>(_ value: T) {
    self.cancellables.append(value.objectWillChange.sink { [weak self] _ in
      self?.objectWillChange.send()
    })
  }

  func closeMenu() {
    inputDelegate.mouseSensitivity = managedConfig.mouseSensitivity
    inputCaptured = true

    withAnimation(nil) {
      showInGameMenu = false
      inputDelegate.captureCursor()
    }
  }

  enum GameViewError: LocalizedError {
    case noAccountSelected
    case failedToRefreshAccount
    case failedToSendJoinServerRequest
    case connectionFailed
    case disconnectedDuringLogin
    case disconnectedDuringPlay
    case failedToDecodePacket
    case failedToHandlePacket
    case failedToStartFrameCapture

    var errorDescription: String? {
      switch self {
        case .noAccountSelected:
          return "Please login and select an account before joining a server."
        case .failedToRefreshAccount:
          return "Failed to refresh account."
        case .failedToSendJoinServerRequest:
          return "Failed to send join server request."
        case .connectionFailed:
          return "Failed to connect to server."
        case .disconnectedDuringLogin:
          return "Disconnected from server during login."
        case .disconnectedDuringPlay:
          return "Disconnected from server during play."
        case .failedToDecodePacket:
          return "Failed to decode packet."
        case .failedToHandlePacket:
          return "Failed to handle packet."
        case .failedToStartFrameCapture:
          return "Failed to start frame capture."
      }
    }
  }

  func joinServer(_ descriptor: ServerDescriptor) async throws {
    // Get the account to use
    guard let account = managedConfig.config.selectedAccount else {
      throw GameViewError.noAccountSelected
    }

    // Refresh the account (if it's an online account) and then join the server
    let refreshedAccount: Account
    do {
      refreshedAccount = try await managedConfig.selectedAccountRefreshedIfNecessary()
    } catch {
      throw GameViewError.failedToRefreshAccount
        .with("Username", account.username)
        .becauseOf(error)
    }

    do {
      try self.client.joinServer(
        describedBy: descriptor,
        with: refreshedAccount)
    } catch {
      throw GameViewError.failedToSendJoinServerRequest.becauseOf(error)
    }
  }

  func handleClientEvent(_ event: Event) throws {
    switch event {
      case let connectionFailedEvent as ConnectionFailedEvent:
        throw GameViewError.connectionFailed.with("Address", serverDescriptor).becauseOf(connectionFailedEvent.networkError)
      case _ as LoginStartEvent:
        state.update(to: .loggingIn)
      case _ as JoinWorldEvent:
        // Approximation of the number of chunks the server will send (used in progress indicator)
        let totalChunksToReceieve = Int(Foundation.pow(Double(client.game.maxViewDistance * 2 + 3), 2))
        state.update(to: .downloadingChunks(numberReceived: 0, total: totalChunksToReceieve))
      case _ as World.Event.AddChunk:
        ThreadUtil.runInMain {
          if case let .downloadingChunks(_, total) = state.current {
            // An intermediate variable is used to reduce the number of SwiftUI updates generated by downloading chunks
            downloadedChunksCount.value += 1
            if downloadedChunksCount.value % 25 == 0 {
              state.update(to: .downloadingChunks(numberReceived: downloadedChunksCount.value, total: total))
            }
          }
        }
      case _ as TerrainDownloadCompletionEvent:
        state.update(to: .playing)
      case let disconnectEvent as PlayDisconnectEvent:
        throw GameViewError.disconnectedDuringPlay.with("Reason", disconnectEvent.reason)
      case let disconnectEvent as LoginDisconnectEvent:
        throw GameViewError.disconnectedDuringLogin.with("Reason", disconnectEvent.reason)
      case let packetError as PacketHandlingErrorEvent:
        throw GameViewError.failedToHandlePacket.with("Id", packetError.packetId.hexWithPrefix).with("Reason", packetError.error)
      case let packetError as PacketDecodingErrorEvent:
        throw GameViewError.failedToDecodePacket.with("Id", packetError.packetId.hexWithPrefix).with("Reason", packetError.error)
      case let generalError as ErrorEvent:
        if let message = generalError.message {
          throw RichError(message).becauseOf(generalError.error)
        } else {
          throw generalError.error
        }
      case let event as KeyPressEvent where event.input == .performGPUFrameCapture:
        guard let outputFile = storage?.uniqueGPUCaptureFile() else {
          // TODO: GameViewModel as a whole is a mess, it should be created in GameView's onAppear
          //   instead of the init so that we can access environment values and environment objects
          //   in a much safer way.
          return
        }
        do {
          try renderCoordinator.captureFrames(count: 10, to: outputFile)
        } catch {
          throw GameViewError.failedToStartFrameCapture.becauseOf(error)
        }
      case _ as OpenInGameMenuEvent:
        inputDelegate.releaseCursor()
        overlayState.update(to: .menu)
        showInGameMenu = true
        inputCaptured = false
      case _ as ReleaseCursorEvent:
        inputDelegate.releaseCursor()
      case _ as CaptureCursorEvent:
        inputDelegate.captureCursor()
      case let event as FinishFrameCaptureEvent:
        inputDelegate.releaseCursor()
        state.update(to: .gpuFrameCaptureComplete(file: event.file))
      default:
        break
    }
  }
}

struct GameView: View {
  @EnvironmentObject var appState: StateWrapper<AppState>
  @EnvironmentObject var modal: Modal
  @EnvironmentObject var pluginEnvironment: PluginEnvironment
  @EnvironmentObject var managedConfig: ManagedConfig

  @ObservedObject var model: GameViewModel

  let serverDescriptor: ServerDescriptor

  init(
    serverDescriptor: ServerDescriptor,
    managedConfig: ManagedConfig,
    resourcePack: Box<ResourcePack>,
    inputCaptureEnabled: Binding<Bool>,
    delegateSetter setDelegate: (InputDelegate) -> Void
  ) {
    self.serverDescriptor = serverDescriptor

    // TODO: Update the flow of the game view so that we don't have to create a dummy
    //   config.
    let client = Client(
      resourcePack: resourcePack.value,
      configuration: managedConfig
    )

    // Setup input system
    let inputDelegate = ClientInputDelegate(for: client, mouseSensitivity: managedConfig.mouseSensitivity)
    setDelegate(inputDelegate)

    // Create render coordinator
    let renderCoordinator = RenderCoordinator(client)

    model = GameViewModel(
      client: client,
      inputDelegate: inputDelegate,
      renderCoordinator: renderCoordinator,
      serverDescriptor: serverDescriptor,
      inputCaptured: inputCaptureEnabled,
      managedConfig: managedConfig
    )
  }

  var body: some View {
    VStack {
      switch model.state.current {
        case .connecting:
          connectingView
        case .loggingIn:
          loggingInView
        case .downloadingChunks(let numberReceived, let total):
          VStack {
            Text("Downloading chunks...")
            HStack {
              ProgressView(value: Double(numberReceived) / Double(total))
              Text("\(numberReceived) of \(total)")
            }
              .frame(maxWidth: 200)
            Button("Cancel", action: disconnect)
              .buttonStyle(SecondaryButtonStyle())
              .frame(width: 150)
          }
        case .playing:
          ZStack {
            gameView
            overlayView
          }
        case .gpuFrameCaptureComplete(let file):
          VStack {
            Text("GPU frame capture complete")

            Group {
              #if os(macOS)
              Button("Show in finder") {
                NSWorkspace.shared.activateFileViewerSelecting([file])
              }.buttonStyle(SecondaryButtonStyle())
              #elseif os(iOS)
              // TODO: Add a file sharing menu for iOS
              Text("I have no clue how to get hold of the file")
              #else
              #error("Unsupported platform, no file opening method")
              #endif

              Button("OK") {
                model.state.pop()
              }.buttonStyle(PrimaryButtonStyle())
            }.frame(width: 200)
          }
      }
    }
    .onAppear {
      // Setup plugins
      pluginEnvironment.addEventBus(model.client.eventBus)
      pluginEnvironment.handleWillJoinServer(server: serverDescriptor, client: model.client)

      model.registerEventHandler(using: modal, appState: appState)

      // Connect to server
      Task {
        do {
          try await model.joinServer(serverDescriptor)
        } catch {
          modal.error(error)
          appState.update(to: .serverList)
        }
      }
    }
    .onDisappear {
      model.client.disconnect()
      model.renderCoordinator = RenderCoordinator(model.client)
      model.inputDelegate.releaseCursor()
    }
  }

  var connectingView: some View {
    VStack {
      Text("Establishing connection...")
      Button("Cancel", action: disconnect)
        .buttonStyle(SecondaryButtonStyle())
        .frame(width: 150)
    }
  }

  var loggingInView: some View {
    VStack {
      Text("Logging in...")
      Button("Cancel", action: disconnect)
        .buttonStyle(SecondaryButtonStyle())
        .frame(width: 150)
    }
  }

  var gameView: some View {
    ZStack {
      // Renderer
      if #available(macOS 13, iOS 16, *) {
        MetalView(renderCoordinator: model.renderCoordinator)
          .onAppear {
            model.inputDelegate.captureCursor()
            model.inputCaptured = true
          }
      }
      else {
        MetalViewClass(renderCoordinator: model.renderCoordinator)
          .onAppear {
            model.inputDelegate.captureCursor()
            model.inputCaptured = true
          }
      }

      #if os(iOS)
      movementControls
      #endif
    }
  }

  /// In-game menu overlay.
  var overlayView: some View {
    VStack {
      if model.showInGameMenu {
        GeometryReader { geometry in
          VStack {
            switch model.overlayState.current {
              case .menu:
                VStack {
                  Button("Back to game", action: model.closeMenu)
                    .keyboardShortcut(.escape, modifiers: [])
                    .buttonStyle(PrimaryButtonStyle())
                  Button("Settings", action: { model.overlayState.update(to: .settings) })
                    .buttonStyle(SecondaryButtonStyle())
                  Button("Disconnect", action: disconnect)
                    .buttonStyle(SecondaryButtonStyle())
                }
                .frame(width: 200)
              case .settings:
                SettingsView(isInGame: true, client: model.client, onDone: {
                  model.overlayState.update(to: .menu)
                })
            }
          }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.black.opacity(0.702), alignment: .center)
        }
      }
    }
  }

  #if os(iOS)
  var movementControls: some View {
    VStack {
      Spacer()
      HStack {
        HStack(alignment: .bottom) {
          movementControl("a", .strafeLeft)
          VStack {
            movementControl("w", .moveForward)
            movementControl("s", .moveBackward)
          }
          movementControl("d", .strafeRight)
        }
        Spacer()
        VStack {
          movementControl("*", .jump)
          movementControl("_", .sneak)
        }
      }
    }
  }

  func movementControl(_ label: String, _ input: Input) -> some View {
    return ZStack {
      Color.blue.frame(width: 50, height: 50)
      Text(label)
    }.onLongPressGesture(
      minimumDuration: 100000000000,
      maximumDistance: 50,
      perform: { return },
      onPressingChanged: { isPressing in
        if isPressing {
          model.client.press(input)
        } else {
          model.client.release(input)
        }
      }
    )
  }
  #endif

  func disconnect() {
    appState.update(to: .serverList)
  }
}
