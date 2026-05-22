// lib/services/path_provider_stub.dart
// Web platformda path_provider o'rniga ishlatiladi

import 'dart:io';

Future<Directory> getTemporaryDirectory() async {
  throw UnsupportedError('getTemporaryDirectory() web platformda ishlamaydi');
}

Future<Directory> getApplicationDocumentsDirectory() async {
  throw UnsupportedError('getApplicationDocumentsDirectory() web platformda ishlamaydi');
}