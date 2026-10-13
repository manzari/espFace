import 'package:flutter/services.dart';

/// Opens this app's page in the system settings (permission denial UX); Android only via MainActivity.
/// Returns false where unavailable so callers fall back to plain instructions.
Future<bool> openAppSettings() async {
  try {
    return await const MethodChannel('espface/platform').invokeMethod<bool>('openAppSettings') ?? false;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
