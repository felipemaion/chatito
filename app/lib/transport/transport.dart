/// Camada `transport`: REST (`RelayApi`), WebSocket (`RelayWs`) e upload em
/// chunks (`ChunkUploader`). Dart puro (usa `dart:io` para o WS com header).
library;

export 'chunk_uploader.dart';
export 'relay_api.dart';
export 'relay_ws.dart';
