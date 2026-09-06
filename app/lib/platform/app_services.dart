import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/focus.dart';
import '../ui/notification_coordinator.dart';
import '../ui/providers.dart';
import '../ui/settings.dart';
import 'notifications.dart';
import 'push.dart';

/// Liga os serviços de plataforma à fachada: push → sync, notificações locais,
/// ciclo de vida (voltar ao foco → sync). Deve envolver o app dentro do `ProviderScope`.
class AppServices extends ConsumerStatefulWidget {
  const AppServices({super.key, required this.child, this.onOpenConversation});
  final Widget child;
  final void Function(String convId)? onOpenConversation;

  @override
  ConsumerState<AppServices> createState() => _AppServicesState();
}

class _AppServicesState extends ConsumerState<AppServices>
    with WidgetsBindingObserver {
  NotificationCoordinator? _coordinator;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final facade = ref.read(chatFacadeProvider);
    _coordinator = NotificationCoordinator(
      facade: facade,
      notifier: ref.read(localNotificationsProvider),
      focus: ref.read(uiFocusProvider),
      isEnabled: () => ref.read(settingsProvider).notificationsEnabled,
      onOpen: widget.onOpenConversation,
    )..start();
    ref
        .read(pushWakerProvider)
        .init(onWake: facade.sync, onToken: facade.setPushToken);
  }

  @override
  void didUpdateWidget(covariant AppServices old) {
    super.didUpdateWidget(old);
    _coordinator?.onOpen = widget.onOpenConversation;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final focus = ref.read(uiFocusProvider);
    focus.isForeground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      ref.read(chatFacadeProvider).sync();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _coordinator?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
