import '../library/settings.dart';

/// The fake engine needs no key. All consumers of one setting get
/// the same permission to synthesize; the dummy secret is neither stored nor shown.
class NativeSettings extends AppSettings {
  NativeSettings({required super.voice, required super.modelId, super.secretStore, required this.fakeTts});
  final bool fakeTts;
  @override
  bool get hasApiKey => fakeTts || super.hasApiKey;
}
