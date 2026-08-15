import 'dart:io';
import 'package:vox_rw/vox_rw.dart';

void main() {
  final Directory sampleDir =
      Directory(<String>['example', 'samples'].join(Platform.pathSeparator));
  final Iterable<File> sampleFiles = _getFileList(sampleDir, 'vox');
  if (sampleFiles.isEmpty) {
    throw FileSystemException('no sample files found to test with', sampleDir.toString());
  }

  print('reading .vox files from ${sampleDir.path}..');
  for (final File file in sampleFiles) {
    print('\n${file.path}');
    print('-' * file.path.length);

    try {
      final VoxFile voxFile = VoxParser.parseFile(file);

      print('VOX file version: ${voxFile.version}');
      print('${_asThousands(voxFile.models.length)} ${_pl('model', voxFile.models.length)}');

      for (int i = 0; i < voxFile.models.length; i++) {
        final VoxModel model = voxFile.models[i];
        print(
            '  ${i}: ${_asThousands(model.voxels.length)} voxels (size: ${model.sizeX}x ${model.sizeY}y ${model.sizeZ}z)');
        if (model.voxels.isNotEmpty) {
          final String n = _asThousands(model.voxels.length - 1);
          final VoxVoxel first = model.voxels.first;
          final VoxVoxel last = model.voxels.last;
          final VoxColor firstColor = voxFile.palette[first.colorIndex];
          final VoxColor lastColor = voxFile.palette[last.colorIndex];
          print('     ${'0'.padLeft(n.length)}: ${first.toString()} -> ${firstColor.toString()}');
          print('     ${n}: ${last.toString()} -> ${lastColor.toString()}');
        }
      }

      print('materials parsed: ${_asThousands(voxFile.materials.length)}');
      print('layers parsed: ${_asThousands(voxFile.layers.length)}');
      print('cameras parsed: ${_asThousands(voxFile.cameras.length)}');
      print('scene graph nodes parsed: ${_asThousands(voxFile.nodes.length)}');
      if (voxFile.nodes.isNotEmpty) {
        _printSceneNode(voxFile.rootNode, voxFile.nodes);
      }
    } catch (e, stackTrace) {
      print('error parsing ${file.path}: ${e}');
      print(stackTrace);
    }
  }
}

Iterable<File> _getFileList(Directory dir, String ext, {String prefix = ''}) {
  String extension(String path) {
    final int i = path.lastIndexOf('.');
    return (i < 0) ? '' : path.substring(i + 1, path.length);
  }

  String basename(String path) => RegExp(r'[^/\\]+$').allMatches(path).firstOrNull?[0] ?? '';

  return dir
      .listSync()
      .where(
        (FileSystemEntity fse) => ((fse is File) &&
            (extension(fse.path) == ext) &&
            (basename(fse.path).startsWith(prefix))),
      )
      .cast<File>();
}

void _printSceneNode(VoxNode? node, Map<int, VoxNode> nodes, [int depth = 1]) {
  if (node == null) return;
  final String indent = '  ' * depth;

  if (node is VoxTransformNode) {
    print(
        '${indent}[transform node #${node.id}] name: "${node.name ?? ''}" layer: ${node.layerId} frames: ${_asThousands(node.frames.length)}');
    for (final VoxTransformFrame frame in node.frames) {
      print(
          '${indent}- frame ${frame.frameIndex}: translation (${frame.translationX}, ${frame.translationY}, ${frame.translationZ})');
    }
    final VoxNode? child = nodes[node.childNodeId];
    _printSceneNode(child, nodes, depth + 1);
  } else if (node is VoxGroupNode) {
    print(
        '${indent}[group node #${node.id}] children: ${_asThousands(node.childrenNodeIds.length)}');
    for (final int childId in node.childrenNodeIds) {
      final VoxNode? child = nodes[childId];
      _printSceneNode(child, nodes, depth + 1);
    }
  } else if (node is VoxShapeNode) {
    print('${indent}[shape node #${node.id}] models: ${_asThousands(node.models.length)}');
    for (final VoxShapeModelReference modelRef in node.models) {
      print('${indent}- model id: ${modelRef.modelId} (frame: ${modelRef.frameIndex})');
    }
  }
}

String _pl(String s, num n) => (n == 1) ? s : '${s}s';

String _asThousands(num v, {String delim = ','}) {
  final String s = v.toString();
  final int n = s.lastIndexOf('.');
  final String i = (n < 0) ? s : s.substring(0, n);
  final String d = (n < 0) ? '' : s.substring(n);
  final String t = i.replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (Match m) => '${m[1]}${delim}',
  );
  return '${t}${d}';
}
