import 'package:material_ui/material_ui.dart';

const appName = 'Book AudioReader';

/// The version shown on the license page. Kept equal to the part of `version:` in pubspec.yaml before the `+`; the
/// test `licenses_test.dart` fails when they differ. The Android build takes the version from pubspec.yaml too.
const appVersion = '0.1.0';

const repositoryUrl = 'https://github.com/slawa19/BookAudioReader';

const _copyright = '© 2026 Slawa Gorobets';

/// The standard Flutter license page with the app name and version.
///
/// The page lists what the `flutter` tool collected into the app's NOTICES at build time: for every package, this app
/// included, it reads the package's `NOTICES` file, or its `LICENSE` when there is none. The `LICENSE` alone would be
/// listed under the Dart package name `audiobook_reader`. So the repository root carries a `NOTICES` file in the tool's
/// format (entries separated by a line of 80 dashes, each starting with its names and a blank line): the app under
/// [appName] with the copyright, GPL-3.0-or-later, [repositoryUrl] and the full text of `LICENSE`; the OFL texts of the
/// two bundled fonts; the sources of the demo texts. `test/licenses_test.dart` keeps it equal to those files.
void openLicenses(BuildContext context) => showLicensePage(
      context: context,
      applicationName: appName,
      applicationVersion: appVersion,
      applicationLegalese: _copyright,
    );
