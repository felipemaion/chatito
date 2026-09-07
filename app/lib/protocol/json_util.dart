/// Conversores JSON compartilhados pelos modelos.
library;

import 'package:json_annotation/json_annotation.dart';

/// RFC 3339 UTC. Sem fração quando o instante é inteiro (`…:00Z`), com
/// milissegundos caso contrário — mantém round-trip exato com as fixtures.
class Rfc3339Converter implements JsonConverter<DateTime, String> {
  const Rfc3339Converter();

  @override
  DateTime fromJson(String json) => DateTime.parse(json).toUtc();

  @override
  String toJson(DateTime object) {
    final iso = object.toUtc().toIso8601String();
    return object.millisecond == 0 && object.microsecond == 0
        ? iso.replaceFirst(RegExp(r'\.\d+Z$'), 'Z')
        : iso;
  }
}
