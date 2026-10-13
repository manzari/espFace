import 'dart:convert';
import 'dart:io';

/// Result of a user-triggered GitHub "latest release" lookup for the device's `repo`.
class ReleaseInfo {
  const ReleaseInfo({required this.tag, this.name, this.binUrl, this.htmlUrl});
  final String tag;
  final String? name;
  final String? binUrl;
  final String? htmlUrl;

  /// True when `tag` looks newer than `fw` (numeric dotted compare, leading "v" ignored).
  bool isNewerThan(String? fw) {
    if (fw == null || fw.isEmpty) return true;
    final a = _parts(tag), b = _parts(fw);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  static List<int> _parts(String v) => RegExp(r'\d+').allMatches(v.split('-').first).map((m) => int.parse(m[0]!)).toList();

  static ReleaseInfo? fromJson(dynamic j) {
    if (j is! Map || j['tag_name'] is! String) return null;
    String? bin;
    if (j['assets'] is List) {
      for (final a in j['assets'] as List) {
        if (a is Map && a['name'] is String && (a['name'] as String).endsWith('.bin') && a['browser_download_url'] is String) {
          bin = a['browser_download_url'] as String;
          break;
        }
      }
    }
    return ReleaseInfo(tag: j['tag_name'] as String, name: j['name'] is String ? j['name'] as String : null, binUrl: bin, htmlUrl: j['html_url'] is String ? j['html_url'] as String : null);
  }
}

/// Only runs when the user taps "Check" and the setting is on; the app never calls out on its own.
Future<ReleaseInfo?> fetchLatestRelease(String repo, {HttpClient? client}) async {
  if (!RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repo)) return null;
  final c = client ?? HttpClient();
  try {
    final req = await c.getUrl(Uri.parse('https://api.github.com/repos/$repo/releases/latest'));
    req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    req.headers.set(HttpHeaders.userAgentHeader, 'espface-app');
    final res = await req.close().timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    return ReleaseInfo.fromJson(jsonDecode(await res.transform(utf8.decoder).join()));
  } finally {
    if (client == null) c.close(force: true);
  }
}
