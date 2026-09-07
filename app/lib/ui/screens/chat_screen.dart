import 'dart:io';

import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/domain.dart';
import '../../platform/attachment_files.dart';
import '../../platform/files.dart';
import '../../platform/platform_info.dart';
import '../attachment_progress.dart';
import '../focus.dart';
import '../providers.dart';
import '../strings.dart';
import '../widgets/composer.dart';
import '../widgets/connection_banner.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.convId, this.showBack = false});
  final String convId;
  final bool showBack;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scroll = ScrollController();
  late final UiFocus _focus;

  @override
  void initState() {
    super.initState();
    _focus = ref.read(uiFocusProvider)..activeConvId = widget.convId;
    Future<void>.microtask(
      () => ref.read(chatFacadeProvider).markRead(widget.convId),
    );
  }

  @override
  void didUpdateWidget(covariant ChatScreen old) {
    super.didUpdateWidget(old);
    if (old.convId != widget.convId) {
      _focus.activeConvId = widget.convId;
      ref.read(chatFacadeProvider).markRead(widget.convId);
    }
  }

  @override
  void dispose() {
    if (_focus.activeConvId == widget.convId) _focus.activeConvId = null;
    _scroll.dispose();
    super.dispose();
  }

  void _showError(Object e) {
    if (!mounted) return;
    final msg = e is ChatException ? e.message : '${S.error}: $e';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _send(String text) async {
    try {
      await ref.read(chatFacadeProvider).sendText(widget.convId, text);
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _attach() async {
    final picked = await ref.read(filePickerProvider).pick();
    if (picked == null) return;
    try {
      await ref
          .read(chatFacadeProvider)
          .sendFile(
            widget.convId,
            name: picked.name,
            mime: picked.mime,
            size: picked.size,
            data: File(picked.path).openRead(),
          );
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _materialize(Message m, MessageAttachment a) async {
    final progress = ref.read(downloadProgressProvider.notifier);
    progress.update(a.blobId, 0);
    try {
      final path = await materializeAttachment(
        blobId: a.blobId,
        name: a.name,
        bytes: ref
            .read(chatFacadeProvider)
            .readAttachment(messageId: m.id, blobId: a.blobId),
        onProgress: (received) => progress.update(
          a.blobId,
          a.size == 0 ? 1 : (received / a.size).clamp(0, 1),
        ),
      );
      if (!mounted) return;
      ref.read(attachmentPathsProvider.notifier).set(a.blobId, path);
    } catch (e) {
      _showError(e);
    } finally {
      progress.clear(a.blobId);
    }
  }

  Future<void> _download(Message m, MessageAttachment a) => _materialize(m, a);

  Future<void> _open(Message m, MessageAttachment a) async {
    final existing = ref.read(attachmentPathsProvider)[a.blobId];
    final path = existing ?? await _materializeAndReturn(m, a);
    if (path == null) return;
    try {
      await ref.read(fileOpenerProvider).open(path);
    } catch (e) {
      _showError(e);
    }
  }

  Future<String?> _materializeAndReturn(Message m, MessageAttachment a) async {
    await _materialize(m, a);
    return ref.read(attachmentPathsProvider)[a.blobId];
  }

  void _openHeader(Conversation conv) {
    if (conv.kind == ConversationKind.direct &&
        conv.participantUserIds.isNotEmpty) {
      context.push('/contact/${conv.participantUserIds.first}');
      return;
    }
    final contacts = ref.read(contactsProvider);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                S.members,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            for (final c in contacts.where(
              (c) => conv.participantUserIds.contains(c.user.id),
            ))
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(c.user.name),
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.push('/contact/${c.user.id}');
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final conv = ref.watch(conversationProvider(widget.convId));
    final messages = ref.watch(messagesProvider(widget.convId));
    final contacts = ref.watch(contactsProvider);
    final platform = ref.watch(platformInfoProvider);
    final progress = ref.watch(downloadProgressProvider);
    final paths = ref.watch(attachmentPathsProvider);
    ref.listen(messagesProvider(widget.convId), (prev, next) {
      if ((prev?.length ?? 0) < next.length &&
          next.isNotEmpty &&
          !next.last.isMine) {
        ref.read(chatFacadeProvider).markRead(widget.convId);
      }
    });
    String nameOf(String userId) => contactName(contacts, userId);

    return Scaffold(
      key: const Key('chat'),
      appBar: AppBar(
        leading: widget.showBack
            ? BackButton(onPressed: () => context.go('/'))
            : null,
        automaticallyImplyLeading: widget.showBack,
        title: InkWell(
          key: const Key('chat-title'),
          onTap: conv == null ? null : () => _openHeader(conv),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                child: Icon(
                  conv?.kind == ConversationKind.group
                      ? Icons.groups
                      : Icons.person,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  conv?.title ?? widget.convId,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          const ConnectionBanner(),
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Text(
                      S.noMessages,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  )
                : ListView.builder(
                    key: const Key('messages'),
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: messages.length,
                    itemBuilder: (context, i) {
                      final m = messages[messages.length - 1 - i];
                      final prev = messages.length - 2 - i >= 0
                          ? messages[messages.length - 2 - i]
                          : null;
                      return MessageBubble(
                        message: m,
                        senderName: nameOf(m.senderUserId),
                        showSender:
                            (conv?.kind == ConversationKind.group) &&
                            prev?.senderUserId != m.senderUserId,
                        downloadProgressOf: (blobId) => progress[blobId],
                        localPathOf: (blobId) => paths[blobId],
                        onDownload: (a) => _download(m, a),
                        onOpen: (a) => _open(m, a),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Composer(
            onSend: _send,
            onAttach: _attach,
            enterSends: platform.isDesktop,
          ),
        ],
      ),
    );
  }
}
