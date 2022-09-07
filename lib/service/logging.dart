import 'package:flutter/foundation.dart';

void logError(String code, String? message) {
  if (message != null) {
    debugPrint('Error: $code\nError Message: $message');
  } else {
    debugPrint('Error: $code');
  }
}

void dPrint(Object? object) {
  if (kDebugMode) print(object);
}
