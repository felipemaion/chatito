import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/server_config.dart';
import '../../protocol/protocol.dart' show Device, UserRole;
import '../providers.dart';
import '../settings.dart';
import '../strings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const appVersion = '0.1.0';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(registeredProvider);
    final myContact = me == null
        ? null
        : ref.watch(contactProvider(me.user.id));
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    Widget header(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        t,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
    return Scaffold(
      key: const Key('settings'),
      appBar: AppBar(title: const Text(S.settings)),
      body: ListView(
        children: [
          if (me != null)
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(me.user.name),
              subtitle: Text(
                me.user.role == UserRole.admin ? 'Administrador' : 'Membro',
              ),
            ),
          header(S.myDevices),
          for (final d in myContact?.devices ?? const <Device>[])
            ListTile(
              leading: Icon(_platformIcon(d.platform)),
              title: Text(
                d.id == me?.device.id ? '${d.name} (${S.thisDevice})' : d.name,
              ),
              subtitle: Text(d.platform),
            ),
          header(S.serverUrl),
          const _ServerUrlSection(),
          header(S.notifications),
          SwitchListTile(
            key: const Key('notifications-switch'),
            title: const Text(S.notificationsEnabled),
            value: settings.notificationsEnabled,
            onChanged: (v) =>
                ref.read(settingsProvider.notifier).setNotifications(v),
          ),
          header(S.about),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('${S.appName} · ${S.version} $appVersion'),
            subtitle: Text(S.protocol),
          ),
          if (me != null)
            ListTile(
              leading: const Icon(Icons.fingerprint),
              title: const Text('Identificadores'),
              subtitle: Text('${me.user.id}\n${me.device.id}'),
              isThreeLine: true,
            ),
        ],
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

/// Endereço do relay, editável a qualquer momento (não só no onboarding) —
/// para quando o servidor muda de endereço ou a instalação é antiga e nunca
/// teve um salvo (ver `ConnectionBanner`/`serverConfiguredProvider`). Ao
/// salvar, `serverUrlProvider` muda, o que já reconstrói
/// `realChatFacadeProvider` sozinho (ele observa `serverUrlProvider`);
/// depois disso só falta pedir pra conectar na fachada nova.
class _ServerUrlSection extends ConsumerStatefulWidget {
  const _ServerUrlSection();

  @override
  ConsumerState<_ServerUrlSection> createState() => _ServerUrlSectionState();
}

class _ServerUrlSectionState extends ConsumerState<_ServerUrlSection> {
  late final TextEditingController _controller;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(serverUrlProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    final url = _controller.text.trim();
    if (!isValidServerUrl(url)) {
      setState(() => _error = S.invalidServerUrl);
      return;
    }
    setState(() => _busy = true);
    await commitServerUrl(ref, url);
    try {
      await ref.read(chatFacadeProvider).ensureConnected();
    } on Object catch (_) {
      // Silencioso de propósito: a faixa de conexão já mostra o estado de
      // novo (offline/conectando) se isto falhar — não precisa duplicar o
      // erro aqui.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('settings-server-url'),
            controller: _controller,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: S.serverUrl,
              errorText: _error,
              prefixIcon: const Icon(Icons.dns_outlined),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const Key('save-server-url'),
              onPressed: _busy ? null : _save,
              child: Text(_busy ? S.registering : S.save),
            ),
          ),
        ],
      ),
    );
  }
}
