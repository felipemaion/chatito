import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'platform_info.dart';

/// Configuração da janela no desktop (tamanho mínimo, título).
Future<void> setupWindow(PlatformInfo platform) async {
  if (!platform.isDesktop) return;
  try {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      title: 'Piriquito',
      minimumSize: Size(480, 600),
      size: Size(1100, 760),
      center: true,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  } catch (_) {
    // Sem window_manager (ex.: testes de integração): segue com a janela padrão.
  }
}
