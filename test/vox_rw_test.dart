import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:vox_rw/vox_rw.dart';

void main() {
  group('VoxRotation Tests', () {
    test('Decodes rotation bits correctly to orthogonal matrix', () {
      // Identity matrix equivalent (or one of the standard rotations)
      // Spec example:
      // R =
      //  0  1  0
      //  0  0 -1
      // -1  0  0
      // ==>
      // unsigned char _r = (1 << 0) | (2 << 2) | (0 << 4) | (1 << 5) | (1 << 6)
      // Bit 0-1: 1
      // Bit 2-3: 2
      // Bit 4: 0
      // Bit 5: 1
      // Bit 6: 1
      // Value: 1 | (2 << 2) | (0 << 4) | (1 << 5) | (1 << 6)
      // Value = 1 | 8 | 0 | 32 | 64 = 105
      final VoxRotation r = VoxRotation(105);
      final List<List<int>> m = r.toMatrix();

      expect(m[0], <int>[0, 1, 0]);
      expect(m[1], <int>[0, 0, -1]);
      expect(m[2], <int>[-1, 0, 0]);
    });
  });

  group('VoxReader Tests', () {
    test('Reads integers and strings', () {
      final Uint8List bytes = Uint8List.fromList(<int>[
        0x01, 0x02, 0x03, 0x04, // int32 (little endian) -> 67305985
        0x41, 0x42, 0x43, 0x44, // string "ABCD"
        0xFF, // uint8 -> 255
      ]);

      final VoxReader reader = VoxReader(bytes);
      expect(reader.readInt32(), 67305985);
      expect(reader.readString(4), 'ABCD');
      expect(reader.readUint8(), 255);
      expect(reader.hasMore, isFalse);
    });

    test('Reads strings and dicts', () {
      final Uint8List bytes = Uint8List.fromList(<int>[
        0x04, 0x00, 0x00, 0x00, // length 4
        0x74, 0x65, 0x73, 0x74, // "test"
        0x02, 0x00, 0x00, 0x00, // dict count 2
        0x03, 0x00, 0x00, 0x00, 0x6B, 0x65, 0x79, // key "key"
        0x03, 0x00, 0x00, 0x00, 0x76, 0x61, 0x6C, // val "val"
        0x04, 0x00, 0x00, 0x00, 0x6E, 0x61, 0x6D, 0x65, // key "name"
        0x04, 0x00, 0x00, 0x00, 0x6A, 0x6F, 0x68, 0x6E, // val "john"
      ]);

      final VoxReader reader = VoxReader(bytes);
      expect(reader.readStringPrefixed(), 'test');
      final Map<String, String> dict = reader.readDict();
      expect(dict['key'], 'val');
      expect(dict['name'], 'john');
    });
  });

  group('VoxParser Tests', () {
    // Helper to generate a valid vox file header + MAIN chunk
    List<int> createMockVoxBytes({
      required List<int> childrenBytes,
    }) {
      final List<int> builder = <int>[];

      // File header: 'VOX ' + version (150)
      builder.addAll('VOX '.codeUnits);
      builder.addAll(<int>[150, 0, 0, 0]); // 32-bit int version 150

      // MAIN chunk
      builder.addAll('MAIN'.codeUnits);
      builder.addAll(<int>[0, 0, 0, 0]); // Content size = 0

      // Children size
      final int len = childrenBytes.length;
      builder.addAll(<int>[
        len & 0xFF,
        (len >> 8) & 0xFF,
        (len >> 16) & 0xFF,
        (len >> 24) & 0xFF,
      ]);

      // Children data
      builder.addAll(childrenBytes);

      return builder;
    }

    test('Throws on invalid magic header', () {
      final List<int> invalidBytes = 'INVALID_HEADER'.codeUnits;
      expect(() => VoxParser.parse(invalidBytes), throwsFormatException);
    });

    test('Parses a basic vox file with SIZE and XYZI chunks', () {
      final List<int> children = <int>[];

      // SIZE chunk: sizeX=3, sizeY=4, sizeZ=5
      children.addAll('SIZE'.codeUnits);
      children.addAll(<int>[12, 0, 0, 0]); // content size = 12
      children.addAll(<int>[0, 0, 0, 0]); // children size = 0
      children.addAll(<int>[3, 0, 0, 0]); // X
      children.addAll(<int>[4, 0, 0, 0]); // Y
      children.addAll(<int>[5, 0, 0, 0]); // Z

      // XYZI chunk: 1 voxel at x=1, y=2, z=3, colorIndex=42
      children.addAll('XYZI'.codeUnits);
      children.addAll(<int>[8, 0, 0, 0]); // content size = 8
      children.addAll(<int>[0, 0, 0, 0]); // children size = 0
      children.addAll(<int>[1, 0, 0, 0]); // numVoxels = 1
      children.addAll(<int>[1, 2, 3, 42]); // voxel: x, y, z, colorIndex

      final List<int> fileBytes = createMockVoxBytes(childrenBytes: children);
      final VoxFile vox = VoxParser.parse(fileBytes);

      expect(vox.version, 150);
      expect(vox.models.length, 1);

      final VoxModel model = vox.models.first;
      expect(model.sizeX, 3);
      expect(model.sizeY, 4);
      expect(model.sizeZ, 5);
      expect(model.voxels.length, 1);

      final VoxVoxel voxel = model.voxels.first;
      expect(voxel.x, 1);
      expect(voxel.y, 2);
      expect(voxel.z, 3);
      expect(voxel.colorIndex, 42);

      // No custom palette was specified, should fall back to default palette
      expect(vox.palette, defaultPalette);
    });

    test('Parses a custom RGBA palette', () {
      final List<int> children = <int>[];

      // RGBA chunk: 256 colors
      children.addAll('RGBA'.codeUnits);
      children.addAll(<int>[0, 4, 0, 0]); // content size = 1024 (0x0400)
      children.addAll(<int>[0, 0, 0, 0]); // children size = 0
      for (int i = 0; i < 256; i++) {
        // Red = i, Green = i, Blue = i, Alpha = 255
        children.addAll(<int>[i, i, i, 255]);
      }

      final List<int> fileBytes = createMockVoxBytes(childrenBytes: children);
      final VoxFile vox = VoxParser.parse(fileBytes);

      expect(vox.palette.length, 256);

      // Verify mapping:
      // First color in file (i=0) should map to palette index 1.
      expect(vox.palette[1], const VoxColor(0, 0, 0, 255));
      // Second color (i=1) should map to index 2.
      expect(vox.palette[2], const VoxColor(1, 1, 1, 255));
      // 255th color (i=254) should map to index 255.
      expect(vox.palette[255], const VoxColor(254, 254, 254, 255));
      // 256th color (i=255) should map to index 0.
      expect(vox.palette[0], const VoxColor(255, 255, 255, 255));
    });

    test('Parses scene graph and metadata chunks', () {
      final List<int> children = <int>[];

      // nTRN (Transform node) chunk
      children.addAll('nTRN'.codeUnits);

      // Calculate content size:
      // nodeId (4) + nodeAttrs dict size + childNodeId (4) + reservedId (4) + layerId (4) + numFrames (4) + frameAttrs dict size
      // nodeAttrs: count = 1, key = "_name", val = "RootTransform"
      // frameAttrs: count = 1, key = "_t", val = "1 2 3"
      final List<int> nodeAttrsBytes = <int>[
        1, 0, 0, 0, // count = 1
        5, 0, 0, 0, 0x5F, 0x6E, 0x61, 0x6D, 0x65, // key "_name" (len=5)
        13, 0, 0, 0, 0x52, 0x6F, 0x6F, 0x74, 0x54, 0x72, 0x61, 0x6E, 0x73, 0x66, 0x6F, 0x72,
        0x6D, // val "RootTransform" (len=13)
      ];
      final List<int> frameAttrsBytes = <int>[
        1, 0, 0, 0, // count = 1
        2, 0, 0, 0, 0x5F, 0x74, // key "_t" (len=2)
        5, 0, 0, 0, 0x31, 0x20, 0x32, 0x20, 0x33, // val "1 2 3" (len=5)
      ];
      final int contentSize = 4 + nodeAttrsBytes.length + 4 + 4 + 4 + 4 + frameAttrsBytes.length;

      children.addAll(<int>[
        contentSize & 0xFF,
        (contentSize >> 8) & 0xFF,
        (contentSize >> 16) & 0xFF,
        (contentSize >> 24) & 0xFF,
      ]);
      children.addAll(<int>[0, 0, 0, 0]); // children size = 0

      children.addAll(<int>[0, 0, 0, 0]); // nodeId = 0
      children.addAll(nodeAttrsBytes);
      children.addAll(<int>[1, 0, 0, 0]); // childNodeId = 1
      children.addAll(<int>[-1, -1, -1, -1].map((int b) => b & 0xFF)); // reservedId = -1
      children.addAll(<int>[10, 0, 0, 0]); // layerId = 10
      children.addAll(<int>[1, 0, 0, 0]); // numFrames = 1
      children.addAll(frameAttrsBytes);

      // nGRP (Group node) chunk
      // Calculate content size: nodeId (4) + nodeAttrs (4 for count=0) + numChildren (4) + childrenIds (4)
      children.addAll('nGRP'.codeUnits);
      children.addAll(<int>[16, 0, 0, 0]); // content size = 16
      children.addAll(<int>[0, 0, 0, 0]); // children size = 0
      children.addAll(<int>[1, 0, 0, 0]); // nodeId = 1
      children.addAll(<int>[0, 0, 0, 0]); // nodeAttrs (count = 0)
      children.addAll(<int>[1, 0, 0, 0]); // numChildren = 1
      children.addAll(<int>[2, 0, 0, 0]); // childId = 2

      // nSHP (Shape node) chunk
      // Calculate content size: nodeId (4) + nodeAttrs (4 for count=0) + numModels (4) + modelId (4) + modelAttrs (4 for count=0)
      children.addAll('nSHP'.codeUnits);
      children.addAll(<int>[20, 0, 0, 0]); // content size = 20
      children.addAll(<int>[0, 0, 0, 0]); // children size = 0
      children.addAll(<int>[2, 0, 0, 0]); // nodeId = 2
      children.addAll(<int>[0, 0, 0, 0]); // nodeAttrs (count = 0)
      children.addAll(<int>[1, 0, 0, 0]); // numModels = 1
      children.addAll(<int>[0, 0, 0, 0]); // modelId = 0
      children.addAll(<int>[0, 0, 0, 0]); // modelAttrs (count = 0)

      final List<int> fileBytes = createMockVoxBytes(childrenBytes: children);
      final VoxFile vox = VoxParser.parse(fileBytes);

      expect(vox.nodes.length, 3);
      expect(vox.nodes[0], isA<VoxTransformNode>());
      expect(vox.nodes[1], isA<VoxGroupNode>());
      expect(vox.nodes[2], isA<VoxShapeNode>());

      final VoxTransformNode rootTrans = vox.nodes[0] as VoxTransformNode;
      expect(rootTrans.name, 'RootTransform');
      expect(rootTrans.layerId, 10);
      expect(rootTrans.childNodeId, 1);
      expect(rootTrans.frames.length, 1);
      expect(rootTrans.frames[0].translationX, 1);
      expect(rootTrans.frames[0].translationY, 2);
      expect(rootTrans.frames[0].translationZ, 3);

      final VoxGroupNode group = vox.nodes[1] as VoxGroupNode;
      expect(group.childrenNodeIds, <int>[2]);

      final VoxShapeNode shape = vox.nodes[2] as VoxShapeNode;
      expect(shape.models.length, 1);
      expect(shape.models[0].modelId, 0);
    });
  });
}
