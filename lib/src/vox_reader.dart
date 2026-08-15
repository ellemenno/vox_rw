import 'dart:typed_data';

/// utility for decoding .vox file bytes
///
/// extracts the following types:
/// - byte (uint8) &rarr; [int]
/// - integer (int32) &rarr; [int]
/// - float (float32) &rarr; [double]
/// - string (character codes) &rarr; [String]
/// - prefixed string (integer length followed by character bytes) &rarr; [String]
/// - dictionary (integer count followed by pairs of key-value prefixed strings) &rarr; [Map] (`<String, String>{}`)
class VoxReader {
  final Uint8List _bytes;
  int _offset = 0;

  /// construct from a list of integer bytes, e.g. [Uint8List], or [int]
  VoxReader(List<int> bytes) : _bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

  /// construct from a [ByteData] instance
  VoxReader.fromByteData(ByteData data)
      : _bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

  /// zero-based index tracking how many bytes have been read.
  ///
  /// values can range from 0 to [length]-1
  int get offset => _offset;

  /// total number of bytes available to read.
  int get length => _bytes.length;

  /// `true` when more bytes are available to read from [offset].
  bool get hasMore => _offset < _bytes.length;

  /// read a byte as an unsigned 8-bit integer (`uint8`), value range of 0 to 255.
  ///
  /// dart doesn't have an instantiable `uint8` data type; result is given as [int], similar to [Uint8List] behavior.
  /// throws [RangeError] if there are not enough bytes from [offset] to [length] for reading this type
  int readUint8() {
    if (_offset + 1 > _bytes.length) {
      throw RangeError('Read out of bounds: offset=$_offset, length=1, total=${_bytes.length}');
    }
    final int value = _bytes[_offset];
    _offset += 1;
    return value;
  }

  /// read 4 bytes as a signed little-endian 32-bit integer ([int]), value range of -2,147,483,648 to 2,147,483,647.
  ///
  /// throws [RangeError] if there are not enough bytes from [offset] to [length] for reading this type
  int readInt32() {
    if (_offset + 4 > _bytes.length) {
      throw RangeError('Read out of bounds: offset=$_offset, length=4, total=${_bytes.length}');
    }
    // read little-endian 32-bit integer
    final ByteData byteData = ByteData.sublistView(_bytes, _offset, _offset + 4);
    final int value = byteData.getInt32(0, Endian.little);
    _offset += 4;
    return value;
  }

  /// read 4 bytes as a signed little-endian 32-bit float ([double]).
  ///
  /// throws [RangeError] if there are not enough bytes from [offset] to [length] for reading this type
  double readFloat32() {
    if (_offset + 4 > _bytes.length) {
      throw RangeError('Read out of bounds: offset=$_offset, length=4, total=${_bytes.length}');
    }
    // read little-endian 32-bit float
    final ByteData byteData = ByteData.sublistView(_bytes, _offset, _offset + 4);
    final double value = byteData.getFloat32(0, Endian.little);
    _offset += 4;
    return value;
  }

  /// read [length] bytes into a [Uint8List].
  ///
  /// throws [RangeError] if there are not enough bytes from [offset] to [length] for reading this type
  List<int> readBytes(int length) {
    if (_offset + length > _bytes.length) {
      throw RangeError(
          'Read out of bounds: offset=$_offset, length=$length, total=${_bytes.length}');
    }
    final Uint8List result = _bytes.sublist(_offset, _offset + length);
    _offset += length;
    return result;
  }

  /// read [length] bytes as dart character codes and construct a [String] from them (see [String.fromCharCodes()]).
  ///
  /// a [RangeError] will be thrown if there are not enough bytes from [offset] to [length] for reading this type
  String readString(int length) {
    final List<int> bytes = readBytes(length);
    return String.fromCharCodes(bytes);
  }

  /// read an `int32` and use its value as the length parameter for [readString()].
  ///
  /// a [RangeError] will be thrown if there are not enough bytes from [offset] to [length] for reading this type
  String readStringPrefixed() {
    final int len = readInt32();
    if (len < 0) {
      throw FormatException('Invalid string length: $len');
    }
    return readString(len);
  }

  /// read an `int32` and use its value as the number of prefixed string pairs to consume and construct a key-value map.
  ///
  /// a [RangeError] will be thrown if there are not enough bytes from [offset] to [length] for reading this type
  Map<String, String> readDict() {
    final int count = readInt32();
    final Map<String, String> dict = <String, String>{};
    for (int i = 0; i < count; i++) {
      final String key = readStringPrefixed();
      final String value = readStringPrefixed();
      dict[key] = value;
    }
    return dict;
  }
}
