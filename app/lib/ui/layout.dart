import 'package:flutter/widgets.dart';

/// Largura a partir da qual o layout vira "desktop" (lista + chat lado a lado).
const double wideBreakpoint = 720;

/// Largura da coluna de conversas no layout largo.
const double sidebarWidth = 320;

bool isWide(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= wideBreakpoint;
