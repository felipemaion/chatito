import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../storage/storage.dart';

/// [KeyStore] em arquivo, para desktop (macOS/Windows/Linux). Guarda tudo num
/// único JSON em `getApplicationSupportDirectory()/piriquito/keystore.json`,
/// com permissão `0600` (só o dono lê/escreve) onde o SO suporta.
///
/// Existe por causa de problemas reais de integração com o keychain nativo
/// nesta app (ex.: erro -34018 do Keychain no macOS com assinatura ad-hoc) —
/// um arquivo simples, cifrado só pelas permissões do SO e do diretório de
/// perfil do usuário, evita essa superfície inteira. Sem primitivas de
/// cripto próprias aqui: os *valores* guardados (chave privada, token) já
/// são a saída de `libsodium`/tokens opacos do servidor; o arquivo em si não
/// precisa adicionar outra camada de cifra caseira.
class FileKeyStore extends MapKeyStore {
  FileKeyStore(this._file);

  /// Abre (ou cria) o keystore de arquivo no diretório de dados do app.
  static Future<FileKeyStore> open({String fileName = 'keystore.json'}) async {
    final dir = await getApplicationSupportDirectory();
    return FileKeyStore(File('${dir.path}/piriquito/$fileName'));
  }

  final File _file;
  Map<String, String>? _cache;

  Future<Map<String, String>> _load() async {
    final cached = _cache;
    if (cached != null) return cached;
    if (!await _file.exists()) return _cache = {};
    try {
      final raw = await _file.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return _cache = decoded.map((k, v) => MapEntry(k, v as String));
    } on Object catch (e) {
      // Arquivo corrompido/ilegível: melhor começar vazio do que travar o
      // app inteiro por causa do keystore. Nunca apaga o arquivo original.
      debugPrint('piriquito: keystore de arquivo ilegível, ignorando: $e');
      return _cache = {};
    }
  }

  Future<void> _save(Map<String, String> data) async {
    _cache = data;
    await _file.parent.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(_file.path);
    await _restrictPermissions();
  }

  /// `chmod 600` — só o dono do arquivo lê/escreve. Sem equivalente POSIX no
  /// Windows (ACLs são outra API); lá a proteção vem de o diretório
  /// `%LOCALAPPDATA%` já ser exclusivo do usuário logado.
  Future<void> _restrictPermissions() async {
    if (Platform.isWindows) return;
    try {
      await Process.run('chmod', ['600', _file.path]);
    } on Object catch (e) {
      debugPrint('piriquito: não consegui restringir permissão do keystore: $e');
    }
  }

  @override
  Future<String?> read(String key) async => (await _load())[key];

  @override
  Future<void> write(String key, String value) async {
    final data = Map<String, String>.from(await _load());
    data[key] = value;
    await _save(data);
  }

  @override
  Future<void> delete(String key) async {
    final data = Map<String, String>.from(await _load());
    if (data.remove(key) != null) await _save(data);
  }

  /// Copia identidade/token/sessão de um keystore antigo (ex.: keychain via
  /// `SecureKeyStore`) na 1ª execução após a migração — só se este arquivo
  /// ainda estiver vazio, para nunca sobrescrever dados já migrados. **Não
  /// apaga nada do armazenamento antigo**: um resquício inofensivo ali é
  /// preferível a arriscar perda de identidade se a migração falhar no meio.
  Future<void> migrateFrom(KeyStore old) async {
    final hasLocal =
        await readIdentity() != null ||
        await readToken() != null ||
        await readSession() != null;
    if (hasLocal) return;
    final identity = await old.readIdentity();
    final token = await old.readToken();
    final session = await old.readSession();
    if (identity == null && token == null && session == null) return;
    if (identity != null) await writeIdentity(identity);
    if (token != null) await writeToken(token);
    if (session != null) await writeSession(session);
    debugPrint(
      'piriquito: keystore migrado do keychain para arquivo em ${_file.path}',
    );
  }
}
