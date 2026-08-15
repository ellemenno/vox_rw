import 'default_palette.dart';
import 'vox_core.dart';
import 'vox_extensions.dart';

/// Represents a parsed MagicaVoxel `.vox` file containing core and extended format data chunks.
class VoxFile {
  /// VOX format version number (e.g. `150`, `200`).
  final int version;

  /// list of 3D models contained in the file.
  final List<VoxModel> models;

  /// color palette, with 256 entries (if parsed from `RGBA` chunk, else default palette).
  final List<VoxColor> palette;

  /// map of all scene graph nodes (Transform, Group, Shape) keyed by node ID.
  /// Optional, may be empty.
  final Map<int, VoxNode> nodes;

  /// map of material properties keyed by material ID.
  /// Optional, may be empty.
  final Map<int, VoxMaterial> materials;

  /// map of layer definitions keyed by layer ID.
  /// Optional, may be empty.
  final Map<int, VoxLayer> layers;

  /// global rendering attributes (if parsed from the `rOBJ` chunk).
  /// Optional, may be empty.
  final Map<String, String> renderingAttributes;

  /// map of rendering camera settings keyed by camera ID.
  /// Optional, may be empty.
  final Map<int, VoxCamera> cameras;

  /// color palette notes (if parsed from the `NOTE` chunk).
  /// Optional, may be empty.
  final List<String> paletteNotes;

  /// index mapping table (parsed from the `IMAP` chunk, or defaults to palette ordering).
  final List<int> indexMap;

  VoxFile({
    required this.version,
    required this.models,
    List<VoxColor>? palette,
    Map<int, VoxNode>? nodes,
    Map<int, VoxMaterial>? materials,
    Map<int, VoxLayer>? layers,
    Map<String, String>? renderingAttributes,
    Map<int, VoxCamera>? cameras,
    List<String>? paletteNotes,
    List<int>? indexMap,
  })  : this.palette = palette ?? defaultPalette,
        this.nodes = nodes ?? <int, VoxNode>{},
        this.materials = materials ?? <int, VoxMaterial>{},
        this.layers = layers ?? <int, VoxLayer>{},
        this.renderingAttributes = renderingAttributes ?? <String, String>{},
        this.cameras = cameras ?? <int, VoxCamera>{},
        this.paletteNotes = paletteNotes ?? <String>[],
        this.indexMap = indexMap ?? defaultIndexMap;

  /// Returns the root node of the scene graph if one exists.
  /// Typically, the root node is the transform node with ID 0.
  VoxNode? get rootNode {
    if (nodes.isEmpty) return null;
    // Look for node ID 0 first, otherwise return the transform node with no parents if we were to traverse.
    // As a simple heuristic, find the transform node with the lowest ID (usually 0).
    if (nodes.containsKey(0)) {
      return nodes[0];
    }
    // Fallback: return the first node in the map
    return nodes.values.first;
  }

  /// Retrieve a [VoxColor] for the provided [colorIndex], using the index map.
  VoxColor getColor(int colorIndex) => palette[indexMap[colorIndex]];

  @override
  String toString() {
    return 'VoxFile v$version (\n'
        '  ${models.length} models,\n'
        '  ${palette.length} palette colors, ${paletteNotes.length} palette notes,\n'
        '  ${materials.length} materials,\n'
        '  ${layers.length} layers,\n'
        '  ${cameras.length} cameras,\n'
        '  ${nodes.length} scene graph nodes\n'
        '  renderingAttributes: ${renderingAttributes}\n'
        '  indexMap: ${indexMap}\n'
        ')';
  }
}
