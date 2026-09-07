import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Preferências locais da UI.
class UiSettings {
  const UiSettings({this.notificationsEnabled = true});
  final bool notificationsEnabled;

  UiSettings copyWith({bool? notificationsEnabled}) => UiSettings(
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
  );
}

/// Persistência das preferências (em memória por padrão; o storage do app-core pode
/// fornecer uma implementação durável via override).
abstract class SettingsStore {
  Future<UiSettings> load();
  Future<void> save(UiSettings s);
}

class InMemorySettingsStore implements SettingsStore {
  UiSettings _value = const UiSettings();
  @override
  Future<UiSettings> load() async => _value;
  @override
  Future<void> save(UiSettings s) async => _value = s;
}

final settingsStoreProvider = Provider<SettingsStore>(
  (_) => InMemorySettingsStore(),
);

class SettingsNotifier extends Notifier<UiSettings> {
  @override
  UiSettings build() {
    ref.read(settingsStoreProvider).load().then((s) => state = s);
    return const UiSettings();
  }

  Future<void> setNotifications(bool enabled) async {
    state = state.copyWith(notificationsEnabled: enabled);
    await ref.read(settingsStoreProvider).save(state);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, UiSettings>(
  SettingsNotifier.new,
);
