import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../strings.dart';

/// 60 dígitos em 12 grupos de 5 + QR com o mesmo conteúdo.
class SafetyNumberView extends StatelessWidget {
  const SafetyNumberView({super.key, required this.safetyNumber});
  final String safetyNumber;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Semantics(
          label: '${S.safetyNumber}: ${safetyNumber.split(' ').join(', ')}',
          child: Container(
            padding: const EdgeInsets.all(8),
            color: Colors.white,
            child: QrImageView(
              data: safetyNumber,
              size: 180,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Colors.black,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Colors.black,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: safetyNumber));
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('Copiado')));
          },
          child: Text(
            safetyNumber,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontFamily: 'monospace',
              letterSpacing: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}
