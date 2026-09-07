import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
