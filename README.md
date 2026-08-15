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

```console
$ dart run example/list.dart
reading .vox files from example\samples..

example\samples\chr_knight.vox
------------------------------
VOX file version: 150
1 model
  0: 398 voxels (size: 20x 21y 20z)
       0:  0x 10y 10z 247i -> 220r 220g 220b 255a
     397: 17x 11y  5z  18i -> 252r 152g   0b 255a
0 materials
0 layers
0 cameras
0 scene graph nodes

example\samples\cube3_export.vox
--------------------------------
VOX file version: 200
1 model
  0: 27 voxels (size: 3x 3y 3z)
      0:  0x  0y  0z   1i -> 136r   0g   0b 255a
     26:  2x  2y  2z  67i -> 242r 115g 229b 255a
0 materials
0 layers
0 cameras
0 scene graph nodes

example\samples\cube3_save.vox
------------------------------
VOX file version: 200
1 model
  0: 27 voxels (size: 3x 3y 3z)
      0:  0x  0y  0z   1i -> 136r   0g   0b 255a
     26:  2x  2y  2z 235i -> 242r 115g 229b 255a
256 materials
16 layers
10 cameras
4 scene graph nodes
  [transform node #0] name: "" layer: -1 frames: 1
  - frame 0: translation (0, 0, 0)
    [group node #1] children: 1
      [transform node #2] name: "" layer: 0 frames: 1
      - frame 0: translation (0, 0, 1)
        [shape node #3] models: 1
        - model id: 0 (frame: 0)

example\samples\monu1.vox
-------------------------
VOX file version: 150
1 model
  0: 156,942 voxels (size: 126x 126y 118z)
           0: 50x 59y 80z   1i -> 131r 154g 169b 255a
     156,941: 69x 43y  7z   1i -> 131r 154g 169b 255a
0 materials
0 layers
0 cameras
0 scene graph nodes

example\samples\T-Rex.vox
-------------------------
VOX file version: 150
8 models
  0: 1,272 voxels (size: 24x 24y 26z)
         0: 22x 13y 21z 249i ->  56r  84g  96b 255a
     1,271:  2x 13y 14z 249i ->  56r  84g  96b 255a
  1: 1,265 voxels (size: 24x 24y 26z)
         0: 22x 13y 21z 249i ->  56r  84g  96b 255a
     1,264: 21x 16y 10z 249i ->  56r  84g  96b 255a
  2: 1,287 voxels (size: 24x 24y 26z)
         0: 22x 13y 22z 249i ->  56r  84g  96b 255a
     1,286:  1x 12y 17z 249i ->  56r  84g  96b 255a
  3: 1,284 voxels (size: 24x 24y 26z)
         0: 22x 13y 22z 249i ->  56r  84g  96b 255a
     1,283: 14x  9y 11z 249i ->  56r  84g  96b 255a
  4: 1,268 voxels (size: 24x 24y 26z)
         0: 22x 11y 21z 249i ->  56r  84g  96b 255a
     1,267: 17x  8y 11z 249i ->  56r  84g  96b 255a
  5: 1,272 voxels (size: 24x 24y 26z)
         0: 22x 11y 21z 249i ->  56r  84g  96b 255a
     1,271:  3x 13y 13z 249i ->  56r  84g  96b 255a
  6: 1,287 voxels (size: 24x 24y 26z)
         0: 22x 11y 22z 249i ->  56r  84g  96b 255a
     1,286:  1x 12y 17z 249i ->  56r  84g  96b 255a
  7: 1,284 voxels (size: 24x 24y 26z)
         0: 22x 11y 22z 249i ->  56r  84g  96b 255a
     1,283: 15x 13y 24z 249i ->  56r  84g  96b 255a
255 materials
0 layers
0 cameras
0 scene graph nodes
```

### read a `.vox` file and log details for each chunk

> see `example/print.dart`
> ```console
> dart run example/print.dart <file>
> dart run example/print.dart example/samples/cube3_save.vox
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
