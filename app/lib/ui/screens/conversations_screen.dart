import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/domain.dart';
import '../format.dart';
import '../providers.dart';
import '../strings.dart';
import '../widgets/connection_banner.dart';

class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key, this.selectedConvId});
  final String? selectedConvId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final convs = ref.watch(conversationsProvider);
    return Scaffold(
      key: const Key('conversations'),
      appBar: AppBar(
        title: const Text(S.conversations),
        actions: [
          IconButton(
            key: const Key('open-settings'),
            tooltip: S.settings,
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          const ConnectionBanner(),
          Expanded(
            child: ListView.builder(
              itemCount: convs.length,
              itemBuilder: (context, i) => _ConversationTile(
                conv: convs[i],
                selected: convs[i].id == selectedConvId,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conv, required this.selected});
  final Conversation conv;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final last = conv.lastMessage;
    final preview = last == null
        ? S.noMessages
        : '${last.isMine ? '${S.you}: ' : ''}${previewOf(last)}';
    return Semantics(
      label: '${conv.title}, ${conv.unreadCount} não lidas',
      child: ListTile(
        key: Key('conv-${conv.id}'),
        selected: selected,
        leading: CircleAvatar(
          child: Icon(
            conv.kind == ConversationKind.group ? Icons.groups : Icons.person,
          ),
        ),
        title: Text(conv.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatTime(conv.updatedAt),
              style: Theme.of(context).textTheme.labelSmall,
            ),
            if (conv.unreadCount > 0)
              Badge(
                key: Key('unread-${conv.id}'),
                label: Text('${conv.unreadCount}'),
              ),
          ],
        ),
        onTap: () => context.go('/c/${Uri.encodeComponent(conv.id)}'),
      ),
    );
  }
}
