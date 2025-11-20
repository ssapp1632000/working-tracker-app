import 'package:hive/hive.dart';

/// Custom Hive adapter for Duration type
/// TypeId 100 to avoid conflicts with model adapters (0-3)
class DurationAdapter extends TypeAdapter<Duration> {
  @override
  final int typeId = 100;

  @override
  Duration read(BinaryReader reader) {
    final microseconds = reader.readInt();
    return Duration(microseconds: microseconds);
  }

  @override
  void write(BinaryWriter writer, Duration obj) {
    writer.writeInt(obj.inMicroseconds);
  }
}
