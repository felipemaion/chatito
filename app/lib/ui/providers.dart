import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/domain.dart';
import '../protocol/protocol.dart' show User;

/// Fachada do núcleo. **Deve** ser sobrescrita no `ProviderScope` raiz.
final chatFacadeProvider = Provider<ChatFacade>(
  (_) => throw UnimplementedError('chatFacadeProvider não foi sobrescrito'),
);

/// Liga um `Stream<T>` (que emite o valor atual ao ouvir) a um [Notifier],
/// com [initial] como estado síncrono até a primeira emissão chegar.
mixin StreamBinder<T> on Notifier<T> {
  T bind(Stream<T> stream, T initial) {
    final sub = stream.listen((v) => state = v);
    ref.onDispose(sub.cancel);
    return initial;
  }
}

class SessionNotifier extends Notifier<SessionState>
    with StreamBinder<SessionState> {
  @override
  SessionState build() =>
      bind(ref.watch(chatFacadeProvider).watchSession(), const NotRegistered());
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(
  SessionNotifier.new,
);

/// `false` até a primeira emissão de `watchSession()` chegar. O router usa
/// isto para não redirecionar com base no `NotRegistered` inicial "de mentira"
/// (a sessão real pode já estar registrada; só ainda não emitiu).
class SessionReadyNotifier extends Notifier<bool> {
  @override
  bool build() {
    final sub = ref.watch(chatFacadeProvider).watchSession().listen((_) {
      if (!state) state = true;
    });
    ref.onDispose(sub.cancel);
    return false;
  }
}

final sessionReadyProvider = NotifierProvider<SessionReadyNotifier, bool>(
  SessionReadyNotifier.new,
);

/// Identidade registrada (null se ainda não registrado).
final registeredProvider = Provider<Registered?>((ref) {
  final s = ref.watch(sessionProvider);
  return s is Registered ? s : null;
});

extension SessionStateX on SessionState {
  bool get isRegistered => this is Registered;
}

class ConnectionNotifier extends Notifier<ConnectionState>
    with StreamBinder<ConnectionState> {
  @override
  ConnectionState build() => bind(
    ref.watch(chatFacadeProvider).watchConnection(),
    ConnectionState.offline,
  );
}

final connectionProvider =
    NotifierProvider<ConnectionNotifier, ConnectionState>(
      ConnectionNotifier.new,
    );

class ContactsNotifier extends Notifier<List<Contact>>
    with StreamBinder<List<Contact>> {
  @override
  List<Contact> build() =>
      bind(ref.watch(chatFacadeProvider).watchContacts(), const []);
}

final contactsProvider = NotifierProvider<ContactsNotifier, List<Contact>>(
  ContactsNotifier.new,
);

class ConversationsNotifier extends Notifier<List<Conversation>>
    with StreamBinder<List<Conversation>> {
  @override
  List<Conversation> build() =>
      bind(ref.watch(chatFacadeProvider).watchConversations(), const []);
}

final conversationsProvider =
    NotifierProvider<ConversationsNotifier, List<Conversation>>(
      ConversationsNotifier.new,
    );

class MessagesNotifier extends Notifier<List<Message>>
    with StreamBinder<List<Message>> {
  MessagesNotifier(this.convId);
  final String convId;

  @override
  List<Message> build() =>
      bind(ref.watch(chatFacadeProvider).watchMessages(convId), const []);
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

/// Contato (usuário + devices) por id de usuário.
final contactProvider = Provider.family<Contact?, String>((ref, userId) {
  for (final c in ref.watch(contactsProvider)) {
    if (c.user.id == userId) return c;
  }
  return null;
});

/// Nome de exibição de um usuário pelo id (fallback: o próprio id).
String contactName(List<Contact> contacts, String userId) =>
    contacts
        .where((c) => c.user.id == userId)
        .map((c) => c.user.name)
        .firstOrNull ??
    userId;

/// Todos os usuários visíveis (para telas que precisam de `User` cru).
final usersProvider = Provider<List<User>>(
  (ref) => [for (final c in ref.watch(contactsProvider)) c.user],
);
