import Foundation

public struct SpawnPlayerPacket: ClientboundPacket {
  public static let id: Int = 0x04
  
  /// The player's entity id.
  public var entityId: Int
  /// The player's UUID.
  public var playerUUID: UUID
  /// The player's position.
  public var position: SIMD3<Double>
  /// The player's pitch.
  public var pitch: Float
  /// The player's yaw.
  public var yaw: Float
  
  public init(from packetReader: inout PacketReader) throws {
    entityId = packetReader.readVarInt()
    playerUUID = try packetReader.readUUID()
    position = packetReader.readEntityPosition()
    (pitch, yaw) = packetReader.readEntityRotation()
  }
  
  public func handle(for client: Client) throws {
    client.game.createEntity(id: entityId) {
      LivingEntity()
      PlayerEntity()
      EntityKindId(Registry.shared.entityRegistry.playerEntityKindId)
      EntityId(entityId)
      EntityUUID(playerUUID)
      EntityOnGround(true)
      EntityPosition(position)
      EntityVelocity(0, 0, 0)
      EntityRotation(pitch: pitch, yaw: yaw)
    }
  }
}
