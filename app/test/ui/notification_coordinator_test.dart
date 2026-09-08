import 'package:piriquito/domain/fakes/fake_chat_facade.dart';
import 'package:piriquito/platform/notifications.dart';
import 'package:piriquito/protocol/protocol.dart' show ConvId;
import 'package:piriquito/ui/focus.dart';
import 'package:piriquito/ui/notification_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeNotifier implements LocalNotifications {
  final shown = <(String title, String body, String? payload)>[];
  void Function(String payload)? onTap;
  @override
  Future<void> init({required void Function(String payload) onSelect}) async =>
      onTap = onSelect;
  @override
  Future<void> show({
    required String title,
    required String body,
    String? payload,
  }) async => shown.add((title, body, payload));
}

/// [autoReply] controla se a Mãe "responde" (usado para simular mensagem
/// recebida): `false` usa um atraso longo, então só a minha mensagem é
/// observada dentro da janela do teste.
FakeChatFacade _facade({bool autoReply = false}) => FakeChatFacade(
  autoReplyDelay: autoReply ? Duration.zero : const Duration(days: 1),
);

void main() {
  final family = ConvId.family;
  late _FakeNotifier n;
  late UiFocus focus;
  var enabled = true;

  Future<NotificationCoordinator> start(FakeChatFacade f) async {
    n = _FakeNotifier();
    focus = UiFocus();
    enabled = true;
    final c = NotificationCoordinator(
      facade: f,
      notifier: n,
      focus: focus,
      isEnabled: () => enabled,
    )..start();
    addTearDown(c.stop);
    addTearDown(f.dispose);
    // O `Observable.stream` do domínio emite o valor atual de forma
    // assíncrona (async*); sem este respiro, uma ação síncrona logo após
    // `start()` pode disparar antes da assinatura terminar de se conectar
    // ao stream, e o evento se perde (broadcast sem buffer).
    await Future<void>.delayed(Duration.zero);
    return c;
  }

  test(
    'mensagem recebida (resposta automática) notifica com título e prévia',
    () async {
      final f = _facade(autoReply: true);
      await start(f);
      await f.sendText(family, 'Jantar hoje?');
      await Future<void>.delayed(Duration.zero);
      expect(n.shown, hasLength(1));
      expect(n.shown.first.$1, 'Família');
      expect(n.shown.first.$2, contains('Mãe:'));
      expect(n.shown.first.$3, family);
    },
  );

  test('não notifica a própria mensagem', () async {
    final f = _facade();
    await start(f);
    await f.sendText(family, 'eu');
    await Future<void>.delayed(Duration.zero);
    expect(n.shown, isEmpty);
  });

  test('não notifica conversa aberta em primeiro plano', () async {
    final f = _facade(autoReply: true);
    await start(f);
    focus.activeConvId = family;
    focus.isForeground = true;
    await f.sendText(family, 'x');
    await Future<void>.delayed(Duration.zero);
    expect(n.shown, isEmpty);
  });

  test('notifica conversa aberta se o app está em segundo plano', () async {
    final f = _facade(autoReply: true);
    await start(f);
    focus.activeConvId = family;
    focus.isForeground = false;
    await f.sendText(family, 'x');
    await Future<void>.delayed(Duration.zero);
    expect(n.shown, hasLength(1));
  });

  test('preferência desligada silencia', () async {
    final f = _facade(autoReply: true);
    await start(f);
    enabled = false;
    await f.sendText(family, 'x');
    await Future<void>.delayed(Duration.zero);
    expect(n.shown, isEmpty);
  });

  test('toque na notificação chama onOpen com a conversa', () async {
    final c = await start(_facade());
    String? opened;
    c.onOpen = (id) => opened = id;
    n.onTap!('u:usr_A:usr_B');
    expect(opened, 'u:usr_A:usr_B');
  });

  test('não repete notificação para a mesma mensagem', () async {
    final f = _facade(autoReply: true);
    await start(f);
    await f.sendText(family, 'x');
    await Future<void>.delayed(Duration.zero);
    await f.markRead(family); // emite conversations de novo, mesma última msg
    await Future<void>.delayed(Duration.zero);
    expect(n.shown, hasLength(1));
  });
}
