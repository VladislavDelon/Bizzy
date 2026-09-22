import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
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

/// Сканер QR у клиента. Возвращает userId провайдера или null.
class ProviderQrScanScreen extends StatefulWidget {
  const ProviderQrScanScreen({super.key});

  @override
  State<ProviderQrScanScreen> createState() => _ProviderQrScanScreenState();
}

class _ProviderQrScanScreenState extends State<ProviderQrScanScreen> {
  final _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final b in capture.barcodes) {
      final id = parseProviderQr(b.rawValue ?? '');
      if (id != null) {
        _handled = true;
        Navigator.of(context).pop(id);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сканировать QR')),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.all(16),
              child: const Text(
                'Наведите камеру на QR мастера или салона',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
