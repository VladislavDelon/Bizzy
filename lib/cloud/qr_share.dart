import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'provider_qr.dart';

export 'provider_qr.dart';

/// Сканер QR у клиента. Возвращает userId провайдера или null.
/// Только мобильные платформы — mobile_scanner на вебе не работает.
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
