import '../platform/media_service.dart';
import '../playback/media_session.dart';

class AndroidMediaServiceLifecycle implements MediaServiceLifecycle {
  @override
  Future<void> awaitForeground() => AndroidMediaService.awaitForeground();
}
