/// an RGBA color from a .vox color palette.
///
/// [r], [g], [b], and [a] are 8-bit values, `0x00 - 0xff` (0-255)
class VoxColor {
  /// red channel value, `0x00 - 0xff` (0-255)
  final int r;

  /// green channel value, `0x00 - 0xff` (0-255)
  final int g;

  /// blue channel value, `0x00 - 0xff` (0-255)
  final int b;

  /// alpha channel value, `0x00 - 0xff` (0-255). 255 is fully opaque.
  final int a;

  /// Create a [VoxColor] from individual 8-bit channel components.
  const VoxColor(this.r, this.g, this.b, [this.a = 0xff]);

  /// Create a [VoxColor] from a 32-bit `ARGB` format integer.
  factory VoxColor.fromInt(int argb) {
    // 11111111 00000000 11111111 00000000  <-- opaque green
    // '-- a--' '-- r--' '-- g--' '-- b--'
    //
    // extract a, r, g, b bytes by shifting and masking to select the lowest 8 bits
    final int a = (argb >> 24) & 0xff;
    final int r = (argb >> 16) & 0xff;
    final int g = (argb >> 8) & 0xff;
    final int b = argb & 0xff;

    return VoxColor(r, g, b, a);
  }

  @override
  String toString() {
    final StringBuffer sb = StringBuffer();
    sb.write('${r}'.padLeft(3, ' '));
    sb.write('r ');
    sb.write('${g}'.padLeft(3, ' '));
    sb.write('g ');
    sb.write('${b}'.padLeft(3, ' '));
    sb.write('b ');
    sb.write('${a}'.padLeft(3, ' '));
    sb.write('a');
    return sb.toString();
  }
  //String toString() => 'VoxColor(r${r}, g${g}, b${b}, a${a})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VoxColor &&
          runtimeType == other.runtimeType &&
          r == other.r &&
          g == other.g &&
          b == other.b &&
          a == other.a;

  @override
  int get hashCode => r.hashCode ^ g.hashCode ^ b.hashCode ^ a.hashCode;
}

/// a volume element (voxel) from a [VoxModel].
class VoxVoxel {
  /// local X coordinate (0-255).
  final int x;

  /// local Y coordinate (0-255).
  final int y;

  /// local Z coordinate (0-255).
  final int z;

  /// index into the color palette (1-255).
  ///
  /// use [VoxFile.getColor()] to retrieve the correct [VoxColor], as defined by the `IMAP` chunk.
  final int colorIndex;

  const VoxVoxel({
    required this.x,
    required this.y,
    required this.z,
    required this.colorIndex,
  });

  @override
  String toString() {
    final StringBuffer sb = StringBuffer();
    sb.write('${x}'.padLeft(2, ' '));
    sb.write('x ');
    sb.write('${y}'.padLeft(2, ' '));
    sb.write('y ');
    sb.write('${z}'.padLeft(2, ' '));
    sb.write('z ');
    sb.write('${colorIndex}'.padLeft(3, ' '));
    sb.write('i');
    return sb.toString();
  }
  //String toString() => 'VoxVoxel(x${x}, y${y}, z${z}, colorIndex: ${colorIndex})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VoxVoxel &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y &&
          z == other.z &&
          colorIndex == other.colorIndex;

  @override
  int get hashCode => x.hashCode ^ y.hashCode ^ z.hashCode ^ colorIndex.hashCode;
}

/// a collection of voxels from a .vox file.
class VoxModel {
  /// zero-based index of the model in the order it was read from the file.
  final int id;

  /// X-dimension (width) of the model.
  final int sizeX;

  /// Y-dimension (depth) of the model.
  final int sizeY;

  /// Z-dimension (height / gravity direction) of the model.
  final int sizeZ;

  /// list of voxels contained in this model.
  final List<VoxVoxel> voxels;

  const VoxModel({
    required this.id,
    required this.sizeX,
    required this.sizeY,
    required this.sizeZ,
    required this.voxels,
  });

  @override
  String toString() =>
      'VoxModel(id: $id, size: x${sizeX} × y${sizeY} × z${sizeZ}, voxels.length: ${voxels.length})';
}
