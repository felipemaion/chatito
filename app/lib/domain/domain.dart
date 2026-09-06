/// Camada `domain`: casos de uso e a interface [ChatFacade] consumida pela UI.
///
/// Dart puro (sem Flutter). A UI deve depender **só** deste barrel e de
/// `protocol` (para `User`/`Device`). Implementações: `RealChatFacade` (real)
/// e `fakes/FakeChatFacade` (memória, para desenvolvimento e testes de widget).
library;

export 'chat_facade.dart';
export 'models.dart';
