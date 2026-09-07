import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Progresso de download de anexos em andamento (blobId → fração 0..1).
/// Sem entrada aqui: nada em andamento — o anexo já foi baixado
/// ([MessageAttachment.downloaded]) ou ainda não foi solicitado.
class DownloadProgressNotifier extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => const {};

  void update(String blobId, double fraction) =>
      state = {...state, blobId: fraction};

  void clear(String blobId) => state = {...state}..remove(blobId);
}

final downloadProgressProvider =
    NotifierProvider<DownloadProgressNotifier, Map<String, double>>(
      DownloadProgressNotifier.new,
    );

/// Caminho local do arquivo materializado (decifrado) de cada anexo já baixado
/// nesta sessão do app, para reabrir sem baixar de novo. blobId → path.
class AttachmentPathsNotifier extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {};

  void set(String blobId, String path) => state = {...state, blobId: path};
}

final attachmentPathsProvider =
    NotifierProvider<AttachmentPathsNotifier, Map<String, String>>(
      AttachmentPathsNotifier.new,
    );
