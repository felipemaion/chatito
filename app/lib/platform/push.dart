import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'platform_info.dart';

/// Push "acorda e busca" (FCM data-only `{"type":"wake"}`), abstraído para testes.
abstract class PushWaker {
  Future<void> init({
    required void Function() onWake,
    required void Function(String? token) onToken,
  });
}

class NoopPushWaker implements PushWaker {
  const NoopPushWaker();
  @override
  Future<void> init({
    required void Function() onWake,
    required void Function(String? token) onToken,
  }) async {}
}

/// Handler de background (isolate separado). Sem acesso à fachada aqui: a
/// sincronização acontece quando o app volta ao primeiro plano.
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {}

/// Android: inicializa o Firebase se houver `google-services.json`; caso contrário,
/// falha silenciosamente e o app funciona sem push (WS em primeiro plano).
class FirebasePushWaker implements PushWaker {
  const FirebasePushWaker();

  static bool isWake(Map<String, dynamic> data) => data['type'] == 'wake';

  @override
  Future<void> init({
    required void Function() onWake,
    required void Function(String? token) onToken,
  }) async {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint(
        'chatito: Firebase indisponível (sem google-services.json?): $e',
      );
      return;
    }
    try {
      final fm = FirebaseMessaging.instance;
      FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);
      await fm.requestPermission();
      onToken(await fm.getToken());
      fm.onTokenRefresh.listen(onToken);
      FirebaseMessaging.onMessage.listen((m) {
        if (isWake(m.data)) onWake();
      });
      FirebaseMessaging.onMessageOpenedApp.listen((_) => onWake());
    } catch (e) {
      debugPrint('chatito: push desativado: $e');
    }
  }
}

final pushWakerProvider = Provider<PushWaker>((ref) {
  final p = ref.watch(platformInfoProvider);
  return p.isAndroid ? const FirebasePushWaker() : const NoopPushWaker();
});
