import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/storage.dart';
import 'platform_info.dart';

/// Relay de produção (Fase 4): Oracle atrás da Cloudflare + Caddy.
const productionServerUrl = 'https://piriquito.maionesys.com';

/// Endereço padrão do relay. Em build release é o de produção; em
/// desenvolvimento é o relay local (loopback no desktop, alias especial do
/// emulador Android para o `localhost` da máquina host). O usuário sempre pode
/// trocar no onboarding ou em Ajustes (ver [savedServerUrlProvider]).
String defaultServerUrl(
  PlatformInfo platform, {
  bool release = const bool.fromEnvironment('dart.vm.product'),
}) {
  if (release) return productionServerUrl;
  return platform.isAndroid ? 'http://10.0.2.2:8080' : 'http://127.0.0.1:8080';
}

/// `true` se [input] é `http://host[:porta]` ou `https://host[:porta]` — só
/// o endereço base do relay, sem caminho/query/fragmento.
bool isValidServerUrl(String input) {
  final v = input.trim();
  if (v.isEmpty) return false;
  final uri = Uri.tryParse(v);
  if (uri == null) return false;
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  if (uri.host.isEmpty) return false;
  if (uri.path.isNotEmpty || uri.hasQuery || uri.hasFragment) return false;
  return true;
}

const _serverUrlStorageKey = 'server_url';

/// Lê a URL do servidor salva pela última vez que [saveServerUrl] rodou —
/// `null` se nunca foi salva (instalação nova, ou sessão registrada antes
/// desta correção). Chamado em `main()`, ANTES de montar a fachada real:
/// causa raiz confirmada em campo (logcat + `nc`) era o app reconstruir a
/// fachada com o endereço padrão (inalcançável fora do emulador/desktop de
/// dev) toda vez que reiniciava, porque nada persistia/recarregava a URL
/// digitada no onboarding.
///
/// Usa o mesmo [KeyStore] já aberto para identidade/token (arquivo no
/// desktop, secure storage no Android) — dado não secreto, mas evita puxar
/// mais uma dependência só pra isso. Só funciona se [keyStore] for um
/// [MapKeyStore] (as duas implementações reais são); outra implementação
/// (ex.: um fake mínimo de teste) simplesmente nunca persiste, sem erro.
Future<String?> loadSavedServerUrl(KeyStore keyStore) async {
  if (keyStore is! MapKeyStore) return null;
  return keyStore.read(_serverUrlStorageKey);
}

Future<void> saveServerUrl(KeyStore keyStore, String url) async {
  if (keyStore is! MapKeyStore) return;
  await keyStore.write(_serverUrlStorageKey, url);
}

/// A URL salva no boot (ver [loadSavedServerUrl]), injetada em `main()`
/// antes de qualquer provider que dependa dela ser construído — o
/// carregamento é assíncrono, mas acontece todo antes do `runApp`, então
/// nenhum provider chega a observar um valor "ainda carregando". `null` por
/// padrão (também o valor usado pelos testes de widget, a menos que
/// sobrescrito).
final savedServerUrlProvider = Provider<String?>((_) => null);

/// Como persistir uma nova URL (ver [saveServerUrl]) — sobrescrita em
/// `main.dart` com o [KeyStore] real. Fica como função solta em vez de
/// depender do `KeyStore`/`chatDepsProvider` direto: assim as telas que
/// mudam a URL (onboarding, Ajustes) não obrigam os testes de widget a
/// montar um keystore de verdade — o padrão em teste é não persistir nada.
final serverUrlPersisterProvider = Provider<Future<void> Function(String)>(
  (_) => (_) async {},
);

class ServerUrlNotifier extends Notifier<String> {
  @override
  String build() =>
      ref.watch(savedServerUrlProvider) ??
      defaultServerUrl(ref.watch(platformInfoProvider));

  void set(String url) => state = url;
}

/// URL do relay, editável no onboarding e em Ajustes. Reconstrói
/// automaticamente `realChatFacadeProvider` quando muda (que a observa via
/// `ref.watch`).
final serverUrlProvider = NotifierProvider<ServerUrlNotifier, String>(
  ServerUrlNotifier.new,
);

/// `true` assim que uma URL de servidor foi definida com sucesso nesta
/// instalação (salva no boot, ou definida agora via [commitServerUrl]).
/// `false` só no caso de instalação antiga: sessão já registrada (device
/// tem token/chaves), mas nunca passou por esta correção — a faixa de
/// conexão usa isto para mostrar "servidor não configurado" em vez de
/// tentar conectar silenciosamente no endereço padrão (quase certamente
/// errado num aparelho de verdade).
class ServerConfiguredNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(savedServerUrlProvider) != null;

  void markConfigured() => state = true;
}

final serverConfiguredProvider =
    NotifierProvider<ServerConfiguredNotifier, bool>(
      ServerConfiguredNotifier.new,
    );

/// Valida [url]; se válida, define [serverUrlProvider], marca
/// [serverConfiguredProvider] e persiste via [serverUrlPersisterProvider].
/// Usado tanto no onboarding quanto em Ajustes. Devolve `false` sem mexer em
/// nada se [url] for inválida.
Future<bool> commitServerUrl(WidgetRef ref, String url) async {
  final trimmed = url.trim();
  if (!isValidServerUrl(trimmed)) return false;
  ref.read(serverUrlProvider.notifier).set(trimmed);
  ref.read(serverConfiguredProvider.notifier).markConfigured();
  await ref.read(serverUrlPersisterProvider)(trimmed);
  return true;
}
