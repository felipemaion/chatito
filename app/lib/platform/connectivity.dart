import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Observa a conectividade de rede do SO para pedir reconexão assim que a
/// rede volta (o WS pode cair em segundo plano sem que o app receba
/// `AppLifecycleState.resumed`, ex.: troca de wifi para dados móveis).
abstract class ConnectivityWatcher {
  Future<void> init({required void Function() onOnline});
}

class NoopConnectivityWatcher implements ConnectivityWatcher {
  const NoopConnectivityWatcher();
  @override
  Future<void> init({required void Function() onOnline}) async {}
}

/// Guardado em try/catch: o canal de plataforma pode não existir em todo
/// alvo (ex.: testes, plataformas sem o plugin nativo) — o app segue
/// funcionando sem reconexão automática por rede nesse caso.
class SystemConnectivityWatcher implements ConnectivityWatcher {
  const SystemConnectivityWatcher();

  @override
  Future<void> init({required void Function() onOnline}) async {
    try {
      Connectivity().onConnectivityChanged.listen((results) {
        if (results.any((r) => r != ConnectivityResult.none)) onOnline();
      });
    } catch (e) {
      debugPrint('piriquito: connectivity_plus indisponível: $e');
    }
  }
}

final connectivityWatcherProvider = Provider<ConnectivityWatcher>(
  (_) => const SystemConnectivityWatcher(),
);
