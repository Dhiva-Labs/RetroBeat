/// Everything `WebDavClient` throws.
///
/// The five subtypes exist because the UI has five different things to say:
/// fix your password, that file is gone, something is already there, the
/// network is down, and the server is behaving oddly. Catching the base type
/// and printing [message] is always safe — no message ever contains a
/// password, because the client never puts one in a URL or a log.
library;

/// Base type for every WebDAV failure. Never thrown directly.
abstract class WebDavException implements Exception {
  const WebDavException(this.message, {this.statusCode, this.path});

  /// Safe to show the user verbatim.
  final String message;

  /// The HTTP status that produced this, when there was one.
  final int? statusCode;

  /// The remote path involved, when there was one.
  final String? path;

  String get _label => runtimeType.toString();

  @override
  String toString() {
    final where = path == null ? '' : ' ($path)';
    return '$_label: $message$where';
  }
}

/// 401/403 — wrong username or password, or the account cannot see that path.
class WebDavAuthException extends WebDavException {
  const WebDavAuthException(
    super.message, {
    super.statusCode,
    super.path,
  });
}

/// 404/410 — the path is not there. Also thrown when a listing of a parent
/// succeeds but the child has since gone.
class WebDavNotFoundException extends WebDavException {
  const WebDavNotFoundException(
    super.message, {
    super.statusCode,
    super.path,
  });
}

/// 405/409/412/423 — the operation collides with what is already on the
/// server: the name is taken, the parent folder is missing, a precondition
/// failed, or the resource is locked.
class WebDavConflictException extends WebDavException {
  const WebDavConflictException(
    super.message, {
    super.statusCode,
    super.path,
  });
}

/// The server was never reached: DNS, refused connection, TLS failure, or a
/// timeout. Distinct from [WebDavProtocolException] because retrying later is
/// the sensible response to this one and not to that one.
class WebDavNetworkException extends WebDavException {
  const WebDavNetworkException(super.message, {super.path});
}

/// The server answered, but not usefully: an unexpected status, or a body that
/// is not the WebDAV XML the request asked for.
class WebDavProtocolException extends WebDavException {
  const WebDavProtocolException(
    super.message, {
    super.statusCode,
    super.path,
  });
}
