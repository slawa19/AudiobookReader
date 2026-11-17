import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

const appName = 'Book AudioReader';

/// The version shown on the license page. Kept equal to the part of `version:` in pubspec.yaml before the `+`; the
/// test `licenses_test.dart` fails when they differ. The Android build takes the version from pubspec.yaml too.
const appVersion = '0.1.0';

const repositoryUrl = 'https://github.com/slawa19/AudiobookReader';

const _copyright = '© 2026 Slawa Gorobets';

/// The license files bundled as assets (pubspec.yaml). The full GPL text is the repository's `LICENSE` file.
const projectLicenseAsset = 'LICENSE';
const merriweatherLicenseAsset = 'assets/fonts/Merriweather-OFL.txt';
const robotoLicenseAsset = 'assets/fonts/Roboto-OFL.txt';

/// Adds the notices that Flutter does not collect itself to [LicenseRegistry]: the project, and the two bundled fonts.
/// Flutter's own NOTICES already cover the pub packages and the engine. Call once at startup. The files are read
/// lazily, when the license page is opened.
void registerLicenses() => LicenseRegistry.addLicense(collectOwnLicenses);

/// The license entries of the project itself and of the bundled fonts. [bundle] is for tests.
Stream<LicenseEntry> collectOwnLicenses([AssetBundle? bundle]) async* {
  final assets = bundle ?? rootBundle;
  final project = await assets.loadString(projectLicenseAsset);
  yield LicenseEntryWithLineBreaks(
    [appName],
    '$_copyright\n\n'
    '$appName is free software: you can redistribute it and modify it under the terms of the GNU General Public '
    'License, version 3 or (at your option) any later version (GPL-3.0-or-later).\n\n'
    'Source code: $repositoryUrl\n\n'
    '$project',
  );
  yield LicenseEntryWithLineBreaks(['Merriweather'], await assets.loadString(merriweatherLicenseAsset));
  yield LicenseEntryWithLineBreaks(['Roboto'], await assets.loadString(robotoLicenseAsset));
}

/// The standard Flutter license page with the app name and version.
void openLicenses(BuildContext context) => showLicensePage(
      context: context,
      applicationName: appName,
      applicationVersion: appVersion,
      applicationLegalese: _copyright,
    );
