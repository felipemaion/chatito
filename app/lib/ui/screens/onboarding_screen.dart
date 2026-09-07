import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/domain.dart';
import '../../platform/platform_info.dart';
import '../../platform/server_config.dart';
import '../providers.dart';
import '../strings.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _form = GlobalKey<FormState>();
  final _invite = TextEditingController();
  late final TextEditingController _device;
  late final TextEditingController _server;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _device = TextEditingController(
      text: ref.read(platformInfoProvider).defaultDeviceName,
    );
    _server = TextEditingController(text: ref.read(serverUrlProvider));
  }

  @override
  void dispose() {
    _invite.dispose();
    _device.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    ref.read(serverUrlProvider.notifier).set(_server.text.trim());
    try {
      await ref
          .read(chatFacadeProvider)
          .register(
            inviteCode: _invite.text.trim(),
            deviceName: _device.text.trim(),
            platform: ref.read(platformInfoProvider).name,
          );
      // O router redireciona ao observar a sessão; limpa a mensagem de sessão
      // inválida (se o motivo de estar aqui era essa e não "nunca registrado").
      ref.read(sessionInvalidProvider.notifier).set(false);
    } on ChatException catch (e) {
      setState(
        () => _error = e.code == 'invalid_invite' ? S.invalidInvite : e.message,
      );
    } catch (e) {
      setState(() => _error = '${S.error}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessionInvalid = ref.watch(sessionInvalidProvider);
    return Scaffold(
      key: const Key('onboarding'),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (sessionInvalid) ...[
                    Container(
                      key: const Key('session-invalid'),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber,
                            color: theme.colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              S.sessionExpired,
                              style: TextStyle(
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Icon(
                    Icons.lock_outline,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    S.onboardingTitle,
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(S.onboardingSubtitle, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const Key('invite'),
                    controller: _invite,
                    enabled: !_busy,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [const _InviteFormatter()],
                    decoration: const InputDecoration(
                      labelText: S.inviteCode,
                      hintText: 'XXXX-XXXX',
                      prefixIcon: Icon(Icons.vpn_key_outlined),
                    ),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? S.required : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('device-name'),
                    controller: _device,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: S.deviceName,
                      prefixIcon: Icon(Icons.devices_outlined),
                    ),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? S.required : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('server-url'),
                    controller: _server,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: S.serverUrl,
                      prefixIcon: Icon(Icons.dns_outlined),
                    ),
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? S.required : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      key: const Key('onboarding-error'),
                      style: TextStyle(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const Key('register'),
                    onPressed: _busy ? null : _submit,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: Text(_busy ? S.registering : S.register),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Maiúsculas, só [A-Z0-9], hífen automático após 4 caracteres.
class _InviteFormatter extends TextInputFormatter {
  const _InviteFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    final clipped = raw.length > 8 ? raw.substring(0, 8) : raw;
    final text = clipped.length > 4
        ? '${clipped.substring(0, 4)}-${clipped.substring(4)}'
        : clipped;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
