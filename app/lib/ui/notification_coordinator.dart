import 'dart:async';

import '../domain/domain.dart';
import '../platform/notifications.dart';
import 'focus.dart';
import 'format.dart';

/// Observa as conversas e dispara notificação local para mensagens recebidas
/// que o usuário não está vendo. Dart puro (testável na VM).
class NotificationCoordinator {
  NotificationCoordinator({
    required this.facade,
    required this.notifier,
    required this.focus,
    required this.isEnabled,
    this.onOpen,
  });

  final ChatFacade facade;
  final LocalNotifications notifier;
  final UiFocus focus;
  final bool Function() isEnabled;

  /// Chamado com o `conv_id` quando o usuário toca na notificação.
  void Function(String convId)? onOpen;

  StreamSubscription<List<Conversation>>? _convSub;
  StreamSubscription<List<Contact>>? _contactsSub;
  final Map<String, String?> _lastSeen = {};
  List<Contact> _contacts = const [];
  bool _first = true;

  void start() {
    unawaited(notifier.init(onSelect: (payload) => onOpen?.call(payload)));
    _contactsSub = facade.watchContacts().listen((c) => _contacts = c);
    _convSub = facade.watchConversations().listen(_onConversations);
  }

  void stop() {
    _convSub?.cancel();
    _contactsSub?.cancel();
    _convSub = null;
    _contactsSub = null;
  }

  void _onConversations(List<Conversation> convs) {
    final first = _first;
    _first = false;
    for (final c in convs) {
      final last = c.lastMessage;
      final prevId = _lastSeen[c.id];
      _lastSeen[c.id] = last?.id;
      if (first || last == null || last.id == prevId || last.isMine) continue;
      if (!isEnabled()) continue;
      if (focus.isForeground && focus.activeConvId == c.id) continue;
      final sender = _contacts
          .where((u) => u.user.id == last.senderUserId)
          .map((u) => u.user.name)
          .firstOrNull;
      final body = c.kind == ConversationKind.group && sender != null
          ? '$sender: ${previewOf(last)}'
          : previewOf(last);
      unawaited(notifier.show(title: c.title, body: body, payload: c.id));
    }
  }
}
