import 'package:chatito/platform/notifications.dart';
import 'package:chatito/ui/fake/fake_chat_facade.dart';
import 'package:chatito/ui/focus.dart';
import 'package:chatito/ui/notification_coordinator.dart';
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

void main() {
  late FakeChatFacade f;
  late _FakeNotifier n;
  late UiFocus focus;
  var enabled = true;
  late NotificationCoordinator c;

  setUp(() {
    f = FakeChatFacade.seeded();
    n = _FakeNotifier();
    focus = UiFocus();
    enabled = true;
    c = NotificationCoordinator(
      facade: f,
      notifier: n,
      focus: focus,
      isEnabled: () => enabled,
    )..start();
  });

  tearDown(() => c.stop());

  test(
    'mensagem recebida em conversa não aberta notifica com título e prévia',
    () async {
      f.simulateIncoming('g:familia', 'Jantar hoje?');
      await Future<void>.delayed(Duration.zero);
      expect(n.shown, hasLength(1));
      expect(n.shown.first.$1, 'Família');
      expect(n.shown.first.$2, 'Mãe: Jantar hoje?');
      expect(n.shown.first.$3, 'g:familia');
    },
  );

  test('não notifica a própria mensagem', () async {
    await f.sendText('g:familia', 'eu');
    await Future<void>.delayed(Duration.zero);
    expect(n.shown, isEmpty);
  });

  test('não notifica conversa aberta em primeiro plano', () async {
    focus.activeConvId = 'g:familia';
    focus.isForeground = true;
    f.simulateIncoming('g:familia', 'x');
    await Future<void>.delayed(Duration.zero);
    expect(n.shown, isEmpty);
  });

  test('notifica conversa aberta se o app está em segundo plano', () async {
    focus.activeConvId = 'g:familia';
    focus.isForeground = false;
    f.simulateIncoming('g:familia', 'x');
    await Future<void>.delayed(Duration.zero);
    expect(n.shown, hasLength(1));
  });

  test('preferência desligada silencia', () async {
    enabled = false;
    f.simulateIncoming('g:familia', 'x');
    await Future<void>.delayed(Duration.zero);
    expect(n.shown, isEmpty);
  });

  test('toque na notificação chama onOpen com a conversa', () async {
    String? opened;
    c.onOpen = (id) => opened = id;
    n.onTap!('u:usr_A:usr_B');
    expect(opened, 'u:usr_A:usr_B');
  });

  test('não repete notificação para a mesma mensagem', () async {
    f.simulateIncoming('g:familia', 'x');
    await Future<void>.delayed(Duration.zero);
    await f.markRead('g:familia'); // emite conversations de novo
    await Future<void>.delayed(Duration.zero);
    expect(n.shown, hasLength(1));
  });
}
