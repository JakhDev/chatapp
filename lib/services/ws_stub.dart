// lib/services/ws_stub.dart
// Web platformda WebSocketChannel o'rniga ishlatiladi

import 'dart:async';

class WebSocketChannel {
  final _ctrl = StreamController<dynamic>.broadcast();

  WebSocketChannel.connect(Uri uri);

  Stream<dynamic> get stream => _ctrl.stream;
  WebSocketSink   get sink   => _WebSocketSink();

  Future<void> get ready => Future.value();

  void close() => _ctrl.close();
}

class _WebSocketSink implements WebSocketSink {
  @override void add(dynamic data) {}
  @override void addError(Object e, [StackTrace? st]) {}
  @override Future addStream(Stream s) async {}
  @override Future close([int? code, String? reason]) async {}
  @override Future get done => Future.value();
}

abstract class WebSocketSink {
  void  add(dynamic data);
  void  addError(Object error, [StackTrace? stackTrace]);
  Future addStream(Stream stream);
  Future close([int? closeCode, String? closeReason]);
  Future get done;
}