/// Regras de `conv_id` (PROTOCOL.md §5).
abstract final class ConvId {
  /// Grupo único do v1: todos os usuários do diretório.
  static const String family = 'g:familia';

  /// 1:1: `"u:" + os dois user_ids em ordem lexicográfica separados por ":"`.
  static String direct(String userA, String userB) {
    final sorted = [userA, userB]..sort();
    return 'u:${sorted[0]}:${sorted[1]}';
  }

  static bool isGroup(String convId) => convId.startsWith('g:');

  /// Os dois `user_id` de um 1:1, ou `null` se for grupo.
  static List<String>? directParticipants(String convId) {
    if (!convId.startsWith('u:')) return null;
    final parts = convId.substring(2).split(':');
    if (parts.length != 2) return null;
    return parts;
  }

  /// O outro usuário de um 1:1, dado o próprio `myUserId`.
  static String? peerOf(String convId, String myUserId) {
    final p = directParticipants(convId);
    if (p == null) return null;
    return p[0] == myUserId ? p[1] : p[0];
  }
}
