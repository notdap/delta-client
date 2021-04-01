//
//  PacketWriter.swift
//  DeltaClient
//
//  Created by Rohan van Klinken on 12/12/20.
//

import Foundation

struct PacketWriter {
  var buffer: Buffer = Buffer([])
  
  mutating func writeBool(_ bool: Bool) {
    let byte: UInt8 = bool ? 1 : 0
    writeUnsignedByte(byte)
  }
  
  mutating func writeByte(_ byte: Int8) {
    buffer.writeSignedByte(byte)
  }
  
  mutating func writeUnsignedByte(_ unsignedByte: UInt8) {
    buffer.writeByte(unsignedByte)
  }
  
  mutating func writeShort(_ short: Int16) {
    buffer.writeSignedShort(short, endian: .big)
  }
  
  mutating func writeUnsignedShort(_ unsignedShort: UInt16) {
    buffer.writeShort(unsignedShort, endian: .big)
  }
  
  mutating func writeInt(_ int: Int32) {
    buffer.writeSignedInt(int, endian: .big)
  }
  
  mutating func writeLong(_ long: Int64) {
    buffer.writeSignedLong(long, endian: .big)
  }
  
  mutating func writeFloat(_ float: Float) {
    buffer.writeFloat(float, endian: .big)
  }
  
  mutating func writeDouble(_ double: Double) {
    buffer.writeDouble(double, endian: .big)
  }
  
  mutating func writeString(_ string: String) {
    let length = string.utf8.count
    precondition(length < 32767, "string too long to write")
    
    writeVarInt(Int32(length))
    buffer.writeString(string)
  }
  
  mutating func writeIdentifier(_ identifier: Identifier) {
    writeString(identifier.toString())
  }
  
  mutating func writeVarInt(_ varInt: Int32) {
    buffer.writeVarInt(varInt)
  }
  
  mutating func writeVarLong(_ varLong: Int64) {
    buffer.writeVarLong(varLong)
  }
  
  // IMPLEMENT: Entity Metadata, Position, Angle
  
  mutating func writeItemStack(_ itemStack: ItemStack) {
    writeBool(itemStack.isEmpty)
    if itemStack.isEmpty {
      let item = itemStack.item!
      writeVarInt(Int32(item.id))
      writeByte(Int8(itemStack.count))
      writeNBT(item.nbt ?? NBTCompound())
    }
  }
  
  mutating func writeNBT(_ nbtCompound: NBTCompound) {
    var compound = nbtCompound
    buffer.writeBytes(compound.pack())
  }
  
  mutating func writeUUID(_ uuid: UUID) {
    let bytes = uuid.toBytes()
    buffer.writeBytes(bytes)
  }
  
  mutating func writeByteArray(_ byteArray: [UInt8]) {
    buffer.writeBytes(byteArray)
  }
  
  mutating func writePosition(_ position: Position) {
    var val: UInt64 = (UInt64(position.x) & 0x3FFFFFF) << 38
    val |= (UInt64(position.z) & 0x3FFFFFF) << 12
    val |= UInt64(position.y) & 0xFFF
    buffer.writeLong(val, endian: .big)
  }
  
  mutating func writeEntityPosition(_ entityPosition: EntityPosition) {
    writeDouble(entityPosition.x)
    writeDouble(entityPosition.y)
    writeDouble(entityPosition.z)
  }
}