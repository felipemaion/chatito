import 'package:flutter/material.dart';

import '../layout.dart';
import '../strings.dart';
import 'chat_screen.dart';
import 'conversations_screen.dart';

/// Desktop: lista à esquerda + chat à direita. Celular: uma tela por vez.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, this.selectedConvId});
  final String? selectedConvId;

  @override
  Widget build(BuildContext context) {
    final id = selectedConvId;
    if (!isWide(context)) {
      return id == null
          ? const ConversationsScreen()
          : ChatScreen(convId: id, showBack: true);
    }
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: sidebarWidth,
            child: ConversationsScreen(selectedConvId: id),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: id == null
                ? const _EmptyChat()
                : ChatScreen(key: ValueKey(id), convId: id),
          ),
        ],
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('chat-empty'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.forum_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            S.noConversation,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}
