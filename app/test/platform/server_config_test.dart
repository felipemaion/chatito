import 'package:chatito/platform/platform_info.dart';
import 'package:chatito/platform/server_config.dart';
import 'package:chatito/storage/storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isValidServerUrl', () {
    test('aceita http(s) com e sem porta', () {
      expect(isValidServerUrl('http://127.0.0.1:8080'), isTrue);
      expect(isValidServerUrl('https://relay.exemplo.com'), isTrue);
      expect(isValidServerUrl('http://192.168.0.10:8080'), isTrue);
      expect(isValidServerUrl('  http://10.0.2.2:8080  '), isTrue);
    });

    test('rejeita vazio, sem esquema, esquema errado, caminho/query', () {
      expect(isValidServerUrl(''), isFalse);
      expect(isValidServerUrl('   '), isFalse);
      expect(isValidServerUrl('127.0.0.1:8080'), isFalse);
      expect(isValidServerUrl('ftp://127.0.0.1:8080'), isFalse);
      expect(isValidServerUrl('http://'), isFalse);
      expect(isValidServerUrl('http://127.0.0.1:8080/api'), isFalse);
      expect(isValidServerUrl('http://127.0.0.1:8080?x=1'), isFalse);
    });
  });

  group('loadSavedServerUrl / saveServerUrl', () {
    test('round-trip num MapKeyStore', () async {
      final store = InMemoryKeyStore();
      expect(await loadSavedServerUrl(store), isNull);
      await saveServerUrl(store, 'http://192.168.15.8:8080');
      expect(await loadSavedServerUrl(store), 'http://192.168.15.8:8080');
    });
  });

  group('ServerUrlNotifier', () {
    const platform = PlatformInfo(
      name: 'android',
      isDesktop: false,
      isAndroid: true,
    );

    test('sem URL salva, cai no padrão da plataforma', () {
      final container = ProviderContainer(
        overrides: [platformInfoProvider.overrideWithValue(platform)],
      );
      addTearDown(container.dispose);
      expect(container.read(serverUrlProvider), 'http://10.0.2.2:8080');
      expect(container.read(serverConfiguredProvider), isFalse);
    });

    test('com URL salva, usa ela e já marca como configurado', () {
      final container = ProviderContainer(
        overrides: [
          platformInfoProvider.overrideWithValue(platform),
          savedServerUrlProvider.overrideWithValue('http://192.168.15.8:8080'),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(serverUrlProvider), 'http://192.168.15.8:8080');
      expect(container.read(serverConfiguredProvider), isTrue);
    });
  });
}
