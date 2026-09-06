import 'dart:io';

import 'package:flutter/material.dart';

import '../contracts.dart';
import '../format.dart';
import '../strings.dart';

/// Anexo dentro da bolha: preview de imagem, nome/tamanho, progresso, ações.
class AttachmentTile extends StatelessWidget {
  const AttachmentTile({
    super.key,
    required this.attachment,
    required this.onDownload,
    required this.onOpen,
    this.onSurface,
  });
  final Attachment attachment;
  final VoidCallback onDownload;
  final VoidCallback onOpen;
  final Color? onSurface;

  @override
  Widget build(BuildContext context) {
    final a = attachment;
    final t = a.transfer;
    final path = a.localPath;
    final hasLocal = path != null && t.state != TransferState.uploading;
    final preview = _imagePreview(a);
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
                    _subtitle(t),
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: onSurface),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (t.isActive)
              SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(
                  key: Key('progress-${a.blobId}'),
                  value: t.progress,
                  strokeWidth: 3,
                  semanticsLabel: '${(t.progress * 100).round()}%',
                ),
              )
            else if (t.state == TransferState.failed)
              IconButton(
                key: Key('retry-${a.blobId}'),
                tooltip: S.retry,
                icon: Icon(
                  Icons.refresh,
                  color: Theme.of(context).colorScheme.error,
                ),
                onPressed: hasLocal ? onOpen : onDownload,
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
        if (t.isActive)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: LinearProgressIndicator(value: t.progress, minHeight: 3),
          ),
      ],
    );
  }

  String _subtitle(TransferProgress t) {
    final size = formatSize(attachment.size);
    return switch (t.state) {
      TransferState.uploading =>
        '${S.uploading} ${(t.progress * 100).round()}% · $size',
      TransferState.downloading =>
        '${S.downloading} ${(t.progress * 100).round()}% · $size',
      TransferState.failed =>
        '${S.failed}${t.error != null ? ': ${t.error}' : ''} · $size',
      _ => size,
    };
  }

  Widget? _imagePreview(Attachment a) {
    final path = a.localPath;
    if (!a.isImage || path == null) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    return Image.file(
      file,
      width: 240,
      fit: BoxFit.cover,
      semanticLabel: a.name,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
}
