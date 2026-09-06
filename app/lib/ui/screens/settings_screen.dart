import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../contracts.dart';
import '../providers.dart';
import '../settings.dart';
import '../strings.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const appVersion = '0.1.0';

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    DeviceInfo d,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${S.removeDevice}: ${d.name}'),
        content: const Text(S.removeDeviceConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(S.remove),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(chatFacadeProvider).removeDevice(d.id);
    } catch (e) {
      if (!context.mounted) return;
      final msg = e is ChatException ? e.message : '$e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(sessionProvider).me;
    final myUser = me == null ? null : ref.watch(userProvider(me.user.id));
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
              subtitle: Text(me.user.isAdmin ? 'Administrador' : 'Membro'),
            ),
          header(S.myDevices),
          for (final d in myUser?.devices ?? const <DeviceInfo>[])
            ListTile(
              leading: Icon(_platformIcon(d.platform)),
              title: Text(
                d.id == me?.device.id ? '${d.name} (${S.thisDevice})' : d.name,
              ),
              subtitle: Text(d.platform),
              trailing: d.id == me?.device.id
                  ? null
                  : IconButton(
                      key: Key('remove-${d.id}'),
                      tooltip: S.removeDevice,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _remove(context, ref, d),
                    ),
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
