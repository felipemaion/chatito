import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/domain.dart';
import '../providers.dart';
import '../reconnect.dart';
import '../strings.dart';

/// Faixa discreta quando o app está sem conexão com o relay.
class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(connectionProvider);
    if (state == ConnectionState.online) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const Key('connection-banner'),
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.cloud_off, size: 16, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                state == ConnectionState.offline ? S.offline : S.connecting,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            TextButton(
              key: const Key('reconnect'),
              onPressed: () => reconnectAndTrack(ref),
              child: Text(
                S.reconnect,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
