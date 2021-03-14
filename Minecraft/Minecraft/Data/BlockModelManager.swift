//
//  BlockModelManager.swift
//  Minecraft
//
//  Created by Rohan van Klinken on 13/3/21.
//

import Foundation
import simd
import os

enum BlockModelError: LocalizedError {
  case missingBlockModelFolder
  case missingBlockStatesFolder
  case failedToEnumerateBlockModels
  case failedToReadJSON
  case failedToParseJSON
  case invalidIdentifier
  case noFileForParent
  case noSuchBlockModel
  case invalidDisplayTag
  case invalidBlockPalette
  case invalidBlockIdentifier
  case invalidBlockStateJSON
  case nonExistentPropertyCombination
}

struct MojangBlockModelElementRotation {
  var origin: [Float]
  var axis: String
  var angle: Float
  var rescale: Bool
}

struct MojangBlockModelElementFace {
  var uv: [Float]
  var texture: String
  var cullface: String
  var rotation: Int
  var tintIndex: Int?
}

struct MojangBlockModelElement {
  var from: [Float]
  var to: [Float]
  var rotation: MojangBlockModelElementRotation
  var shade: Bool
  var faces: [String: MojangBlockModelElementFace]
}

struct MojangBlockModelDisplayLocation {
  var rotation: [Double]?
  var translation: [Double]?
  var scale: [Double]?
}

// https://minecraft.gamepedia.com/Model#Block_models
struct MojangBlockModel {
  var parent: Identifier?
  var ambientOcclusion: Bool
  var displayLocations: [String: MojangBlockModelDisplayLocation]
  var textures: [String: String]
  var elements: [MojangBlockModelElement]
}

enum CullFace: String {
  case down = "down"
  case up = "up"
  case north = "north"
  case south = "south"
  case west = "west"
  case east = "east"
}

struct BlockModelElementFace {
  var textureCoordinates: (simd_float2, simd_float2)
  var textureIndex: Int // the index of the texture to use in the block texture buffer
  var cullface: CullFace
  var rotation: Float
  var tintIndex: Int?
}

struct BlockModelElement {
  var modelMatrix: simd_float4x4
  var faces: [BlockModelElementFace]
}

struct BlockModel {
  var elements: [BlockModelElement]
}

// TODO: think of a better name for BlockModelManager
class BlockModelManager {
  var assetManager: AssetManager
  
  // TODO: make mojang block model map not global
  var identifierToMojangBlockModel: [Identifier: MojangBlockModel] = [:]
  
  var blockModelPalette: [Int: MojangBlockModel] = [:]
  
  init(assetManager: AssetManager) {
    self.assetManager = assetManager
  }
  
  func loadBlockModels() throws {
    // load the block models into the structs appended with Mojang (to make the data easier to manipulate)
    guard let blockModelFolder = assetManager.getBlockModelFolder() else {
      throw BlockModelError.missingBlockModelFolder
    }
    guard let blockModelFiles = try? FileManager.default.contentsOfDirectory(at: blockModelFolder, includingPropertiesForKeys: nil, options: []) else {
      throw BlockModelError.failedToEnumerateBlockModels
    }
    
    for file in blockModelFiles {
      let identifier = identifierFromFileName(file)
      do {
        let blockModel = try loadBlockModel(fileName: file)
        identifierToMojangBlockModel[identifier] = blockModel
      } catch {
        throw error
      }
    }
    
    // TODO: convert the mojang block models to a more efficient structure for rendering
  }
  
  func loadGlobalPalette() throws {
    try loadBlockModels()
    
    guard let blockStatesFolder = assetManager.getBlockStatesFolder() else {
      throw BlockModelError.missingBlockStatesFolder
    }
    let blockPalettePath = assetManager.storageManager.getBundledResourceByName("blocks", fileExtension: ".json")!
    guard let blockPaletteDict = try? JSON.fromURL(blockPalettePath).dict as? [String: [String: Any]] else {
      Logger.error("failed to load block palette from bundle")
      throw BlockModelError.invalidBlockPalette
    }
    for (identifierString, blockDict) in blockPaletteDict {
      let paletteBlockJSON = JSON(dict: blockDict)
      guard let identifier = try? Identifier(identifierString) else {
        throw BlockModelError.invalidBlockIdentifier
      }
      guard let paletteStatesArray = paletteBlockJSON.getArray(forKey: "states") as? [[String: Any]] else {
        throw BlockModelError.invalidBlockPalette
      }
//      let palettePropertiesJSON = paletteBlockJSON.getJSON(forKey: "properties")
      
      let blockStateFile = blockStatesFolder.appendingPathComponent("\(identifier.name).json")
      guard let blockStateJSON = try? JSON.fromURL(blockStateFile) else {
        Logger.debug("failed to load block state json: invalid json in file '\(identifier.name).json'")
        throw BlockModelError.invalidBlockStateJSON
      }
      
      // loop through all states for block (and skip multiparts)
      if let variants = blockStateJSON.getJSON(forKey: "variants") {
        if let variant = variants.getJSON(forKey: "") { // all states for block use one variant
          guard let variantString = variant.getString(forKey: "model") else {
            Logger.debug("failed to load block state json: variant '' doesn't specify a model on '\(identifier.name)'")
            throw BlockModelError.invalidBlockStateJSON
          }
          guard let variantBlockModelIdentifier = try? Identifier(variantString) else {
            throw BlockModelError.invalidIdentifier
          }
          for paletteStateDict in paletteStatesArray {
            let paletteStateJSON = JSON(dict: paletteStateDict)
            guard let stateId = paletteStateJSON.getInt(forKey: "id") else {
              Logger.debug("failed to load block palette: '\(identifier.name)' contains a state without an id")
              throw BlockModelError.invalidBlockPalette
            }
            blockModelPalette[stateId] = identifierToMojangBlockModel[variantBlockModelIdentifier]
          }
        } else { // a different variant for each state
          for paletteStateDict in paletteStatesArray {
            let paletteStateJSON = JSON(dict: paletteStateDict)
            guard let stateId = paletteStateJSON.getInt(forKey: "id") else {
              Logger.debug("failed to load block palette: '\(identifier.name)' contains a state without an id")
              throw BlockModelError.invalidBlockPalette
            }
            
            if let properties = paletteStateJSON.getJSON(forKey: "properties")?.dict as? [String: String] { // TODO: variant rotations
              let propertyNames = properties.keys.sorted()
              var variantKeyParts: [String] = []
              for propertyName in propertyNames {
                variantKeyParts.append("\(propertyName)=\(properties[propertyName]!)")
              }
              let variantKey = variantKeyParts.joined(separator: ",")
              if let variant = variants.getJSON(forKey: variantKey) {
                guard let variantModel = variant.getString(forKey: "model") else {
                  Logger.debug("failed to load block state json: variant '\(variantKey)' doesn't specify a model on '\(identifier.name)'")
                  throw BlockModelError.invalidBlockStateJSON
                }
                guard let variantModelIdentifier = try? Identifier(variantModel) else {
                  Logger.debug("variant's block model identifier is invalid, '\(variantModel)'")
                  throw BlockModelError.invalidIdentifier
                }
                blockModelPalette[stateId] = identifierToMojangBlockModel[variantModelIdentifier]
              } else {
                // at the moment block states that we can't handle are just passed
//                Logger.debug("no variant for '\(variantKey)' on '\(identifier.name)'")
//                throw BlockModelError.nonExistentPropertyCombination
              }
            } else {
              // handle blocks with multiple variants under the same name (randomly choose one each time)
            }
          }
        }
      }
    }
  }
  
  func loadBlockModel(fileName: URL) throws -> MojangBlockModel {
    guard let blockModelJSON = try? JSON.fromURL(fileName) else {
      throw BlockModelError.failedToReadJSON
    }
    
    do {
      var parent: Identifier? = nil
      if let parentName = blockModelJSON.getString(forKey: "parent") {
        guard let parentIdentifier = try? Identifier(parentName) else {
          throw BlockModelError.invalidIdentifier
        }
        parent = parentIdentifier
      }
      
      // actually read the block model
      let ambientOcclusion = blockModelJSON.getBool(forKey: "ambientocclusion") ?? true
      var displayLocations: [String: MojangBlockModelDisplayLocation] = [:]
      if let displayJSON = blockModelJSON.getJSON(forKey: "display")?.dict as? [String: [String: Any]] {
        for (location, transformations) in displayJSON {
          let transformationsJSON = JSON(dict: transformations)
          let rotation = transformationsJSON.getArray(forKey: "rotation") as? [Double]
          let translation = transformationsJSON.getArray(forKey: "translation") as? [Double]
          let scale = transformationsJSON.getArray(forKey: "scale") as? [Double]
          displayLocations[location] = MojangBlockModelDisplayLocation(rotation: rotation, translation: translation, scale: scale)
        }
      }
      let textureVariables: [String: String] = (blockModelJSON.getAny(forKey: "textures") as? [String: String]) ?? [:]
      
      var elements: [MojangBlockModelElement] = []
      if let elementsArray = blockModelJSON.getArray(forKey: "elements") as? [[String: Any]] {
        for elementDict in elementsArray {
          let elementJSON = JSON(dict: elementDict)
          let from = elementJSON.getArray(forKey: "from") as? [Float]
          let to = elementJSON.getArray(forKey: "to") as? [Float]
          
          let rotationJSON = elementJSON.getJSON(forKey: "rotation")
          let origin = rotationJSON?.getArray(forKey: "origin") as? [Float]
          let axis = rotationJSON?.getString(forKey: "axis")
          let angle = rotationJSON?.getFloat(forKey: "angle")
          let rescale = rotationJSON?.getBool(forKey: "rescale")
          let rotation = MojangBlockModelElementRotation( // TODO: reconsider these default values
            origin: origin ?? [0, 0 ,0],
            axis: axis ?? "x",
            angle: angle != nil ? Float(angle!) : 0,
            rescale: rescale ?? false
          )
          
          let shade = elementJSON.getBool(forKey: "shade")
          
          var faces: [String: MojangBlockModelElementFace] = [:]
          if let facesDict = elementJSON.getJSON(forKey: "faces")?.dict as? [String: [String: Any]] {
            for (faceName, faceDict) in facesDict {
              let faceJSON = JSON(dict: faceDict)
              let uv = faceJSON.getArray(forKey: "uv") as? [Float]
              let texture = faceJSON.getString(forKey: "texture")
              let cullface = faceJSON.getString(forKey: "cullface")
              let faceRotation = faceJSON.getInt(forKey: "rotation")
              let tintIndex = faceJSON.getInt(forKey: "tintindex")
              
              let face = MojangBlockModelElementFace( // TODO: reconsider block model face defaults and error handling
                uv: uv ?? [0, 0, 0, 0],
                texture: texture ?? "",
                cullface: cullface ?? "",
                rotation: faceRotation ?? 0,
                tintIndex: tintIndex
              )
              faces[faceName] = face
            }
          }
          
          let element = MojangBlockModelElement(
            from: from ?? [0, 0, 0],
            to: to ?? [16, 16, 16],
            rotation: rotation,
            shade: shade ?? true,
            faces: faces
          )
          
          elements.append(element)
        }
      }
      
      let blockModel = MojangBlockModel(
        parent: parent,
        ambientOcclusion: ambientOcclusion,
        displayLocations: displayLocations,
        textures: textureVariables,
        elements: elements
      )
      
      return blockModel
    } catch {
      Logger.error("failed to load block model: \(error)")
      throw BlockModelError.failedToParseJSON
    }
  }
  
  func identifierFromFileName(_ fileName: URL) -> Identifier {
    let blockModelName = fileName.deletingPathExtension().lastPathComponent
    let identifier = Identifier(name: "block/\(blockModelName)")
    return identifier
  }
  
  func blockModelForIdentifier(_ identifier: Identifier) throws -> MojangBlockModel {
    guard let blockModel = identifierToMojangBlockModel[identifier] else {
      throw BlockModelError.noSuchBlockModel
    }
    return blockModel
  }
}