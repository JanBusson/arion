final class ApiBaseUrl {
  ApiBaseUrl._(this.uri);

  final Uri uri;

  static ApiBaseUrl parse(String input) {
    final value = input.trim();
    final parsed = Uri.tryParse(value);
    if (parsed == null ||
        !parsed.isAbsolute ||
        (parsed.scheme != 'http' && parsed.scheme != 'https') ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment) {
      throw const FormatException(
        'Enter an absolute HTTP or HTTPS address without a query or fragment.',
      );
    }

    var path = parsed.path;
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path == '/') {
      path = '';
    }
    return ApiBaseUrl._(parsed.replace(path: path));
  }

  Uri endpoint(String path) {
    final relativePath = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$uri/').resolve(relativePath);
  }

  @override
  String toString() => uri.toString();
}
