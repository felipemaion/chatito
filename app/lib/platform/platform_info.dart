import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Informações estáticas da plataforma, injetáveis para testes.
class PlatformInfo {
  const PlatformInfo({
    required this.name,
    required this.isDesktop,
    required this.isAndroid,
  });

  /// `macos` | `windows` | `android` | `linux` | `web`.
  final String name;
  final bool isDesktop;
  final bool isAndroid;

  /// Nome sugerido para o device no onboarding.
  String get defaultDeviceName => switch (name) {
    'macos' => 'Mac',
    'windows' => 'PC Windows',
    'android' => 'Android',
    _ => name,
  };

  static PlatformInfo detect() {
    if (kIsWeb) {
      return const PlatformInfo(
        name: 'web',
        isDesktop: false,
        isAndroid: false,
      );
    }
    final name = Platform.isMacOS
        ? 'macos'
        : Platform.isWindows
        ? 'windows'
        : Platform.isAndroid
        ? 'android'
        : Platform.isLinux
        ? 'linux'
        : 'unknown';
    return PlatformInfo(
      name: name,
      isDesktop: Platform.isMacOS || Platform.isWindows || Platform.isLinux,
      isAndroid: Platform.isAndroid,
    );
  }
}

final platformInfoProvider = Provider<PlatformInfo>(
  (_) => PlatformInfo.detect(),
);
