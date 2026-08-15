import 'dart:io';
import 'package:vox_rw/vox_rw.dart';

// dart run example/print.dart example/samples/cube3_export.vox
void main(List<String> args) {
  if (args.isEmpty) {
    print('no arguments provided. please provide a file name to print.');
    return;
  }

  final File file = File(args.first);
  if (!file.existsSync()) {
    print('can\'t find ${args.first} on disk.');
    return;
  }

  print('reading .vox data from ${file.path}..');
  final StringBuffer log = StringBuffer();
  try {
    final VoxFile voxFile = VoxParser.parseFile(file, logBuffer: log);
    print('read .vox file v${voxFile.version}:');
  } catch (e, stackTrace) {
    print('error parsing ${file.path}: ${e}');
    print(stackTrace);
  } finally {
    print(log);
  }
}
