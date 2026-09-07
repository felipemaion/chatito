import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/domain.dart';
import '../../platform/server_config.dart';
import '../providers.dart';
import '../reconnect.dart';
import '../router.dart';
import '../strings.dart';

/// Faixa discreta quando o app está sem conexão com o relay — ou, num caso
/// mais específico (instalação antiga, registrada antes desta correção),
/// quando nem existe uma URL de servidor salva pra tentar. Nesse caso não
/// tenta reconectar sozinha (seria contra o endereço padrão de
/// desenvolvimento, quase certamente errado num aparelho de verdade):
/// manda direto para Ajustes configurar o servidor.
class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(connectionProvider);
    final registered = ref.watch(registeredProvider) != null;
    final configured = ref.watch(serverConfiguredProvider);
    final unconfigured = registered && !configured;
    if (state == ConnectionState.online && !unconfigured) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const Key('connection-banner'),
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(
              unconfigured ? Icons.dns_outlined : Icons.cloud_off,
              size: 16,
              color: scheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                unconfigured
                    ? S.serverNotConfigured
                    : (state == ConnectionState.offline
                          ? S.offline
                          : S.connecting),
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            TextButton(
              key: Key(unconfigured ? 'banner-open-settings' : 'reconnect'),
              onPressed: unconfigured
                  ? () => ref.read(routerProvider(null)).push('/settings')
                  : () => reconnectAndTrack(ref),
              child: Text(
                unconfigured ? S.settings : S.reconnect,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
