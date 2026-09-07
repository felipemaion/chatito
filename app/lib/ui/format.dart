import 'package:intl/intl.dart';

import '../domain/domain.dart';

/// Hora se for hoje, senão dia/mês (local do aparelho).
String formatTime(DateTime utc, {DateTime? now}) {
  final t = utc.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  final sameDay = t.year == n.year && t.month == n.month && t.day == n.day;
  return sameDay
      ? DateFormat.Hm('pt_BR').format(t)
      : DateFormat('dd/MM', 'pt_BR').format(t);
}

String formatDay(DateTime utc) =>
    DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(utc.toLocal());

/// 1024 → "1,0 KB"; 2457600 → "2,3 MB".
String formatSize(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final s = i == 0
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(1).replaceAll('.', ',');
  return '$s ${units[i]}';
}

/// Texto curto para a lista de conversas.
String previewOf(Message m) {
  switch (m.kind) {
    case MessageKind.text:
      return m.body ?? '';
    case MessageKind.file:
      final name = m.attachments.isEmpty ? '' : m.attachments.first.name;
      return '📎 ${m.body?.isNotEmpty == true ? m.body : name}';
    case MessageKind.keyChange:
      return '🔑 Chave de segurança alterada';
  }
}

/// `image/*` — usado para decidir se mostra preview de imagem.
extension MessageAttachmentX on MessageAttachment {
  bool get isImage => mime.startsWith('image/');
}
