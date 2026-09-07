/// Camada `protocol`: modelos e (de)serialização do contrato `docs/PROTOCOL.md`.
///
/// Dart puro (sem Flutter). Binários ficam como `String` base64; quem decodifica
/// é a camada `crypto`.
library;

export 'conv_id.dart';
export 'models.dart';
export 'ws_frames.dart';
