import 'dart:convert';

import 'package:crypto/crypto.dart';

Uri normalizeResourceUri(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  final defaultPort =
      (scheme == 'http' && uri.port == 80) ||
      (scheme == 'https' && uri.port == 443);
  return Uri(
    scheme: scheme,
    userInfo: uri.userInfo,
    host: uri.host.toLowerCase(),
    port: uri.hasPort && !defaultPort ? uri.port : null,
    path: uri.path,
    query: uri.hasQuery ? uri.query : null,
  ).normalizePath();
}

String resourceKey(Uri uri) => sha256
    .convert(utf8.encode(normalizeResourceUri(uri).toString()))
    .toString();
