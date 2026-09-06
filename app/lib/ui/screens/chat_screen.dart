import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../platform/files.dart';
import '../../platform/platform_info.dart';
import '../contracts.dart';
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

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref.read(chatFacadeProvider).markRead(widget.convId),
    );
  }

  @override
  void dispose() {
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
            picked.path,
            name: picked.name,
            size: picked.size,
            mime: picked.mime,
          );
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _download(Message m, Attachment a) async {
    try {
      await ref.read(chatFacadeProvider).downloadAttachment(m.id, a.blobId);
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _open(Attachment a) async {
    final path = a.localPath;
    if (path == null) return;
    try {
      await ref.read(fileOpenerProvider).open(path);
    } catch (e) {
      _showError(e);
    }
  }

  void _openHeader(Conversation conv) {
    if (!conv.isGroup && conv.participantIds.isNotEmpty) {
      context.push('/contact/${conv.participantIds.first}');
      return;
    }
    final users = ref.read(directoryProvider);
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
            for (final u in users.where(
              (u) => conv.participantIds.contains(u.id),
            ))
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(u.name),
                onTap: () {
                  Navigator.of(ctx).pop();
                  context.push('/contact/${u.id}');
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
    final users = ref.watch(directoryProvider);
    final platform = ref.watch(platformInfoProvider);
    ref.listen(messagesProvider(widget.convId), (prev, next) {
      if ((prev?.length ?? 0) < next.length &&
          next.isNotEmpty &&
          !next.last.isMine) {
        ref.read(chatFacadeProvider).markRead(widget.convId);
      }
    });
    String nameOf(String userId) =>
        users.where((u) => u.id == userId).map((u) => u.name).firstOrNull ??
        userId;

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
                  conv?.isGroup == true ? Icons.groups : Icons.person,
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
                        senderName: nameOf(m.fromUserId),
                        showSender:
                            (conv?.isGroup ?? false) &&
                            prev?.fromUserId != m.fromUserId,
                        onDownload: (a) => _download(m, a),
                        onOpen: _open,
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
