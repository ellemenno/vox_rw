import 'dart:io';
import 'dart:typed_data';

import 'vox_core.dart';
import 'vox_extensions.dart';
import 'vox_reader.dart';
import 'vox_file.dart';

// convenience struct for working with labeled data chunks from a .vox file
class _VoxRawChunk {
  final String id;
  final Uint8List content;
  final List<_VoxRawChunk> children;
  const _VoxRawChunk(this.id, this.content, this.children);
}

// convenience struct for voxel dimensions
class _VoxSize {
  final int x;
  final int y;
  final int z;
  const _VoxSize(this.x, this.y, this.z);
}

class _VoxLogger {
  late final String _hbarSolid;
  late final String _hbarDashy;
  late final StringBuffer _logBuffer;
  bool tracing;

  _VoxLogger({StringBuffer? buffer, this.tracing = true, int barLength = 80}) {
    _logBuffer = buffer ?? StringBuffer();
    _hbarSolid = '--' * (barLength ~/ 2);
    _hbarDashy = '- ' * (barLength ~/ 2);
  }

  bool get isEmpty => _logBuffer.isEmpty;

  bool get isNotEmpty => _logBuffer.isNotEmpty;

  int get length => _logBuffer.length;

  void clear() {
    if (tracing) _logBuffer.clear();
  }

  void add(String s) {
    if (tracing) _logBuffer.write(s);
  }

  void line(String s) {
    if (tracing) _logBuffer.writeln(s);
  }

  void barS() {
    if (tracing) _logBuffer.writeln(_hbarSolid);
  }

  void barD() {
    if (tracing) _logBuffer.writeln(_hbarDashy);
  }

  @override
  String toString() => _logBuffer.toString();
}

/// utility for parsing MagicaVoxel `.vox` format files.
///
/// VOX files follow a Resource Interchange File Format (RIFF) convention of labeled chunks.
///
/// file format specifications and notes:
/// - https://github.com/ephtracy/voxel-model/blob/master/MagicaVoxel-file-format-vox.txt
/// - https://github.com/ephtracy/voxel-model/blob/master/MagicaVoxel-file-format-vox-extension.txt
///
/// core format data chunks:
/// - `MAIN` - root node
/// - `PACK` (optional) - number of models in file
/// - `SIZE` - model dimensions in x, y, z
/// - `XYZI` - individual voxel data (position, color palette index)
/// - `RGBA` (optional) - color palette
///
/// extended format data chunks:
/// - `nTRN`, `nGRP`, `nSHP` - scene graph nodes (T -> G or S, G -> one or more T)
/// - `MATL` - surface material properties for rendering
/// - `MATT` - (deprecated, use MATL) material attributes
/// - `LAYR` - layer metadata
/// - `rOBJ` - rendering attributes
/// - `rCAM` - render cameras
/// - `NOTE` - palette notes
/// - `IMAP` - palette index mapping
///
/// ```txt
/// ----------------------------------------------------------------------------
/// MagicaVoxel core chunks
/// ----------------------------------------------------------------------------
/// # Bytes  | Type       | Value
/// ----------------------------------------------------------------------------
/// 1x4      | char8      | file id  'VOX ' : V-O-X-space
/// 4        | int32      | version number : 200 or 150
///  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
/// 1x4      | char8      | chunk id 'MAIN' : root chunk
/// 4        | int32      | num bytes of MAIN chunk content : 0
/// 4        | int32      | num bytes of children chunks
///  - - optional- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
/// 1x4      | char8      | chunk id 'PACK' : if absent, only one model in file
/// 4        | int32      | num bytes of PACK chunk content
/// 4        | int32      | num bytes of children chunks
/// 4        | int32      | numModels : num of SIZE and XYZI chunk pairs
///  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
/// 1x4      | char8      | chunk id 'SIZE'
/// 4        | int32      | num bytes of SIZE chunk content
/// 4        | int32      | num bytes of children chunks : 0
/// 4        | int32      | size x
/// 4        | int32      | size y
/// 4        | int32      | size z : gravity direction
///  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
/// 1x4      | char8      | chunk id 'XYZI'
/// 4        | int32      | num bytes of XYZI chunk content
/// 4        | int32      | num bytes of children chunks : 0
/// 4        | int32      | numVoxels : num of voxels in model (N)
/// 4 x N    | int32      | (x, y, z, colorIndex) : 1 byte for each component
///  - - optional (if PACK of models, numModels-1 SIZE & XYZI chunks go here)- -
///          |            |           SIZE
///          |            |           ...
///          |            |           XYZI
///          |            |           ...
///  - - optional (if absent, use default palette) - - - - - - - - - - - - - - -
/// 1x4      | char8      | chunk id 'RGBA' : RGBA[0-254] --> colorIndex[1-255]
///          |            |                 : RGBA[255]   --> colorIndex[0]
/// 4        | int32      | num bytes of RGBA chunk content
/// 4        | int32      | num bytes of children chunks : 0
/// 4 x 256  | int32      | (R, G, B, A) : 1 byte for each component
/// ----------------------------------------------------------------------------
/// ```
/// https://github.com/ephtracy/voxel-model/blob/master/MagicaVoxel-file-format-vox.txt
///
/// ```txt
/// ----------------------------------------------------------------------------
/// MagicaVoxel extension types
/// ----------------------------------------------------------------------------
/// # Bytes  | Type       | Value
/// ----------------------------------------------------------------------------
///  - - STRING- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
/// 4        | int32      | character buffer size N (in bytes)
/// 1xN      | char8      | character code
///  - - DICT- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
/// 4        | int32      | key-value pair count N
/// {
///   ..     | STRING     | key
///   ..     | STRING     | value
/// } xN
///  - - ROTATION- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
/// 1        | uint8      | row-major rotation matrix stored in the bits of a byte
/// ----------------------------------------------------------------------------
///
/// ----------------------------------------------------------------------------
/// MagicaVoxel extension chunks
/// ----------------------------------------------------------------------------
/// # Bytes  | Type       | Value
///  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
/// 1x4      | char8      | chunk id 'nTRN'
/// 4        | int32      | node id
/// (        | DICT       | node attributes
///   ..     | STRING     | key: '_name'
///   ..     | STRING     | val: node name
///   ..     | STRING     | key: '_hidden'
///   1      | unit8 (0/1)| val: 1 if node is hidden, else 0
/// )
/// 4        | int32      | child node id
/// 4        | int32 (-1) | reserved id (must be -1)
/// 4        | int32      | layer id
/// 4        | int32      | number of frames N (must be >0)
/// {        +            + for each frame
///   (      | DICT       | frame attributes
///     ..   | STRING     | key: '_r'
///     1    | ROTATION   | val: rotation matrix
///     ..   | STRING     | key: '_t'
///     4x3  | int32x3    | val: translation x,y,z
///     ..   | STRING     | key: '_f'
///     4    | int32      | val: frame index, zero-based
///   )
/// } xN frames
///  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
/// 1x4      | char8      | chunk id 'nGRP'
/// 4        | int32      | node id
/// (        | DICT       | node attributes
///   ..     | STRING     | key: '_name'
///   ..     | STRING     | val: node name
///   ..     | STRING     | key: '_hidden'
///   1      | unit8 (0/1)| val: 1 if node is hidden, else 0
/// )
/// 4        | int32      | number of children N
/// {        +            + for each child
///   4      | int32      | child node id
/// } xN children
///  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
/// 1x4      | char8      | chunk id 'nSHP'
/// 4        | int32      | node id
/// (        | DICT       | node attributes
///   ..     | STRING     | key: '_name'
///   ..     | STRING     | val: node name
///   ..     | STRING     | key: '_hidden'
///   1      | unit8 (0/1)| val: 1 if node is hidden, else 0
/// )
/// 4        | int32      | number of models N (must be >0)
/// {        +            + for each model
///   (      | DICT       | model attributes
///     ..   | STRING     | key: '_f'
///     4    | int32      | val: frame index, zero-based
///   )
/// } xN models
///  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
/// 1x4      | char8      | chunk id 'MATL' (replaced MATT)
/// 4        | int32      | material id (aligns with color palette ids)
/// (        | DICT       | material properties
///   ..     | STRING     | key: '_type'
///   ..     | STRING     | val: material (_diffuse, _metal, _glass, _emit, _media)
///   ..     | STRING     | key: '_media_type'
///   ..     | STRING     | val: media (_sss, _scatter, ??)
///   ..     | STRING     | key: '_media'
///   ..     | int(STR)   | val: string parsed as int32
///   ..     | STRING     | key: '_weight'
///   ..     | float(STR) | val: string parsed as float, range 0 - 1
///   ..     | STRING     | key: '_rough' (roughness)
///   ..     | float(STR) | val: string parsed as float
///   ..     | STRING     | key: '_spec' (specularity / shininess)
///   ..     | float(STR) | val: string parsed as float
///   ..     | STRING     | key: '_ior' (index of refraction)
///   ..     | float(STR) | val: string parsed as float
///   ..     | STRING     | key: '_att' (attenuation)
///   ..     | float(STR) | val: string parsed as float
///   ..     | STRING     | key: '_flux'
///   ..     | float(STR) | val: string parsed as float
///   ..     | STRING     | key : _g
///   ..     | float(STR) | val: string parsed as float
///   ..     | STRING     | key : _d
///   ..     | float(STR) | val: string parsed as float
///   ..     | STRING     | key: '_alpha'
///   ..     | float(STR) | val: string parsed as float
///   ..     | STRING     | key: '_trans'
///   ..     | float(STR) | val: string parsed as float
///   ..     | STRING     | key: '_metal'
///   ..     | float(STR) | val: string parsed as float
///   ..     | STRING     | key: '_plastic' (value 0/1 as boolean flag)
///   ..     | bool       | val: true if key is present, else false
/// )
///  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
/// 1x4      | char8      | chunk id 'MATT' (deprecated for MATL), if absent, use diffuse
/// 4        | int32      | num bytes of MATT chunk content
/// 4        | int32      | num bytes of children chunks
/// 4        | int32      | material id, range 1 - 255 (aligns with color palette ids)
/// 4        | int32      | material type (0:diffuse, 1:metal, 2:glass, 3:emissive)
/// 4        | float32    | material weight; meaning varies by type:
///          |            |   diffuse: 1.0
///          |            |   metal: (0.0 - 1.0], blend between metal and diffuse
///          |            |   glass: (0.0 - 1.0], blend between glass and diffuse
///          |            |   emissive: (0.0 - 1.0], self-illuminated
/// 4        | int32      | property bits, set if value is saved in next section; # of set bits N
///          |            |   bit(0): Plastic (property value can be only 0.0 or 1.0)
///          |            |   bit(1): Roughness
///          |            |   bit(2): Specular
///          |            |   bit(3): IOR (Index of Refraction)
///          |            |   bit(4): Attenuation
///          |            |   bit(5): Power
///          |            |   bit(6): Glow
///          |            |   bit(7): isTotalPower (*no value)
/// 4xN      | float32    | normalized property values, range (0.0 - 1.0]
///  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
/// 1x4      | char8      | chunk id 'LAYR'
/// 4        | int32      | layer id
/// (        | DICT       | layer attributes
///   ..     | STRING     | key: '_name'
///   ..     | STRING     | val: node name
///   ..     | STRING     | key: '_hidden'
///   ..     | int(STR)   | val: string parsed as int boolean, true when value is '1'
/// )
/// 4        | int32      | reserved id (must be -1)
///  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
/// 1x4      | char8      | chunk id 'rOBJ'
/// (        | DICT       | rendering attributes
///   ..     | STRING     | key: '_type'
///   ..     | STRING     | val: attr name (_atm, _bg, _bloom, _bounce,
///   ..     | ..         |                 _edge, _env, _film, _fog_uni,
///   ..     | ..         |                 _grid, _ground, _ibl, _inf,
///   ..     | ..         |                 _lens, _setting, _uni )
///  · · _atm· · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·
///   ..     | STRING     | key : _ray_d
///   ..     | float(STR) | val: string parsed as float
///   ..     | STRING     | key : _ray_k
///   ..     | vec3(STR)  | val: int32x3 r, g, b [0-255] color values
///   ..     | STRING     | key : _mie_d
///   ..     | float(STR) | val: string parsed as float
///   ..     | STRING     | key : _mie_k
///   ..     | vec3(STR)  | val: int32x3 r, g, b [0-255] color values
///   ..     | STRING     | key : _mie_g
///   ..     | float(STR) | val: string parsed as float
///   ..     | STRING     | key : _o3_d
///   ..     | float(STR) | val: string parsed as float
///   ..     | STRING     | key : _o3_k
///   ..     | vec3(STR)  | val: int32x3 r, g, b [0-255] color values
///  · · _bg · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·
///   ..     | STRING     | key : _color
///   ..     | vec3(STR)  | val: int32x3 r, g, b [0-255] color values
///  · · _bloom· · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·
///   ..     | STRING     | key : _mix
///   ..     | float(STR) | val: string parsed as float (0.0 - 1.0)
///   ..     | STRING     | key : _scale
///   ..     | float(STR) | val: string parsed as float (0.0 - 1.0)
///   ..     | STRING     | key : _aspect
///   ..     | float(STR) | val: string parsed as float (0.0 - 1.0)
///   ..     | STRING     | key : _threshold
///   ..     | float(STR) | val: string parsed as float (0.0 - 1.0)
///  · · _bounce · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·
///   ..     | STRING     | key: _diffuse
///   ..     | int(STR)   | val: string parsed as int32
///   ..     | STRING     | key: _specular
///   ..     | int(STR)   | val: string parsed as int32
///   ..     | STRING     | key: _scatter
///   ..     | int(STR)   | val: string parsed as int32
///   ..     | STRING     | key: _energy
///   ..     | int(STR)   | val: string parsed as int32
///  · · _edge · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·
///   ..     | STRING     | key : _color
///   ..     | vec3(STR)  | val: int32x3 r, g, b [0-255] color values
///   ..     | STRING     | key : _width
///   ..     | float(STR) | val: string parsed as float
///  · · _env· · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·
///   ..     | STRING     | key: _mode
///   ..     | int(STR)   | val: string parsed as int32
///  · · _film · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·
///   ..     | STRING     | key : _expo
///   ..     | float(STR) | val: string parsed as float
///   ..     | STRING     | key : _vig
///   ..     | float(STR) | val: string parsed as float (0.0 - 1.0)
///   ..     | STRING     | key : _aces
///   ..     | int(STR)   | val: string parsed as int boolean, true when value is '1'
///   ..     | STRING     | key : _gam
///   ..     | float(STR) | val: string parsed as float
///  · · _fog_uni· · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·
///   ..     | STRING     | key : _d
///   ..     | float(STR) | val: string parsed as float
///   ..     | STRING     | key : _k
///   ..     | vec3(STR)  | val: int32x3 r, g, b [0-255] color values
///   ..     | STRING     | key : _g
///   ..     | float(STR) | val: string parsed as float
///  · · _grid · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·
///   ..     | STRING     | key : _color
///   ..     | vec3(STR)  | val: int32x3 r, g, b [0-255] color values
///   ..     | STRING     | key : _spacing
///   ..     | int(STR)   | val: string parsed as int32
///   ..     | STRING     | key : _width
///   ..     | float(STR) | val: string parsed as float
///   ..     | STRING     | key : _display
///   ..     | int(STR)   | val: string parsed as int boolean, true when value is '1'
///  · · _ground · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·
///   ..     | STRING     | key : _color
///   ..     | vec3(STR)  | val: int32x3 r, g, b [0-255] color values
///   ..     | STRING     | key : _hor
///   ..     | float(STR) | val: string parsed as float
///  · · _ibl·(image-based lighting) · · · · · · · · · · · · · · · · · · · · · · ·
///   ..     | STRING     | key: _path
///   ..     | STRING     | val: string filepath
///   ..     | STRING     | key : _i
///   ..     | float(STR) | val: string parsed as float
///   ..     | STRING     | key : _angle
///   ..     | vec2(STR)  | val: float32x2 x, y rotation in degrees
///  · · _inf· · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·
///   ..     | STRING     | key: _i
///   ..     | float(STR) | val: string parsed as float
///   ..     | STRING     | key : _k
///   ..     | vec3(STR)  | val: int32x3 r, g, b [0-255] color values
///   ..     | STRING     | key: _angle
///   ..     | vec2(STR)  | val: float32x2 x, y rotation in degrees
///   ..     | STRING     | key: _area
///   ..     | float(STR) | val: string parsed as float
///   ..     | STRING     | key: _disk
///   ..     | int(STR)   | val: string parsed as int boolean, true when value is '1'
///  · · _lens · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·
///   ..     | STRING     | key: _proj
///   ..     | int(STR)   | val: string parsed as int32, projection type
///   ..     | STRING     | key: _fov
///   ..     | int(STR)   | val: string parsed as int32, degrees
///   ..     | STRING     | key: _aperture
///   ..     | float(STR) | val: string parsed as float (0.0 - 1.0)
///   ..     | STRING     | key: _blade_n
///   ..     | int(STR)   | val: string parsed as int32, count
///   ..     | STRING     | key: _blade_r
///   ..     | int(STR)   | val: string parsed as int32, degrees
///  · · _setting· · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·
///   ..     | STRING     | key: _ground
///   ..     | int(STR)   | val: string parsed as int boolean, true when value is '1'
///   ..     | STRING     | key: _grid
///   ..     | int(STR)   | val: string parsed as int boolean, true when value is '1'
///   ..     | STRING     | key: _edge
///   ..     | int(STR)   | val: string parsed as int boolean, true when value is '1'
///   ..     | STRING     | key: _bg_c
///   ..     | int(STR)   | val: string parsed as int boolean, true when value is '1'
///   ..     | STRING     | key: _bg_a
///   ..     | int(STR)   | val: string parsed as int boolean, true when value is '1'
///   ..     | STRING     | key: _scale
///   ..     | vec3(STR)  | val: float32x3 x, y, z scale
///   ..     | STRING     | key: _cell
///   ..     | int(STR)   | val: string parsed as int boolean, true when value is '1'
///  · · _uni· · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · · ·
///   ..     | STRING     | key: _i
///   ..     | float(STR) | val: string parsed as float
///   ..     | STRING     | key : _k
///   ..     | vec3(STR)  | val: int32x3 r, g, b [0-255] color values
/// )
///  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
/// 1x4      | char8      | chunk id 'rCAM'
/// 4        | int32      | camera id
/// (        | DICT       | camera attributes
///   ..     | STRING     | key: '_mode'
///   ..     | STRING     | val: camera mode (pers, free, orth, iso)
///   ..     | STRING     | key: '_focus'
///   ..     | vec3(STR)  | val: int32x3 x, y, z target point coordinates
///   ..     | STRING     | key: '_angle'
///   ..     | vec3(STR)  | val: string int32x3 as pitch, yaw, roll (in degrees)
///   ..     | STRING     | key: '_radius'
///   ..     | int(STR)   | val: string parsed as int32
///   ..     | STRING     | key: '_frustum'
///   ..     | float(STR) | val: string parsed as double
///   ..     | STRING     | key: '_fov'
///   ..     | int(STR)   | val: string parsed as int32
/// )
///  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
/// 1x4      | char8      | chunk id 'NOTE'
/// 4        | int32      | number of color names N
/// {        +            + for each name
///   ..     | STRING     | color name
/// } xN color names
///  - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
/// 1x4      | char8      | chunk id 'IMAP'
/// 4        | int32 (256)| number of indices N (N will be 256)
/// {        +            + for each index
///   4      | int32      | palette index association
/// } xN indices
/// ```
/// https://github.com/ephtracy/voxel-model/blob/master/MagicaVoxel-file-format-vox-extension.txt
class VoxParser {
  static _VoxRawChunk _parseRawChunk(VoxReader reader) {
    // get chunk id, content bytes count, and child bytes count
    final String id = reader.readString(4);
    final int contentSize = reader.readInt32();
    final int childrenSize = reader.readInt32();
    // read content bytes
    final Uint8List contentBytes = reader.readBytes(contentSize);
    // extract chunks from child bytes
    final List<_VoxRawChunk> childChunks = <_VoxRawChunk>[];
    final VoxReader childrenReader = VoxReader(reader.readBytes(childrenSize));
    while (childrenReader.hasMore) {
      childChunks.add(_parseRawChunk(childrenReader));
    }
    return _VoxRawChunk(id, contentBytes, childChunks);
  }

  /// parse voxel data from a [File] into a [VoxFile] data structure.
  ///
  /// throws a [FileSystemException] if file read fails.
  static VoxFile parseFile(File file, {StringBuffer? logBuffer}) {
    return parse(file.readAsBytesSync(), logBuffer: logBuffer);
  }

  /// parse voxel data from a list of [bytes] into a [VoxFile] data structure, optionally logging details to [logBuffer].
  static VoxFile parse(List<int> bytes, {StringBuffer? logBuffer}) {
    final VoxReader reader = VoxReader(bytes);
    final _VoxLogger log =
        _VoxLogger(buffer: logBuffer, barLength: 108, tracing: (logBuffer != null));
    log.clear();
    log.add('\n');

    // verify magic header and extract version
    final String magic = reader.readString(4);
    if (magic != 'VOX ') {
      throw FormatException('Invalid .vox file header: expected "VOX ", got "$magic"');
    }
    final int version = reader.readInt32();
    log.barS();
    log.line('${magic}v${version}');
    log.barS();

    // 2. parse nested chunks starting with root chunk 'MAIN'
    final _VoxRawChunk mainChunk = _parseRawChunk(reader);
    log.line(
        '${mainChunk.id} ${mainChunk.content.length} bytes ${mainChunk.children.length} children');
    if (mainChunk.id != 'MAIN') {
      throw FormatException('Expected root chunk "MAIN", got "${mainChunk.id}"');
    }

    final List<VoxModel> models = <VoxModel>[];
    List<VoxColor>? palette;
    final Map<int, VoxNode> nodes = <int, VoxNode>{};
    final Map<int, VoxMaterial> materials = <int, VoxMaterial>{};
    final Map<int, VoxLayer> layers = <int, VoxLayer>{};
    Map<String, String>? renderingAttributes;
    final Map<int, VoxCamera> cameras = <int, VoxCamera>{};
    List<String>? paletteNotes;
    List<int>? indexMap;

    final List<_VoxSize> pendingSizes = <_VoxSize>[];

    // Traverse the parsed chunk tree
    for (final _VoxRawChunk chunk in mainChunk.children) {
      log.barD();
      log.line('${chunk.id} ${chunk.content.length} bytes ${chunk.children.length} children');
      final VoxReader chunkReader = VoxReader(chunk.content);

      switch (chunk.id) {
        // core chunk types
        // https://github.com/ephtracy/voxel-model/blob/master/MagicaVoxel-file-format-vox.txt

        case 'PACK':
          // optional chunk, specifies model count (num SIZE+XYZI pairs)
          // if absent, only one model is in the file
          final int numModels = chunkReader.readInt32();
          log.line('numModels: ${numModels}');
          break;

        case 'SIZE':
          // model extents; z is gravity direction
          final int x = chunkReader.readInt32();
          final int y = chunkReader.readInt32();
          final int z = chunkReader.readInt32();
          log.line('volume: ${x}x, ${y}y, ${z}z');
          pendingSizes.add(_VoxSize(x, y, z));
          break;

        case 'XYZI':
          // model voxels, paired with the SIZE chunk
          if (pendingSizes.isEmpty) {
            throw FormatException('XYZI chunk without corresponding SIZE chunk');
          }
          final _VoxSize size = pendingSizes.removeAt(0);
          final int numVoxels = chunkReader.readInt32();
          log.line('voxels: ${numVoxels}');
          final List<VoxVoxel> voxels = <VoxVoxel>[];
          for (int i = 0; i < numVoxels; i++) {
            final int vx = chunkReader.readUint8();
            final int vy = chunkReader.readUint8();
            final int vz = chunkReader.readUint8();
            final int vi = chunkReader.readUint8();
            voxels.add(VoxVoxel(x: vx, y: vy, z: vz, colorIndex: vi));
            if (i < 12 || i >= numVoxels - 4) {
              if (i < 12 && (i > 0 && i % 4 == 0)) {
                log.add('\n');
              }
              if (i == numVoxels - 4) {
                log.add('\n··\n');
              }
              log.add('[${i.toString().padLeft(2, ' ')}] ${voxels.last} ');
            }
          }
          log.add('\n');
          models.add(VoxModel(
            id: models.length,
            sizeX: size.x,
            sizeY: size.y,
            sizeZ: size.z,
            voxels: voxels,
          ));
          break;

        case 'RGBA':
          // optional chunk, defines color palette
          log.line('colors: always 256');
          palette = List<VoxColor>.filled(256, const VoxColor(0, 0, 0, 0));
          for (int i = 0; i < 256; i++) {
            final int r = chunkReader.readUint8();
            final int g = chunkReader.readUint8();
            final int b = chunkReader.readUint8();
            final int a = chunkReader.readUint8();
            final VoxColor color = VoxColor(r, g, b, a);
            if (i > 0 && i % 4 == 0) {
              log.add('\n');
            }
            log.add('[${i.toString().padLeft(3, ' ')}] ${color} ');

            // MagicaVoxel maps color [0-254] (the first 255 colors in the file)
            // to palette index [1-255]. The 256th color is mapped to index 0.
            if (i == 255) {
              palette[0] = color;
            } else {
              palette[i + 1] = color;
            }
          }
          log.add('\n');
          break;

        // extended chunk types
        // https://github.com/ephtracy/voxel-model/blob/master/MagicaVoxel-file-format-vox-extension.txt

        case 'nTRN':
          // scene graph transform node
          final int nodeId = chunkReader.readInt32();
          log.line('node id: ${nodeId}');
          final Map<String, String> nodeAttrs = chunkReader.readDict();
          log.line('node attributes: ${nodeAttrs}');
          final int childNodeId = chunkReader.readInt32();
          chunkReader.readInt32(); // consume reserved int; expected to be -1
          final int layerId = chunkReader.readInt32();
          log.line('layer id: ${layerId}');
          final int numFrames = chunkReader.readInt32();
          log.line('frames: ${numFrames}');

          final List<VoxTransformFrame> frames = <VoxTransformFrame>[];
          for (int f = 0; f < numFrames; f++) {
            final Map<String, String> frameAttrs = chunkReader.readDict();
            log.line('frame[${f}]');

            // parse rotation
            final String? rStr = frameAttrs['_r'];
            final int rVal = rStr != null ? (int.tryParse(rStr) ?? 0) : 0;
            final VoxRotation rotation = VoxRotation(rVal);
            log.line('_r: ${rotation}');

            // parse translation
            final String? tStr = frameAttrs['_t'];
            int tx = 0, ty = 0, tz = 0;
            if (tStr != null) {
              final List<String> parts = tStr.trim().split(RegExp(r'\s+'));
              if (parts.length >= 3) {
                tx = int.tryParse(parts[0]) ?? 0;
                ty = int.tryParse(parts[1]) ?? 0;
                tz = int.tryParse(parts[2]) ?? 0;
              }
            }
            log.line('_t: ${tx}x ${ty}y ${tz}z');

            final String? fStr = frameAttrs['_f'];
            log.line('_f: ${fStr}');
            final int frameIdx = fStr != null ? (int.tryParse(fStr) ?? f) : f;

            frames.add(VoxTransformFrame(
              rotation: rotation,
              translationX: tx,
              translationY: ty,
              translationZ: tz,
              frameIndex: frameIdx,
              attributes: frameAttrs,
            ));
          }

          nodes[nodeId] = VoxTransformNode(
            id: nodeId,
            attributes: nodeAttrs,
            childNodeId: childNodeId,
            layerId: layerId,
            frames: frames,
          );
          break;

        case 'nGRP':
          // scene graph group node
          final int nodeId = chunkReader.readInt32();
          log.line('node id: ${nodeId}');
          final Map<String, String> nodeAttrs = chunkReader.readDict();
          log.line('node attributes: ${nodeAttrs}');
          final int numChildren = chunkReader.readInt32();
          log.line('children: ${numChildren}');
          final List<int> childrenIds = <int>[];
          for (int i = 0; i < numChildren; i++) {
            childrenIds.add(chunkReader.readInt32());
          }
          log.line(childrenIds.toString());
          nodes[nodeId] = VoxGroupNode(
            id: nodeId,
            attributes: nodeAttrs,
            childrenNodeIds: childrenIds,
          );
          break;

        case 'nSHP':
          // scene graph shape node
          final int nodeId = chunkReader.readInt32();
          log.line('node id: ${nodeId}');
          final Map<String, String> nodeAttrs = chunkReader.readDict();
          log.line('node attributes: ${nodeAttrs}');
          final int numModels = chunkReader.readInt32();
          log.line('models: ${numModels}');
          final List<VoxShapeModelReference> modelRefs = <VoxShapeModelReference>[];
          for (int i = 0; i < numModels; i++) {
            final int modelId = chunkReader.readInt32();
            log.line('model id: ${modelId}');
            final Map<String, String> modelAttrs = chunkReader.readDict();
            log.line('model attributes: ${modelAttrs}');
            final String? fStr = modelAttrs['_f'];
            final int frameIdx = fStr != null ? (int.tryParse(fStr) ?? 0) : 0;
            log.line('_f: ${fStr}');

            modelRefs.add(VoxShapeModelReference(
              modelId: modelId,
              frameIndex: frameIdx,
              attributes: modelAttrs,
            ));
          }
          nodes[nodeId] = VoxShapeNode(
            id: nodeId,
            attributes: nodeAttrs,
            models: modelRefs,
          );
          break;

        case 'MATT':
          // deprecated material attributes, replaced by MATL chunk
          log.line('MATT chunk is deprecated, migrate to MATL');

          final int matId = chunkReader.readInt32();
          log.line('material id: ${matId}');

          final List<String> matTypes = <String>['_diffuse', '_metal', '_glass', '_emit'];
          final int matTypeIndex = chunkReader.readInt32();
          final String matType = matTypes[matTypeIndex];
          log.line('material type: ${matTypeIndex} (${matType})');

          final double matWeight = chunkReader.readFloat32();
          log.line('material weight: ${matWeight}');

          final Map<String, String> matProps = <String, String>{};
          matProps['_type'] = matType;
          matProps['_weight'] = matWeight.toString();

          final int matPropFlags = chunkReader.readInt32();
          final String flagBits = matPropFlags.toRadixString(2).padLeft(8, '0');
          log.line('material property flags: ${matPropFlags} (${flagBits})');
          bool bitSet(String bits, int i) => (bits[8 - i] == '1');

          if (bitSet(flagBits, 1)) {
            matProps['_plastic'] = '1';
          }
          log.line('plastic: ${flagBits[8 - 1]}');
          if (bitSet(flagBits, 2)) {
            final double roughness = chunkReader.readFloat32();
            log.line('roughness: ${roughness}');
            matProps['_rough'] = roughness.toString();
          }
          if (bitSet(flagBits, 3)) {
            final double specularity = chunkReader.readFloat32();
            log.line('specularity: ${specularity}');
            matProps['_spec'] = specularity.toString();
          }
          if (bitSet(flagBits, 4)) {
            final double indexOfRefraction = chunkReader.readFloat32();
            log.line('indexOfRefraction: ${indexOfRefraction}');
            matProps['_ior'] = indexOfRefraction.toString();
          }
          if (bitSet(flagBits, 5)) {
            final double attenuation = chunkReader.readFloat32();
            log.line('attenuation: ${attenuation}');
            matProps['_att'] = attenuation.toString();
          }
          if (bitSet(flagBits, 6)) {
            final double flux = chunkReader.readFloat32();
            log.line('flux: ${flux}');
            matProps['_flux'] = flux.toString();
          }
          if (bitSet(flagBits, 7)) {
            final double glow = chunkReader.readFloat32();
            log.line('glow: ${glow}');
            matProps['_glow'] = glow.toString();
          }
          if (bitSet(flagBits, 8)) {
            final double isTotalPower = chunkReader.readFloat32();
            log.line('isTotalPower: ${isTotalPower}');
            //matProps['_??'] = isTotalPower.toString();
          }
          materials[matId] = VoxMaterial(id: matId, properties: matProps);
          break;

        case 'MATL':
          // render material properties
          final int matId = chunkReader.readInt32();
          log.line('material id: ${matId}');
          final Map<String, String> matProps = chunkReader.readDict();
          log.line('material properties: ${matProps}');
          materials[matId] = VoxMaterial(id: matId, properties: matProps);
          break;

        case 'LAYR':
          // visibility layers (hidden layers are not rendered)
          final int layerId = chunkReader.readInt32();
          log.line('material id: ${layerId}');
          final Map<String, String> layerAttrs = chunkReader.readDict();
          log.line('layer attributes: ${layerAttrs}');
          chunkReader.readInt32(); // consume reserved int; expected to be -1
          layers[layerId] = VoxLayer(id: layerId, attributes: layerAttrs);
          break;

        case 'rOBJ':
          // render attributes for the model
          renderingAttributes = chunkReader.readDict();
          log.line('rendering attributes: ${renderingAttributes}');
          break;

        case 'rCAM':
          // render camera attributes
          final int camId = chunkReader.readInt32();
          log.line('camera id: ${camId}');
          final Map<String, String> camAttrs = chunkReader.readDict();
          log.line('camera attributes: ${camAttrs}');
          cameras[camId] = VoxCamera(id: camId, attributes: camAttrs);
          break;

        case 'NOTE':
          // records string labels for specific palette entries.
          // these are also retrieved via the indexMap
          // e.g.: note = paletteNotes[indexMap[voxel.colorIndex]];
          final int numNotes = chunkReader.readInt32();
          log.line('notes: ${numNotes}');
          paletteNotes = <String>[];
          for (int i = 0; i < numNotes; i++) {
            paletteNotes.add(chunkReader.readStringPrefixed());
          }
          log.line('notes: ${paletteNotes}');
          break;

        case 'IMAP':
          // The 'IMAP' chunk provides a list of lookups that map voxel color index to RGBA palette color.
          // e.g.: color = palette[indexMap[voxel.colorIndex]];
          // https://github.com/ephtracy/voxel-model/issues/19#issuecomment-739324018
          indexMap = <int>[];
          for (int i = 0; i < 256; i++) {
            indexMap.add(chunkReader.readUint8());
          }
          log.line('mapping: ${indexMap}');
          break;

        default:
          // unknown chunk, skip
          break;
      }
    }
    log.barS();

    return VoxFile(
      version: version,
      models: models,
      palette: palette,
      nodes: nodes,
      materials: materials,
      layers: layers,
      renderingAttributes: renderingAttributes,
      cameras: cameras,
      paletteNotes: paletteNotes,
      indexMap: indexMap,
    );
  }
}
