import 'package:flutter/material.dart';

import '../contracts.dart';
import '../format.dart';
import '../strings.dart';
import 'attachment_tile.dart';
import 'receipt_icon.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.senderName,
    required this.showSender,
    required this.onDownload,
    required this.onOpen,
  });
  final Message message;
  final String senderName;
  final bool showSender;
  final void Function(Attachment) onDownload;
  final void Function(Attachment) onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = message.isMine;
    final bg = mine ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final fg = mine ? scheme.onPrimaryContainer : scheme.onSurface;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.75;
    final body = message.body;

    if (message.kind == MessageKind.keyChange) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Chip(
            avatar: const Icon(Icons.key, size: 16),
            label: Text(
              '$senderName: ${previewOf(message).replaceFirst('🔑 ', '')}',
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: '${mine ? S.you : senderName}, ${formatTime(message.sentAt)}',
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          key: Key('msg-${message.id}'),
          constraints: BoxConstraints(maxWidth: maxWidth.clamp(200, 560)),
          margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 12),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showSender && !mine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    senderName,
                    style: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(color: scheme.primary),
                  ),
                ),
              for (final a in message.attachments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: AttachmentTile(
                    attachment: a,
                    onSurface: fg,
                    onDownload: () => onDownload(a),
                    onOpen: () => onOpen(a),
                  ),
                ),
              if (body != null && body.isNotEmpty)
                SelectableText(body, style: TextStyle(color: fg)),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatTime(message.sentAt),
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: fg.withValues(alpha: 0.7)),
                  ),
                  if (mine) ...[
                    const SizedBox(width: 4),
                    ReceiptIcon(
                      message.status,
                      color: fg.withValues(alpha: 0.7),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
