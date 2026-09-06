import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers.dart';

class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key, required this.convId, this.showBack = false});
  final String convId;
  final bool showBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conv = ref.watch(conversationProvider(convId));
    return Scaffold(
      key: const Key('chat'),
      appBar: AppBar(
        leading: showBack ? BackButton(onPressed: () => context.go('/')) : null,
        automaticallyImplyLeading: showBack,
        title: Text(conv?.title ?? convId),
      ),
      body: const SizedBox.shrink(),
    );
  }
}
