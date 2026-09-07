import 'package:flutter_riverpod/flutter_riverpod.dart';

/// O que a UI está mostrando agora: usado para decidir se notifica.
class UiFocus {
  String? activeConvId;
  bool isForeground = true;
}

final uiFocusProvider = Provider<UiFocus>((_) => UiFocus());
