import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'platform_info.dart';

/// Notificações locais do sistema (abstração para testes).
abstract class LocalNotifications {
  Future<void> init({required void Function(String payload) onSelect});
  Future<void> show({
    required String title,
    required String body,
    String? payload,
  });
}

/// Implementação com `flutter_local_notifications` (macOS, Windows, Android, Linux).
class SystemLocalNotifications implements LocalNotifications {
  SystemLocalNotifications(this.platform);
  final PlatformInfo platform;
  final _plugin = FlutterLocalNotificationsPlugin();
  var _ready = false;
  var _nextId = 1;

  static const _channelId = 'messages';

  @override
  Future<void> init({required void Function(String payload) onSelect}) async {
    if (platform.name == 'web' || platform.name == 'unknown') return;
    try {
      final ok = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          macOS: DarwinInitializationSettings(),
          linux: LinuxInitializationSettings(defaultActionName: 'Abrir'),
          windows: WindowsInitializationSettings(
            appName: 'Piriquito',
            appUserModelId: 'br.com.maion.piriquito',
            guid: '5b0f4c2e-6d1a-4f8b-9c3e-2a7d8e9f0b1c',
          ),
        ),
        onDidReceiveNotificationResponse: (r) {
          final p = r.payload;
          if (p != null && p.isNotEmpty) onSelect(p);
        },
      );
      _ready = ok ?? true;
    } catch (_) {
      // Sem permissão/serviço de notificação: o app segue funcionando.
      _ready = false;
    }
  }

  @override
  Future<void> show({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: _nextId++,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Mensagens',
            channelDescription: 'Novas mensagens',
            importance: Importance.high,
            priority: Priority.high,
          ),
          macOS: DarwinNotificationDetails(),
          windows: WindowsNotificationDetails(),
        ),
      );
    } catch (_) {
      // Falha ao notificar não pode derrubar o app.
    }
  }
}

final localNotificationsProvider = Provider<LocalNotifications>(
  (ref) => SystemLocalNotifications(ref.watch(platformInfoProvider)),
);
