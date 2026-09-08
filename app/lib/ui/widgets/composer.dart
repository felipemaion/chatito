import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../strings.dart';

/// Campo de texto + anexar (arquivo, mídia) + enviar. No desktop, Enter envia e Shift+Enter quebra linha.
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.onSend,
    required this.onAttach,
    required this.onAttachMedia,
    this.enterSends = true,
    this.busy = false,
  });
  final Future<void> Function(String text) onSend;
  final VoidCallback onAttach;
  final VoidCallback onAttachMedia;
  final bool enterSends;
  final bool busy;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _canSend => _controller.text.trim().isNotEmpty && !widget.busy;

  Future<void> _send() async {
    if (!_canSend) return;
    final text = _controller.text.trim();
    _controller.clear();
    await widget.onSend(text);
    _focus.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!widget.enterSends || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
    _send();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              key: const Key('attach'),
              tooltip: S.attach,
              icon: const Icon(Icons.attach_file),
              onPressed: widget.busy ? null : widget.onAttach,
            ),
            IconButton(
              key: const Key('attach-media'),
              tooltip: S.attachMedia,
              icon: const Icon(Icons.photo_library_outlined),
              onPressed: widget.busy ? null : widget.onAttachMedia,
            ),
            Expanded(
              child: Focus(
                onKeyEvent: _onKey,
                child: TextField(
                  key: const Key('composer'),
                  controller: _controller,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 6,
                  textInputAction: widget.enterSends
                      ? TextInputAction.send
                      : TextInputAction.newline,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                    hintText: S.messageHint,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(24)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              key: const Key('send'),
              tooltip: S.send,
              icon: const Icon(Icons.send),
              onPressed: _canSend ? _send : null,
            ),
          ],
        ),
      ),
    );
  }
}
