import 'dart:async';

import 'contracts.dart';
import 'focus.dart';
import 'format.dart';
import '../platform/notifications.dart';

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

  StreamSubscription<List<Conversation>>? _sub;
  final Map<String, String?> _lastSeen = {};

  void start() {
    for (final c in facade.conversations.value) {
      _lastSeen[c.id] = c.lastMessage?.id;
    }
    unawaited(notifier.init(onSelect: (payload) => onOpen?.call(payload)));
    _sub = facade.conversations.stream.listen(_onConversations);
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  void _onConversations(List<Conversation> convs) {
    for (final c in convs) {
      final last = c.lastMessage;
      final prevId = _lastSeen[c.id];
      _lastSeen[c.id] = last?.id;
      if (last == null || last.id == prevId || last.isMine) continue;
      if (!isEnabled()) continue;
      if (focus.isForeground && focus.activeConvId == c.id) continue;
      final sender = facade.directory.value
          .where((u) => u.id == last.fromUserId)
          .map((u) => u.name)
          .firstOrNull;
      final body = c.isGroup && sender != null
          ? '$sender: ${previewOf(last)}'
          : previewOf(last);
      unawaited(notifier.show(title: c.title, body: body, payload: c.id));
    }
  }
}
