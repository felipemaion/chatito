import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'platform_info.dart';

/// Leitura de QR (abstração para testes; câmera só em Android/macOS).
abstract class QrScannerService {
  bool get isSupported;

  /// Abre o leitor e devolve o conteúdo do primeiro QR lido (null se cancelado).
  Future<String?> scan(BuildContext context);
}

class CameraQrScanner implements QrScannerService {
  const CameraQrScanner(this.platform);
  final PlatformInfo platform;

  @override
  bool get isSupported => platform.isAndroid || platform.name == 'macos';

  @override
  Future<String?> scan(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const _ScannerPage(),
        fullscreenDialog: true,
      ),
    );
  }
}

class _ScannerPage extends StatefulWidget {
  const _ScannerPage();

  @override
  State<_ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<_ScannerPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final value = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (value == null) return;
    _done = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ler QR')),
      body: MobileScanner(controller: _controller, onDetect: _onDetect),
    );
  }
}

final qrScannerProvider = Provider<QrScannerService>(
  (ref) => CameraQrScanner(ref.watch(platformInfoProvider)),
);
