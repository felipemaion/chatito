import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'contracts.dart';

/// Fachada do núcleo. **Deve** ser sobrescrita no `ProviderScope` raiz.
final chatFacadeProvider = Provider<ChatFacade>(
  (_) => throw UnimplementedError('chatFacadeProvider não foi sobrescrito'),
);

/// Liga um [Watchable] a um [Notifier]: estado inicial síncrono + atualizações.
mixin WatchableBinder<T> on Notifier<T> {
  T bind(Watchable<T> w) {
    final sub = w.stream.listen((v) => state = v);
    ref.onDispose(sub.cancel);
    return w.value;
  }
}

class SessionNotifier extends Notifier<SessionState>
    with WatchableBinder<SessionState> {
  @override
  SessionState build() => bind(ref.watch(chatFacadeProvider).session);
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(
  SessionNotifier.new,
);

class ConnectionNotifier extends Notifier<RelayState>
    with WatchableBinder<RelayState> {
  @override
  RelayState build() => bind(ref.watch(chatFacadeProvider).connection);
}

final connectionProvider = NotifierProvider<ConnectionNotifier, RelayState>(
  ConnectionNotifier.new,
);

class ConversationsNotifier extends Notifier<List<Conversation>>
    with WatchableBinder<List<Conversation>> {
  @override
  List<Conversation> build() =>
      bind(ref.watch(chatFacadeProvider).conversations);
}

final conversationsProvider =
    NotifierProvider<ConversationsNotifier, List<Conversation>>(
      ConversationsNotifier.new,
    );

class DirectoryNotifier extends Notifier<List<UserInfo>>
    with WatchableBinder<List<UserInfo>> {
  @override
  List<UserInfo> build() => bind(ref.watch(chatFacadeProvider).directory);
}

final directoryProvider = NotifierProvider<DirectoryNotifier, List<UserInfo>>(
  DirectoryNotifier.new,
);

class MessagesNotifier extends Notifier<List<Message>>
    with WatchableBinder<List<Message>> {
  MessagesNotifier(this.convId);
  final String convId;

  @override
  List<Message> build() => bind(ref.watch(chatFacadeProvider).messages(convId));
}

final messagesProvider =
    NotifierProvider.family<MessagesNotifier, List<Message>, String>(
      MessagesNotifier.new,
    );

/// Conversa por id (null se não existir).
final conversationProvider = Provider.family<Conversation?, String>((ref, id) {
  for (final c in ref.watch(conversationsProvider)) {
    if (c.id == id) return c;
  }
  return null;
});

/// Usuário do diretório por id.
final userProvider = Provider.family<UserInfo?, String>((ref, id) {
  for (final u in ref.watch(directoryProvider)) {
    if (u.id == id) return u;
  }
  return null;
});
