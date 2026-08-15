read and write binary files in the MagicaVoxel `.vox` file format, with support for core and extension chunks

## support

**core** ([core-spec](https://github.com/ephtracy/voxel-model/blob/master/MagicaVoxel-file-format-vox.txt))
- `MAIN` root chunk
- `PACK` model count (optional)
- `SIZE` model dimensions
- `XYZI` voxel position and color index
- `RGBA` color palette (optional)

**extended** ([extended-spec](https://github.com/ephtracy/voxel-model/blob/master/MagicaVoxel-file-format-vox-extension.txt))
- scene graph nodes
  - `nTRN` transform
  - `nGRP` group
  - `nSHP` shape
- render properties
  - `rCAM` render camera
  - `rOBJ` render object
- appearance attributes
  - `IMAP` color palette index map
  - `MATL` material
- metadata
  - `LAYR` layer
  - `NOTE` palette note


## usage

add `vox_rw` to `pubspec.yaml`:

```console
dart pub add vox_rw
```

or manually:
```yaml
dependencies:
  vox_rw: ^1.0.0
```

```console
dart pub get
```

import package:

```dart
import 'package:vox_rw/vox_rw.dart';
```

## example

### provide a brief summary of each `.vox` file in the `example/samples` directory

> see `example/list.dart`
> ```console
> dart run example/list.dart
> ```

### read a `.vox` file and log details for each chunk

> see `example/print.dart`
> ```console
> dart run example/print.dart <file>
> dart run example/print.dart example/samples/cube3_project.vox
> ```

```dart
import 'dart:io';
import 'package:vox_rw/vox_rw.dart';

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
```
