// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message_hive.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class MessageAdapter extends TypeAdapter<Message> {
  @override
  final int typeId = 0;

  @override
  Message read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Message(
      senderID: fields[0] as String,
      senderEmail: fields[1] as String,
      senderName: fields[2] as String,
      receiverID: fields[3] as String,
      message: fields[4] as String,
      timestamp: fields[5] as DateTime,
      type: fields[6] as String,
      caption: fields[7] as String?,
      status: fields[8] as String?,
      replyToId: fields[9] as String?,
      replyToMessage: fields[10] as String?,
      replyToSender: fields[11] as String?,
      replyToType: fields[12] as String?,
      voiceDuration: fields[13] as int?,
      thumbnailUrl: fields[14] as String?,
      localId: fields[15] as String,
      fireStoreId: fields[16] as String?,
      syncStatus: fields[17] as MessageSyncStatus,
      localFilePath: fields[18] as String?,
      isEdited: fields[19] as bool?,
      editedAt: fields[20] as DateTime?,
      deletedFor: (fields[21] as List).cast<String>(),
    );
  }

  @override
  void write(BinaryWriter writer, Message obj) {
    writer
      ..writeByte(22)
      ..writeByte(0)
      ..write(obj.senderID)
      ..writeByte(1)
      ..write(obj.senderEmail)
      ..writeByte(2)
      ..write(obj.senderName)
      ..writeByte(3)
      ..write(obj.receiverID)
      ..writeByte(4)
      ..write(obj.message)
      ..writeByte(5)
      ..write(obj.timestamp)
      ..writeByte(6)
      ..write(obj.type)
      ..writeByte(7)
      ..write(obj.caption)
      ..writeByte(8)
      ..write(obj.status)
      ..writeByte(9)
      ..write(obj.replyToId)
      ..writeByte(10)
      ..write(obj.replyToMessage)
      ..writeByte(11)
      ..write(obj.replyToSender)
      ..writeByte(12)
      ..write(obj.replyToType)
      ..writeByte(13)
      ..write(obj.voiceDuration)
      ..writeByte(14)
      ..write(obj.thumbnailUrl)
      ..writeByte(15)
      ..write(obj.localId)
      ..writeByte(16)
      ..write(obj.fireStoreId)
      ..writeByte(17)
      ..write(obj.syncStatus)
      ..writeByte(18)
      ..write(obj.localFilePath)
      ..writeByte(19)
      ..write(obj.isEdited)
      ..writeByte(20)
      ..write(obj.editedAt)
      ..writeByte(21)
      ..write(obj.deletedFor);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class MessageSyncStatusAdapter extends TypeAdapter<MessageSyncStatus> {
  @override
  final int typeId = 1;

  @override
  MessageSyncStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return MessageSyncStatus.pending;
      case 1:
        return MessageSyncStatus.syncing;
      case 2:
        return MessageSyncStatus.synced;
      case 3:
        return MessageSyncStatus.failed;
      default:
        return MessageSyncStatus.pending;
    }
  }

  @override
  void write(BinaryWriter writer, MessageSyncStatus obj) {
    switch (obj) {
      case MessageSyncStatus.pending:
        writer.writeByte(0);
        break;
      case MessageSyncStatus.syncing:
        writer.writeByte(1);
        break;
      case MessageSyncStatus.synced:
        writer.writeByte(2);
        break;
      case MessageSyncStatus.failed:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageSyncStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
