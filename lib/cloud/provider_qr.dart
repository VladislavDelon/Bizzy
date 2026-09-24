import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// QR-код профиля провайдера: payload `bizzy://p/<userId>`.
/// Клиент сканирует его прямо в приложении и попадает в профиль.
String providerQrPayload(String userId) => 'bizzy://p/$userId';

String? parseProviderQr(String raw) {
  final v = raw.trim();
  const prefixes = ['bizzy://p/', 'bizzy:p:', 'bizzy://provider/'];
  for (final p in prefixes) {
    if (v.startsWith(p)) {
      final id = v.substring(p.length).trim();
      return id.isEmpty ? null : id;
    }
  }
  return null;
}

/// Диалог «Поделиться профилем» у мастера/салона.
Future<void> showProviderQrDialog(
  BuildContext context, {
  required String name,
  required String userId,
}) {
  final payload = providerQrPayload(userId);
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(name.isEmpty ? 'Мой QR' : 'QR — $name'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: QrImageView(
              data: payload,
              size: 220,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Клиент сканирует код в приложении Bizzy '
            'и сразу попадает в ваш профиль.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: payload));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Ссылка скопирована')),
              );
            }
          },
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Ссылка'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Готово'),
        ),
      ],
    ),
  );
}
