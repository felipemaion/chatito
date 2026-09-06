import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../platform/qr_scanner.dart';
import '../contracts.dart';
import '../providers.dart';
import '../strings.dart';
import '../widgets/safety_number_view.dart';

/// Detalhe do contato: aparelhos, safety number + QR por aparelho, leitura de QR.
class ContactDetailScreen extends ConsumerWidget {
  const ContactDetailScreen({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider(userId));
    final me = ref.watch(sessionProvider).me;
    if (user == null) {
      return Scaffold(
        key: const Key('contact'),
        appBar: AppBar(title: const Text(S.contact)),
        body: const Center(
          key: Key('contact-missing'),
          child: Text('Contato não encontrado'),
        ),
      );
    }
    final convId = me == null ? null : _dmId(me.user.id, user.id);
    return Scaffold(
      key: const Key('contact'),
      appBar: AppBar(title: Text(user.name)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ListTile(
            leading: const CircleAvatar(radius: 24, child: Icon(Icons.person)),
            title: Text(
              user.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            subtitle: Text(user.isAdmin ? 'Administrador' : 'Membro'),
            trailing: convId == null || user.id == me?.user.id
                ? null
                : FilledButton.tonalIcon(
                    key: const Key('open-chat'),
                    onPressed: () =>
                        context.go('/c/${Uri.encodeComponent(convId)}'),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('Conversar'),
                  ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              S.devices,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              S.safetyNumberHelp,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          for (final d in user.devices)
            _DeviceCard(device: d, isMine: d.id == me?.device.id),
        ],
      ),
    );
  }

  static String _dmId(String a, String b) {
    final ids = [a, b]..sort();
    return 'u:${ids[0]}:${ids[1]}';
  }
}

class _DeviceCard extends ConsumerStatefulWidget {
  const _DeviceCard({required this.device, required this.isMine});
  final DeviceInfo device;
  final bool isMine;

  @override
  ConsumerState<_DeviceCard> createState() => _DeviceCardState();
}

class _DeviceCardState extends ConsumerState<_DeviceCard> {
  bool? _verified;

  Future<void> _scan(String expected) async {
    final read = await ref.read(qrScannerProvider).scan(context);
    if (read == null || !mounted) return;
    setState(
      () =>
          _verified = read.replaceAll(' ', '') == expected.replaceAll(' ', ''),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    final scheme = Theme.of(context).colorScheme;
    final scanner = ref.watch(qrScannerProvider);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(_platformIcon(d.platform)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.isMine ? '${d.name} (${S.thisDevice})' : d.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (!widget.isMine) ...[
              const SizedBox(height: 12),
              FutureBuilder<String>(
                future: ref.read(chatFacadeProvider).safetyNumber(d.id),
                builder: (context, snap) {
                  final sn = snap.data;
                  if (sn == null) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return Column(
                    children: [
                      SafetyNumberView(safetyNumber: sn),
                      const SizedBox(height: 12),
                      if (_verified != null)
                        Chip(
                          key: Key('verify-${d.id}'),
                          avatar: Icon(
                            _verified! ? Icons.verified : Icons.warning_amber,
                            color: _verified! ? scheme.primary : scheme.error,
                          ),
                          label: Text(_verified! ? S.verified : S.notVerified),
                        ),
                      if (scanner.isSupported)
                        OutlinedButton.icon(
                          key: Key('scan-${d.id}'),
                          onPressed: () => _scan(sn),
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text(S.scanQr),
                        ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  static IconData _platformIcon(String p) => switch (p) {
    'android' => Icons.phone_android,
    'macos' => Icons.laptop_mac,
    'windows' => Icons.laptop_windows,
    _ => Icons.devices,
  };
}
