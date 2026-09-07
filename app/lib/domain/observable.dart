import 'dart:async';

/// Valor observável: [stream] emite o valor atual ao ouvir e cada mudança.
class Observable<T> {
  Observable(this._value);

  T _value;
  final _controller = StreamController<T>.broadcast();

  T get value => _value;

  set value(T v) {
    _value = v;
    if (!_controller.isClosed) _controller.add(v);
  }

  bool get isClosed => _controller.isClosed;

  Stream<T> get stream async* {
    yield _value;
    yield* _controller.stream;
  }

  Future<void> close() => _controller.close();
}
