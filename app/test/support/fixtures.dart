import 'dart:convert';
import 'dart:io';

/// Lê uma fixture de `docs/protocol/fixtures/` (cwd = `app/` no `flutter test`).
Map<String, dynamic> loadFixture(String name) {
  final file = File('../docs/protocol/fixtures/$name.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}
