/// base class for scene graph nodes.
abstract class VoxNode {
  final int id;
  final Map<String, String> attributes;

  const VoxNode({
    required this.id,
    required this.attributes,
  });

  String? get name => attributes['_name'];
  bool get hidden => attributes['_hidden'] == '1';
}

/// an orthogonal rotation matrix encoded in a single byte.
///
/// used by [VoxTransformFrame] in scene .vox graphs.
class VoxRotation {
  final int rawValue;

  const VoxRotation(this.rawValue);

  /// Reconstructs the 3x3 rotation matrix from the encoded byte.
  /// The result is a row-major 3x3 matrix represented as a list of 3 rows.
  List<List<int>> toMatrix() {
    final int r0 = rawValue & 3;
    final int r1 = (rawValue >> 2) & 3;

    // The third row's non-zero index is the remaining index in {0, 1, 2}
    final Set<int> used = <int>{r0, r1};
    int r2 = 0;
    for (int i = 0; i < 3; i++) {
      if (!used.contains(i)) {
        r2 = i;
        break;
      }
    }

    final int s0 = ((rawValue >> 4) & 1) == 1 ? -1 : 1;
    final int s1 = ((rawValue >> 5) & 1) == 1 ? -1 : 1;
    final int s2 = ((rawValue >> 6) & 1) == 1 ? -1 : 1;

    final List<List<int>> matrix = List<List<int>>.generate(3, (_) => List<int>.filled(3, 0));
    matrix[0][r0] = s0;
    matrix[1][r1] = s1;
    matrix[2][r2] = s2;
    return matrix;
  }

  @override
  String toString() {
    final List<List<int>> m = toMatrix();
    return 'VoxRotation(value: $rawValue, matrix: ${m[0]} | ${m[1]} | ${m[2]})';
  }
}

/// Represents a single frame in a transform node.
class VoxTransformFrame {
  final VoxRotation rotation;
  final int translationX;
  final int translationY;
  final int translationZ;
  final int frameIndex;
  final Map<String, String> attributes;

  const VoxTransformFrame({
    required this.rotation,
    required this.translationX,
    required this.translationY,
    required this.translationZ,
    required this.frameIndex,
    required this.attributes,
  });

  @override
  String toString() =>
      'VoxTransformFrame(frame: $frameIndex, t: ($translationX, $translationY, $translationZ), r: ${rotation.rawValue})';
}

/// A node that applies transformations (translation, rotation) to its child node.
class VoxTransformNode extends VoxNode {
  final int childNodeId;
  final int layerId;
  final List<VoxTransformFrame> frames;

  const VoxTransformNode({
    required super.id,
    required super.attributes,
    required this.childNodeId,
    required this.layerId,
    required this.frames,
  });

  @override
  String toString() =>
      'VoxTransformNode(id: $id, child: $childNodeId, layer: $layerId, framesCount: ${frames.length})';
}

/// A node that groups multiple children nodes together.
class VoxGroupNode extends VoxNode {
  final List<int> childrenNodeIds;

  const VoxGroupNode({
    required super.id,
    required super.attributes,
    required this.childrenNodeIds,
  });

  @override
  String toString() => 'VoxGroupNode(id: $id, children: $childrenNodeIds)';
}

/// A reference to a model in a shape node.
class VoxShapeModelReference {
  final int modelId;
  final int frameIndex;
  final Map<String, String> attributes;

  const VoxShapeModelReference({
    required this.modelId,
    required this.frameIndex,
    required this.attributes,
  });

  @override
  String toString() => 'VoxShapeModelReference(modelId: $modelId, frame: $frameIndex)';
}

/// A leaf node that references one or more models.
class VoxShapeNode extends VoxNode {
  final List<VoxShapeModelReference> models;

  const VoxShapeNode({
    required super.id,
    required super.attributes,
    required this.models,
  });

  @override
  String toString() => 'VoxShapeNode(id: $id, modelsCount: ${models.length})';
}

/// Represents a layer with properties (name, visibility, etc.).
class VoxLayer {
  final int id;
  final Map<String, String> attributes;

  const VoxLayer({
    required this.id,
    required this.attributes,
  });

  String? get name => attributes['_name'];
  bool get hidden => attributes['_hidden'] == '1';

  @override
  String toString() => 'VoxLayer(id: $id, name: $name, hidden: $hidden)';
}

/// Represents material properties for a color in the palette.
class VoxMaterial {
  final int id;
  final Map<String, String> properties;

  const VoxMaterial({
    required this.id,
    required this.properties,
  });

  String? get type => properties['_type']; // _diffuse, _metal, _glass, _emit
  double? get weight => _parseDouble(properties['_weight']);
  double? get rough => _parseDouble(properties['_rough']);
  double? get spec => _parseDouble(properties['_spec']);
  double? get ior => _parseDouble(properties['_ior']);
  double? get att => _parseDouble(properties['_att']);
  double? get flux => _parseDouble(properties['_flux']);
  bool get plastic => properties.containsKey('_plastic');

  static double? _parseDouble(String? val) {
    if (val == null) return null;
    return double.tryParse(val);
  }

  @override
  String toString() => 'VoxMaterial(id: $id, type: $type, properties: $properties)';
}

/// Represents camera settings.
class VoxCamera {
  final int id;
  final Map<String, String> attributes;

  const VoxCamera({
    required this.id,
    required this.attributes,
  });

  String? get mode => attributes['_mode'];
  // focus, angle, frustum, fov, etc. can be queried from [attributes]

  @override
  String toString() => 'VoxCamera(id: $id, attributes: $attributes)';
}
