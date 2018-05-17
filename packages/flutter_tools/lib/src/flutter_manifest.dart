// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert' as convert;
import 'dart:io' as io;

import 'package:json_schema/json_schema.dart';
import 'package:meta/meta.dart';
import 'package:yaml/yaml.dart';

import 'base/file_system.dart';
import 'cache.dart';
import 'globals.dart';

/// A wrapper around the `flutter` section in the `pubspec.yaml` file.
class FlutterManifest {
  FlutterManifest._();

  /// Returns null on invalid manifest. Returns empty manifest on missing file.
  static Future<FlutterManifest> createFromPath(String path) async {
    if (path == null || !fs.isFileSync(path))
      return _createFromYaml(null);
    final String manifest = await fs.file(path).readAsString();
    return createFromString(manifest);
  }

  /// Returns null on missing or invalid manifest
  @visibleForTesting
  static Future<FlutterManifest> createFromString(String manifest) async {
    return _createFromYaml(loadYaml(manifest));
  }

  static Future<FlutterManifest> _createFromYaml(Object yamlDocument) async {
    final FlutterManifest pubspec = new FlutterManifest._();
    if (yamlDocument != null && !await _validate(yamlDocument))
      return null;

    pubspec._descriptor = yamlDocument ?? <String, dynamic>{};
    pubspec._flutterDescriptor = pubspec._descriptor['flutter'] ?? <String, dynamic>{};
    return pubspec;
  }

  /// A map representation of the entire `pubspec.yaml` file.
  Map<String, dynamic> _descriptor;

  /// A map representation of the `flutter` section in the `pubspec.yaml` file.
  Map<String, dynamic> _flutterDescriptor;

  bool get isEmpty => _descriptor.isEmpty;

  String get appName => _descriptor['name'] ?? '';

  bool get usesMaterialDesign {
    return _flutterDescriptor['uses-material-design'] ?? false;
  }

  List<Map<String, dynamic>> get fontsDescriptor {
   return _flutterDescriptor['fonts'] ?? const <Map<String, dynamic>>[];
  }

  List<Uri> get assets {
    return _flutterDescriptor['assets']?.map(Uri.encodeFull)?.map(Uri.parse)?.toList() ?? const <Uri>[];
  }

  List<Font> _fonts;

  List<Font> get fonts {
    _fonts ??= _extractFonts();
    return _fonts;
  }

  List<Font> _extractFonts() {
    if (!_flutterDescriptor.containsKey('fonts'))
      return <Font>[];

    final List<Font> fonts = <Font>[];
    for (Map<String, dynamic> fontFamily in _flutterDescriptor['fonts']) {
      final List<Map<String, dynamic>> fontFiles = fontFamily['fonts'];
      final String familyName = fontFamily['family'];
      if (familyName == null) {
        printError('Warning: Missing family name for font.', emphasis: true);
        continue;
      }
      if (fontFiles == null) {
        printError('Warning: No fonts specified for font $familyName', emphasis: true);
        continue;
      }

      final List<FontAsset> fontAssets = <FontAsset>[];
      for (Map<String, dynamic> fontFile in fontFiles) {
        final String asset = fontFile['asset'];
        if (asset == null) {
          printError('Warning: Missing asset in fonts for $familyName', emphasis: true);
          continue;
        }

        fontAssets.add(new FontAsset(
          Uri.parse(asset),
          weight: fontFile['weight'],
          style: fontFile['style'],
        ));
      }
      if (fontAssets.isNotEmpty)
        fonts.add(new Font(fontFamily['family'], fontAssets));
    }
    return fonts;
  }
}

class Font {
  Font(this.familyName, this.fontAssets)
    : assert(familyName != null),
      assert(fontAssets != null),
      assert(fontAssets.isNotEmpty);

  final String familyName;
  final List<FontAsset> fontAssets;

  Map<String, dynamic> get descriptor {
    return <String, dynamic>{
      'family': familyName,
      'fonts': fontAssets.map((FontAsset a) => a.descriptor).toList(),
    };
  }

  @override
  String toString() => '$runtimeType(family: $familyName, assets: $fontAssets)';
}

class FontAsset {
  FontAsset(this.assetUri, {this.weight, this.style})
    : assert(assetUri != null);

  final Uri assetUri;
  final int weight;
  final String style;

  Map<String, dynamic> get descriptor {
    final Map<String, dynamic> descriptor = <String, dynamic>{};
    if (weight != null)
      descriptor['weight'] = weight;

    if (style != null)
      descriptor['style'] = style;

    descriptor['asset'] = assetUri.path;
    return descriptor;
  }

  @override
  String toString() => '$runtimeType(asset: ${assetUri.path}, weight; $weight, style: $style)';
}

@visibleForTesting
String buildSchemaDir(FileSystem fs) {
  return fs.path.join(
    fs.path.absolute(Cache.flutterRoot), 'packages', 'flutter_tools', 'schema',
  );
}

@visibleForTesting
String buildSchemaPath(FileSystem fs) {
  return fs.path.join(
    buildSchemaDir(fs),
    'pubspec_yaml.json',
  );
}

Future<Schema> futureSchema(String schemaUrl) async {
//  return Schema.createSchemaFromUrl(schemaUrl);

  final Uri uri = Uri.parse(schemaUrl);

//  final String newSchemaUrl = new Uri.file(schemaUrl,windows: true).toFilePath(windows: true);


//  final Uri uri = Uri.parse(newSchemaUrl);

  if (true) {
    final io.File file = new io.File(
        uri.scheme == 'file' ? uri.toFilePath() : schemaUrl);
    if (file.existsSync()) {
      print('File exists ${file.path}');
    } else {
      print('File NOT exists ${file.path} lets create it, scheme is ${uri.scheme}');

      final String dirname = fs
          .file(file.path)
          .dirname;
      final io.Directory dir = new io.Directory(dirname);
      if (dir.existsSync()) {
        print('Dir exists ${dir.path}');
      } else {
        print('Dir NOT exists ${dir.path}');

        dir.createSync(recursive: true);
        if (new io.Directory(dirname).existsSync()) {
          print('Dir now exists ${dir.path}');

//          file.writeAsStringSync('{}');

          final String whatever = new io.File(
              uri.scheme == 'file' ? uri.toFilePath() : schemaUrl)
              .readAsStringSync();

          print('Schema finally is read, contents: $whatever');
        } else {
          print('Dir still NOT exists ${dir.path}');
        }
      }
    }
  }


  print('Scheme is ${uri.scheme} -- $uri');

  if (uri.scheme == 'file' || uri.scheme == '') {
    return new io.File(uri.scheme == 'file' ? uri.toFilePath() : schemaUrl)
        .readAsString()
        .then((text) => Schema.createSchema(convert.json.decode(text)));
  } else {
    throw new Exception('Nonsense c: is a valid uri scheme: $schemaUrl');
  }
}
Future<bool> _validate(Object manifest) async {
  final String schemaPath = buildSchemaPath(fs);
/*
  final String schemaDir = buildSchemaDir(fs);


  final Uri uri = Uri.parse(schemaPath);

//  final String aa = schemaPath;//fs.path.toUri(schemaPath).toString();

  final io.File f = new io.File(uri.toFilePath());
  if (!f.existsSync()) {
    printError('File does not exist ${f.path}');

    if (!new io.Directory(schemaDir).existsSync()) {
      printError('Folder $schemaDir does not exist');

      new io.Directory(schemaDir).createSync(recursive: true);

      if (!new io.Directory(schemaDir).existsSync()) {
        printError('Folder ${schemaDir} still does not exist');
      }
    }
  } else {
    print ('File can find that thing ${f.path}');
  }

//  fs.directory(fs.file(aa).basename).createSync(recursive: true);
//  fs.file(aa).writeAsStringSync('{aaaaa}');

*/

  final Schema schema = await


  // original
//  Schema.createSchemaFromUrl(fs.path.toUri(schemaPath).toString());

  // last workable try
  futureSchema(fs.path.toUri(schemaPath).toString());

//  Schema.createSchemaFromUrl(fs.file(schemaPath).absolute.path); - url must be http, file or empty C:\Users/fmatos/code/android/flutter/fwk_flutter\packages\flutter_tools\schema\pubspec_yaml.json

//  Schema.createSchemaFromUrl(Uri.parse(schemaPath).toString()); //-- no such file or directory /C:/Users/fmatos/code/android/flutter/fwk_flutter/packages/flutter_tools/schema/pubspec_yaml.json

//  Schema.createSchemaFromUrl(
//      new Uri.file(schemaPath, windows: true).toFilePath(windows: true)); -- Url schemd must be http, file, or empty: C:\Users\fmatos\code\android\flutter\fwk_flutter\packages\flutter_tools\schema\pubspec_yaml.json

//  Schema.createSchemaFromUrl(
//     'file://'+ new Uri.file(schemaPath, windows: true).toFilePath(windows: false)); //-- Cannot open file, path = '/C:/Users/fmatos/code/android/flutter/fwk_flutter/packages/flutter_tools/schema/pubspec_yaml.json'

//  final Schema schema = await futureSchema(Uri.parse(schemaPath).toString());

//  final Schema schema = await futureSchema(Uri.parse(r'$schemaPath').toString());
//  final Schema schema = await futureSchema(schemaPath);

//  final Schema schema = await futureSchema(Uri.parse(r"${schemaPath}").toString());

//  final Schema schema = await Schema.createSchemaFromUrl(r'$schemaPath');

  final Validator validator = new Validator(schema);
  if (validator.validate(manifest)) {
    return true;
  } else {
    printStatus('Error detected in pubspec.yaml:', emphasis: true);
    printError(validator.errors.join('\n'));
    return false;
  }
}
