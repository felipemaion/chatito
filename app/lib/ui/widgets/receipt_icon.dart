import 'package:flutter/material.dart';

import '../../domain/domain.dart';

/// Ícone de status da mensagem enviada (relógio, ✓, ✓✓, ✓✓ azul, erro).
class ReceiptIcon extends StatelessWidget {
  const ReceiptIcon(this.status, {super.key, this.size = 14, this.color});
  final MessageStatus status;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, c, label) = switch (status) {
      MessageStatus.pending => (Icons.schedule, color, 'Enviando'),
      MessageStatus.sent => (Icons.check, color, 'Enviada'),
      MessageStatus.delivered => (Icons.done_all, color, 'Entregue'),
      MessageStatus.read => (Icons.done_all, scheme.primary, 'Lida'),
      MessageStatus.failed => (Icons.error_outline, scheme.error, 'Falhou'),
    };
    return Semantics(
      label: label,
      child: Icon(
        icon,
        key: Key('receipt-${status.name}'),
        size: size,
        color: c,
      ),
    );
  }
}
