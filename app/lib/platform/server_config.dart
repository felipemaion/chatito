import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'platform_info.dart';

/// Endereço padrão do relay em desenvolvimento local: loopback no desktop,
/// alias especial do emulador Android para o `localhost` da máquina host.
String defaultServerUrl(PlatformInfo platform) =>
    platform.isAndroid ? 'http://10.0.2.2:8080' : 'http://127.0.0.1:8080';

class ServerUrlNotifier extends Notifier<String> {
  @override
  String build() => defaultServerUrl(ref.watch(platformInfoProvider));

  void set(String url) => state = url;
}

/// URL do relay, editável no onboarding. Só importa antes do registro: depois
/// a sessão persistida (`KeyStore`) fixa o servidor usado.
final serverUrlProvider = NotifierProvider<ServerUrlNotifier, String>(
  ServerUrlNotifier.new,
);
