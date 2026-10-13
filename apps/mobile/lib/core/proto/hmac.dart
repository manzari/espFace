import 'dart:convert';

import 'package:crypto/crypto.dart';

/// PROTOCOL.md 3.1: HMAC-SHA256(key = PIN utf8, msg = nonce_hex + device_id), lowercase hex.
String hmacPin(String pin, String nonceHex, String deviceId) =>
    Hmac(sha256, utf8.encode(pin)).convert(utf8.encode(nonceHex + deviceId)).toString();
