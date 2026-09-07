import 'dart:io';

import 'package:flutter/material.dart';

import '../../domain/domain.dart';
import '../format.dart';
import '../strings.dart';

/// Anexo dentro da bolha: preview de imagem, nome/tamanho, progresso, ações.
///
/// [downloadProgress] não nulo = download em andamento (0..1); [localPath] não
/// nulo = já materializado em disco (aberto direto); nenhum dos dois = ainda
/// não baixado.
class AttachmentTile extends StatelessWidget {
  const AttachmentTile({
    super.key,
    required this.attachment,
    required this.localPath,
    required this.downloadProgress,
    required this.onDownload,
    required this.onOpen,
    this.onSurface,
  });
  final MessageAttachment attachment;
  final String? localPath;
  final double? downloadProgress;
  final VoidCallback onDownload;
  final VoidCallback onOpen;
  final Color? onSurface;

  @override
  Widget build(BuildContext context) {
    final a = attachment;
    final progress = downloadProgress;
    final hasLocal = localPath != null || a.downloaded;
    final preview = _imagePreview();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (preview != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: GestureDetector(
              key: Key('preview-${a.blobId}'),
              onTap: onOpen,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: preview,
              ),
            ),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              a.isImage
                  ? Icons.image_outlined
                  : Icons.insert_drive_file_outlined,
              color: onSurface,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: onSurface),
                  ),
                  Text(
                    _subtitle(progress),
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: onSurface),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (progress != null)
              SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(
                  key: Key('progress-${a.blobId}'),
                  value: progress,
                  strokeWidth: 3,
                  semanticsLabel: '${(progress * 100).round()}%',
                ),
              )
            else if (hasLocal)
              IconButton(
                key: Key('open-${a.blobId}'),
                tooltip: S.open,
                icon: Icon(Icons.open_in_new, color: onSurface),
                onPressed: onOpen,
              )
            else
              IconButton(
                key: Key('download-${a.blobId}'),
                tooltip: S.download,
                icon: Icon(Icons.download, color: onSurface),
                onPressed: onDownload,
              ),
          ],
        ),
        if (progress != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: LinearProgressIndicator(value: progress, minHeight: 3),
          ),
      ],
    );
  }

  String _subtitle(double? progress) {
    final size = formatSize(attachment.size);
    if (progress != null) {
      return '${S.downloading} ${(progress * 100).round()}% · $size';
    }
    return size;
  }

  Widget? _imagePreview() {
    final path = localPath;
    if (!attachment.isImage || path == null) return null;
    return Image.file(
      File(path),
      width: 240,
      fit: BoxFit.cover,
      semanticLabel: attachment.name,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
}
