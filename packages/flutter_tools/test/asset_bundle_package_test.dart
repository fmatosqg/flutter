// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_tools/src/asset.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/flutter_manifest.dart';
import 'package:test/test.dart';

import 'src/common.dart';
import 'src/context.dart';

void main() {
  void writePubspecFile(String path, String name, {List<String> assets}) {
    String assetsSection;
    if (assets == null) {
      assetsSection = '';
    } else {
      final StringBuffer buffer = new StringBuffer();
      buffer.write('''
flutter:
     assets:
''');

      for (String asset in assets) {
        buffer.write('''
       - $asset
''');
      }
      assetsSection = buffer.toString();
    }

    final Uri uri = new Uri.file(path, windows: platform.isWindows);

    fs.file(uri)
      ..createSync(recursive: true)
      ..writeAsStringSync('''
name: $name
dependencies:
  flutter:
    sdk: flutter
$assetsSection
''');
  }

  void establishFlutterRoot() {
    Cache.flutterRoot = getFlutterRoot();
  }

  void writePackagesFile(String packages) {
    fs.file('.packages')
      ..createSync()
      ..writeAsStringSync(packages);
  }

  Future<Null> buildAndVerifyAssets(
    List<String> assets,
    List<String> packages,
    String expectedAssetManifest,
  ) async {
    final AssetBundle bundle = AssetBundleFactory.instance.createBundle();
    await bundle.build(manifestPath: 'pubspec.yaml');

    for (String packageName in packages) {
      for (String asset in assets) {
        final String entryKey = Uri.encodeFull('packages/$packageName/$asset');
        expect(bundle.entries.containsKey(entryKey), true, reason: 'Cannot find key on bundle: $entryKey');
        expect(
          utf8.decode(await bundle.entries[entryKey].contentsAsBytes()),
          asset,
        );
      }
    }

    expect(
      utf8.decode(await bundle.entries['AssetManifest.json'].contentsAsBytes()),
      expectedAssetManifest,
    );
  }

  void writeAssets(String path, List<String> assets) {
    for (String asset in assets) {
      final String fullPath = fs.path.join(path, asset); // posix compatible

      final String normalizedFullPath = // posix and windows compatible over MemoryFileSystem
      new Uri.file(
          fullPath, windows: platform.isWindows)
          .toFilePath(windows: platform.isWindows);

      fs.file(normalizedFullPath)
        ..createSync(recursive: true)
        ..writeAsStringSync(asset);
    }
  }

  // These tests do not use a memory file system because we want to ensure that
  // asset bundles work correctly on Windows and Posix systems.
  Directory tempDir;
  Directory oldCurrentDir;

  setUp(() async {
    tempDir = await fs.systemTempDirectory.createTemp('asset_bundle_tests');
    oldCurrentDir = fs.currentDirectory;
    fs.currentDirectory = tempDir;
  });

  tearDown(() {
    fs.currentDirectory = oldCurrentDir;
    try {
      tempDir?.deleteSync(recursive: true);
      tempDir = null;
    } on FileSystemException catch (e) {
      // Do nothing, windows sometimes has trouble deleting.
      print('Ignored exception during tearDown: $e');
    }
  });

  group('AssetBundle assets from packages', () {
    testUsingContext('No assets are bundled when the package has no assets', () async {
      establishFlutterRoot();

      writePubspecFile('pubspec.yaml', 'test');
      writePackagesFile('test_package:p/p/lib/');
      writePubspecFile('p/p/pubspec.yaml', 'test_package');

      final AssetBundle bundle = AssetBundleFactory.instance.createBundle();
      await bundle.build(manifestPath: 'pubspec.yaml');
      expect(bundle.entries.length, 3); // LICENSE, AssetManifest, FontManifest
      const String expectedAssetManifest = '{}';
      expect(
        utf8.decode(await bundle.entries['AssetManifest.json'].contentsAsBytes()),
        expectedAssetManifest,
      );
      expect(
        utf8.decode(await bundle.entries['FontManifest.json'].contentsAsBytes()),
        '[]',
      );
    });

    testUsingContext('No assets are bundled when the package has an asset that is not listed', () async {
      establishFlutterRoot();

      writePubspecFile('pubspec.yaml', 'test');
      writePackagesFile('test_package:p/p/lib/');
      writePubspecFile('p/p/pubspec.yaml', 'test_package');

      final List<String> assets = <String>['a/foo'];
      writeAssets('p/p/', assets);

      final AssetBundle bundle = AssetBundleFactory.instance.createBundle();
      await bundle.build(manifestPath: 'pubspec.yaml');
      expect(bundle.entries.length, 3); // LICENSE, AssetManifest, FontManifest
      const String expectedAssetManifest = '{}';
      expect(
        utf8.decode(await bundle.entries['AssetManifest.json'].contentsAsBytes()),
        expectedAssetManifest,
      );
      expect(
        utf8.decode(await bundle.entries['FontManifest.json'].contentsAsBytes()),
        '[]',
      );
    });

    testUsingContext('One asset is bundled when the package has and lists one asset its pubspec', () async {
      establishFlutterRoot();

      writePubspecFile('pubspec.yaml', 'test');
      writePackagesFile('test_package:p/p/lib/');

      final List<String> assets = <String>['a/foo'];
      writePubspecFile(
        'p/p/pubspec.yaml',
        'test_package',
        assets: assets,
      );

      writeAssets('p/p/', assets);

      const String expectedAssetManifest = '{"packages/test_package/a/foo":'
          '["packages/test_package/a/foo"]}';
      await buildAndVerifyAssets(
        assets,
        <String>['test_package'],
        expectedAssetManifest,
      );
    });

    testUsingContext("One asset is bundled when the package has one asset, listed in the app's pubspec", () async {
      establishFlutterRoot();

      final List<String> assetEntries = <String>['packages/test_package/a/foo'];
      writePubspecFile(
        'pubspec.yaml',
        'test',
        assets: assetEntries,
      );
      writePackagesFile('test_package:p/p/lib/');
      writePubspecFile('p/p/pubspec.yaml', 'test_package');

      final List<String> assets = <String>['a/foo'];
      writeAssets('p/p/lib/', assets);

      const String expectedAssetManifest = '{"packages/test_package/a/foo":'
          '["packages/test_package/a/foo"]}';
      await buildAndVerifyAssets(
        assets,
        <String>['test_package'],
        expectedAssetManifest,
      );
    });

    testUsingContext('One asset and its variant are bundled when the package has an asset and a variant, and lists the asset in its pubspec', () async {
      establishFlutterRoot();

      writePubspecFile('pubspec.yaml', 'test');
      writePackagesFile('test_package:p/p/lib/');
      writePubspecFile(
        'p/p/pubspec.yaml',
        'test_package',
        assets: <String>['a/foo'],
      );

      final List<String> assets = <String>['a/foo', 'a/v/foo'];
      writeAssets('p/p/', assets);

      const String expectedManifest = '{"packages/test_package/a/foo":'
          '["packages/test_package/a/foo","packages/test_package/a/v/foo"]}';

      await buildAndVerifyAssets(
        assets,
        <String>['test_package'],
        expectedManifest,
      );
    });

    testUsingContext('One asset and its variant are bundled when the package has an asset and a variant, and the app lists the asset in its pubspec', () async {
      establishFlutterRoot();

      writePubspecFile(
        'pubspec.yaml',
        'test',
        assets: <String>['packages/test_package/a/foo'],
      );
      writePackagesFile('test_package:p/p/lib/');
      writePubspecFile(
        'p/p/pubspec.yaml',
        'test_package',
      );

      final List<String> assets = <String>['a/foo', 'a/v/foo'];
      writeAssets('p/p/lib/', assets);

      const String expectedManifest = '{"packages/test_package/a/foo":'
          '["packages/test_package/a/foo","packages/test_package/a/v/foo"]}';

      await buildAndVerifyAssets(
        assets,
        <String>['test_package'],
        expectedManifest,
      );
    });

    testUsingContext('Two assets are bundled when the package has and lists two assets in its pubspec', () async {
      establishFlutterRoot();

      writePubspecFile('pubspec.yaml', 'test');
      writePackagesFile('test_package:p/p/lib/');

      final List<String> assets = <String>['a/foo', 'a/bar'];
      writePubspecFile(
        'p/p/pubspec.yaml',
        'test_package',
        assets: assets,
      );

      writeAssets('p/p/', assets);
      const String expectedAssetManifest =
          '{"packages/test_package/a/bar":["packages/test_package/a/bar"],'
          '"packages/test_package/a/foo":["packages/test_package/a/foo"]}';

      await buildAndVerifyAssets(
        assets,
        <String>['test_package'],
        expectedAssetManifest,
      );
    });

    testUsingContext("Two assets are bundled when the package has two assets, listed in the app's pubspec", () async {
      establishFlutterRoot();

      final List<String> assetEntries = <String>[
        'packages/test_package/a/foo',
        'packages/test_package/a/bar',
      ];
      writePubspecFile(
        'pubspec.yaml',
        'test',
         assets: assetEntries,
      );
      writePackagesFile('test_package:p/p/lib/');

      final List<String> assets = <String>['a/foo', 'a/bar'];
      writePubspecFile(
        'p/p/pubspec.yaml',
        'test_package',
      );

      writeAssets('p/p/lib/', assets);
      const String expectedAssetManifest =
          '{"packages/test_package/a/bar":["packages/test_package/a/bar"],'
          '"packages/test_package/a/foo":["packages/test_package/a/foo"]}';

      await buildAndVerifyAssets(
        assets,
        <String>['test_package'],
        expectedAssetManifest,
      );
    });

    testUsingContext('Two assets are bundled when two packages each have and list an asset their pubspec', () async {
      establishFlutterRoot();

      writePubspecFile(
        'pubspec.yaml',
        'test',
      );
      writePackagesFile('test_package:p/p/lib/\ntest_package2:p2/p/lib/');
      writePubspecFile(
        'p/p/pubspec.yaml',
        'test_package',
        assets: <String>['a/foo'],
      );
      writePubspecFile(
        'p2/p/pubspec.yaml',
        'test_package2',
        assets: <String>['a/foo'],
      );

      final List<String> assets = <String>['a/foo', 'a/v/foo'];
      writeAssets('p/p/', assets);
      writeAssets('p2/p/', assets);

      const String expectedAssetManifest =
          '{"packages/test_package/a/foo":'
          '["packages/test_package/a/foo","packages/test_package/a/v/foo"],'
          '"packages/test_package2/a/foo":'
          '["packages/test_package2/a/foo","packages/test_package2/a/v/foo"]}';

      await buildAndVerifyAssets(
        assets,
        <String>['test_package', 'test_package2'],
        expectedAssetManifest,
      );
    });

    testUsingContext("Two assets are bundled when two packages each have an asset, listed in the app's pubspec", () async {
      establishFlutterRoot();

      final List<String> assetEntries = <String>[
        'packages/test_package/a/foo',
        'packages/test_package2/a/foo',
      ];
      writePubspecFile(
        'pubspec.yaml',
        'test',
        assets: assetEntries,
      );
      writePackagesFile('test_package:p/p/lib/\ntest_package2:p2/p/lib/');
      writePubspecFile(
        'p/p/pubspec.yaml',
        'test_package',
      );
      writePubspecFile(
        'p2/p/pubspec.yaml',
        'test_package2',
      );

      final List<String> assets = <String>['a/foo', 'a/v/foo'];
      writeAssets('p/p/lib/', assets);
      writeAssets('p2/p/lib/', assets);

      const String expectedAssetManifest =
          '{"packages/test_package/a/foo":'
          '["packages/test_package/a/foo","packages/test_package/a/v/foo"],'
          '"packages/test_package2/a/foo":'
          '["packages/test_package2/a/foo","packages/test_package2/a/v/foo"]}';

      await buildAndVerifyAssets(
        assets,
        <String>['test_package', 'test_package2'],
        expectedAssetManifest,
      );
    });

    testUsingContext('One asset is bundled when the app depends on a package, listing in its pubspec an asset from another package', () async {
      establishFlutterRoot();
      writePubspecFile(
        'pubspec.yaml',
        'test',
      );
      writePackagesFile('test_package:p/p/lib/\ntest_package2:p2/p/lib/');
      writePubspecFile(
        'p/p/pubspec.yaml',
        'test_package',
        assets: <String>['packages/test_package2/a/foo'],
      );
      writePubspecFile(
        'p2/p/pubspec.yaml',
        'test_package2',
      );

      final List<String> assets = <String>['a/foo', 'a/v/foo'];
      writeAssets('p2/p/lib/', assets);

      const String expectedAssetManifest =
          '{"packages/test_package2/a/foo":'
          '["packages/test_package2/a/foo","packages/test_package2/a/v/foo"]}';

      await buildAndVerifyAssets(
        assets,
        <String>['test_package2'],
        expectedAssetManifest,
      );
    });
  });

  testUsingContext('Asset paths can contain URL reserved characters', () async {
    establishFlutterRoot();

    writePubspecFile('pubspec.yaml', 'test');
    writePackagesFile('test_package:p/p/lib/');

    final List<String> assets = <String>['a/foo', 'a/foo[x]'];
    writePubspecFile(
      'p/p/pubspec.yaml',
      'test_package',
      assets: assets,
    );

    writeAssets('p/p/', assets);
    const String expectedAssetManifest =
        '{"packages/test_package/a/foo":["packages/test_package/a/foo"],'
        '"packages/test_package/a/foo%5Bx%5D":["packages/test_package/a/foo%5Bx%5D"]}';

    await buildAndVerifyAssets(
      assets,
      <String>['test_package'],
      expectedAssetManifest,
    );
  });

  group('AssetBundle assets from scanned paths', () {
    testUsingContext(
        'Two assets are bundled when scanning their directory', () async {
      establishFlutterRoot();

      writePubspecFile('pubspec.yaml', 'test');
      writePackagesFile('test_package:p/p/lib/');

      final List<String> assetsOnDisk = <String>['a/foo', 'a/bar'];
      final List<String> assetsOnManifest = <String>['a/'];

      writePubspecFile(
        'p/p/pubspec.yaml',
        'test_package',
        assets: assetsOnManifest,
      );

      writeAssets('p/p/', assetsOnDisk);
      const String expectedAssetManifest =
          '{"packages/test_package/a/bar":["packages/test_package/a/bar"],'
          '"packages/test_package/a/foo":["packages/test_package/a/foo"]}';

      await buildAndVerifyAssets(
        assetsOnDisk,
        <String>['test_package'],
        expectedAssetManifest,
      );
    });

    testUsingContext(
        'Two assets are bundled when listing one and scanning second directory', () async {
      establishFlutterRoot();

      writePubspecFile('pubspec.yaml', 'test');
      writePackagesFile('test_package:p/p/lib/');

      final List<String> assetsOnDisk = <String>['a/foo', 'abc/bar'];
      final List<String> assetOnManifest = <String>['a/foo', 'abc/'];

      writePubspecFile(
        'p/p/pubspec.yaml',
        'test_package',
        assets: assetOnManifest,
      );

      writeAssets('p/p/', assetsOnDisk);
      const String expectedAssetManifest =
          '{"packages/test_package/abc/bar":["packages/test_package/abc/bar"],'
          '"packages/test_package/a/foo":["packages/test_package/a/foo"]}';

      await buildAndVerifyAssets(
        assetsOnDisk,
        <String>['test_package'],
        expectedAssetManifest,
      );
    });

    testUsingContext(
        'One asset is bundled with variant, scanning wrong directory', () async {
      establishFlutterRoot();

      writePubspecFile('pubspec.yaml', 'test');
      writePackagesFile('test_package:p/p/lib/');

      final List<String> assetsOnDisk = <String>['a/foo','a/b/foo','a/bar'];
      final List<String> assetOnManifest = <String>['a','a/bar']; // can't list 'a' as asset, should be 'a/'

      writePubspecFile(
        'p/p/pubspec.yaml',
        'test_package',
        assets: assetOnManifest,
      );

      writeAssets('p/p/', assetsOnDisk);

      final AssetBundle bundle = AssetBundleFactory.instance.createBundle();
      await bundle.build(manifestPath: 'pubspec.yaml');
      assert(bundle.entries['AssetManifest.json'] == null,'Invalid pubspec.yaml should not generate AssetManifest.json'  );
    });
  });

  group('AssetBundle assets from scanned paths with MemoryFileSystem', () {
    String readSchemaPath(FileSystem fs) {
      final String schemaPath = buildSchemaPath(fs);
      final File schemaFile = fs.file(schemaPath);

      return schemaFile.readAsStringSync();
    }

    void writeSchemaFile(FileSystem filesystem, String schemaData) {
      final String normalizeStep1 = buildSchemaPath(filesystem);

      final String normalizeStep2 = fs.path.toUri(normalizeStep1).toString();
      final Uri normalizeStep3 = Uri.parse(normalizeStep2);

      final io.File file = new io.File(normalizeStep3.toFilePath());

      final String dirname = fs
          .file(file.path)
          .dirname;
      final io.Directory dir = new io.Directory(dirname);
      dir.createSync(recursive: true);

      print('Dir exists? ${dir.existsSync()} -- ${dir.path}');

      file.writeAsStringSync(schemaData);

      print('File exists? ${file.existsSync()} -- ${file.path}');

    }

    void testUsingContextAndFs(String description, dynamic testMethod(),) {
      final FileSystem windowsFs = new MemoryFileSystem(
          style: FileSystemStyle.windows);

      final FileSystem posixFs = new MemoryFileSystem(
          style: FileSystemStyle.posix);

      const String _kFlutterRoot = '/flutter/flutter';
      establishFlutterRoot();

      final String schema = readSchemaPath(fs);

      testUsingContext('$description - on windows FS', () async {
        establishFlutterRoot();
        writeSchemaFile(windowsFs, schema);
        await testMethod();
      }, overrides: <Type, Generator>{
        FileSystem: () => windowsFs,
        Platform: () =>
        new FakePlatform(
            environment: <String, String>{'FLUTTER_ROOT': _kFlutterRoot,},
            operatingSystem: 'windows')
      });

      testUsingContext('$description - on posix FS', () async {
        establishFlutterRoot();
        writeSchemaFile(posixFs, schema);
        await testMethod();
      }, overrides: <Type, Generator>{
        FileSystem: () => posixFs,
        Platform: () =>
        new FakePlatform(
            environment: <String, String>{ 'FLUTTER_ROOT': _kFlutterRoot,},
            operatingSystem: 'linux')
      });

      testUsingContext('$description - on original FS', () async {
        establishFlutterRoot();
        await testMethod();
      });
    }

    testUsingContextAndFs(
        'One asset is bundled with variant, scanning directory', () async {
      establishFlutterRoot();

      writePubspecFile('pubspec.yaml', 'test');
      writePackagesFile('test_package:p/p/lib/');

      final List<String> assetsOnDisk = <String>['a/foo','a/b/foo'];
      final List<String> assetOnManifest = <String>['a/',];

      writePubspecFile(
        'p/p/pubspec.yaml',
        'test_package',
        assets: assetOnManifest,
      );

      writeAssets('p/p/', assetsOnDisk);
      const String expectedAssetManifest =
          '{"packages/test_package/a/foo":["packages/test_package/a/foo","packages/test_package/a/b/foo"]}';

      await buildAndVerifyAssets(
        assetsOnDisk,
        <String>['test_package'],
        expectedAssetManifest,
      );
    });

    testUsingContextAndFs(
        'No asset is bundled with variant, no assets or directories are listed', () async {
      establishFlutterRoot();

      writePubspecFile('pubspec.yaml', 'test');
      writePackagesFile('test_package:p/p/lib/');

      final List<String> assetsOnDisk = <String>['a/foo', 'a/b/foo'];
      final List<String> assetOnManifest = <String>[];

      writePubspecFile(
        'p/p/pubspec.yaml',
        'test_package',
        assets: assetOnManifest,
      );

      writeAssets('p/p/', assetsOnDisk);
      const String expectedAssetManifest = '{}';

      await buildAndVerifyAssets(
        assetOnManifest,
        <String>['test_package'],
        expectedAssetManifest,
      );
    });

    testUsingContextAndFs(
        'Expect error generating manifest, wrong non-existing directory is listed', () async {
      establishFlutterRoot();

      writePubspecFile('pubspec.yaml', 'test');
      writePackagesFile('test_package:p/p/lib/');

      final List<String> assetOnManifest = <String>['c/'];

      writePubspecFile(
        'p/p/pubspec.yaml',
        'test_package',
        assets: assetOnManifest,
      );

      try {
        await buildAndVerifyAssets(
          assetOnManifest,
          <String>['test_package'],
          null,
        );

        final Function watchdog = () async {
          assert(false, 'Code failed to detect missing directory. Test failed.');
        };
        watchdog();
      } catch (e) {
        // Test successful
      }
    });

  });
}
