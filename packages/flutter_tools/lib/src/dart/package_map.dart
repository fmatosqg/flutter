// Copyright 2016 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:package_config/packages_file.dart' as packages_file;

import '../base/file_system.dart';

const String kPackagesFileName = '.packages';

Map<String, Uri> _parse(String packagesPath) {
  final Uri uri = new Uri.file(packagesPath, windows: true);
  print('Needs unit test, _parse(packagesPath) $packagesPath');
  print('Needs unit test, uri of packagesPath  $uri');


//  final uri = packagesPath.replaceAll('C:\\','/C:/').replaceAll(':','' );
//  print('Uri is ${uri}, contents are \n${fs.file(packagesPath).readAsStringSync()}');
//  final uri= packagesPath;
  final List<int> source = fs.file(packagesPath).readAsBytesSync();
  final Map<dynamic, dynamic> theMap = packages_file.parse(source,
     uri );

  print('Needs unit test for map $theMap');

  return theMap;
}

class PackageMap {
  PackageMap(this.packagesPath);

  static String get globalPackagesPath => _globalPackagesPath ?? kPackagesFileName;

  static set globalPackagesPath(String value) {
    _globalPackagesPath = value;
  }

  static bool get isUsingCustomPackagesPath => _globalPackagesPath != null;

  static String _globalPackagesPath;

  final String packagesPath;

  /// Load and parses the .packages file.
  void load() {
    _map ??= _parse(packagesPath);
  }

  Map<String, Uri> get map {
    load();
    print('Package parsing gives $_map');
    return _map;
  }
  Map<String, Uri> _map;

  /// Returns the path to [packageUri].
  String pathForPackage(Uri packageUri) => uriForPackage(packageUri).path;

  /// Returns the path to [packageUri] as Uri.
  Uri uriForPackage(Uri packageUri) {
    assert(packageUri.scheme == 'package');
    final List<String> pathSegments = packageUri.pathSegments.toList();
    final String packageName = pathSegments.removeAt(0);
    final Uri packageBase = map[packageName];
    if (packageBase == null)
      return null;
    final String packageRelativePath = fs.path.joinAll(pathSegments);
    return packageBase.resolveUri(fs.path.toUri(packageRelativePath));
  }

  String checkValid() {
    if (fs.isFileSync(packagesPath))
      return null;
    String message = '$packagesPath does not exist.';
    final String pubspecPath = fs.path.absolute(fs.path.dirname(packagesPath), 'pubspec.yaml');
    if (fs.isFileSync(pubspecPath))
      message += '\nDid you run "flutter packages get" in this directory?';
    else
      message += '\nDid you run this command from the same directory as your pubspec.yaml file?';
    return message;
  }
}
