import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Session tokens per device id (PROTOCOL.md 3.1 step 3).
abstract class TokenStore {
  Future<String?> get(String deviceId);
  Future<void> put(String deviceId, String token);
  Future<void> remove(String deviceId);
}

class MemoryTokenStore implements TokenStore {
  final Map<String, String> tokens = {};
  @override
  Future<String?> get(String deviceId) async => tokens[deviceId];
  @override
  Future<void> put(String deviceId, String token) async => tokens[deviceId] = token;
  @override
  Future<void> remove(String deviceId) async => tokens.remove(deviceId);
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  String _key(String id) => 'espface.tok.$id';

  @override
  Future<String?> get(String deviceId) async {
    try {
      return await _s.read(key: _key(deviceId));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> put(String deviceId, String token) async {
    try {
      await _s.write(key: _key(deviceId), value: token);
    } catch (_) {}
  }

  @override
  Future<void> remove(String deviceId) async {
    try {
      await _s.delete(key: _key(deviceId));
    } catch (_) {}
  }
}
