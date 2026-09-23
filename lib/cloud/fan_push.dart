import '../notifications/push_stub.dart'
    if (dart.library.io) '../notifications/push_service.dart';
import 'cloud_service.dart';

/// Push всем клиентам, у которых этот мастер/салон в избранном.
/// Используется при публикации новой услуги, фото работ и Honey.
/// Никогда не бросает исключение — уведомления не должны
/// блокировать сохранение.
Future<void> notifyFavoriteClients({
  required String title,
  required String body,
}) async {
  try {
    final clientIds = await CloudService().fanClientIds();
    for (final clientId in clientIds) {
      try {
        await PushNotificationService.sendPush(
          toUserId: clientId,
          title: title,
          body: body,
        );
      } catch (e) {
        await SyncLog.write('fan_push', 'push $clientId: $e');
      }
    }
  } catch (e) {
    await SyncLog.write('fan_push', 'fanClientIds: $e');
  }
}
