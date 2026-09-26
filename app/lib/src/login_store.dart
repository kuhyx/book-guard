import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The public dufs URL the phone uploads to (same host every kuhy app uses).
const kDefaultDufsUrl = 'https://kuhy-cloud.duckdns.org';

/// The dufs login `add_dufs_login.sh bookguard /Reading rw` creates.
const kDefaultDufsUser = 'bookguard';

/// Where the desktop wrapper proxies WebDAV; same origin, no credentials.
const kWrapperDavPath = '/dav';

/// A dufs login: where, and as whom.
@immutable
class DufsLogin {
  /// Creates a login.
  const new({required this.url, required this.user, required this.password});

  /// Share root without a trailing slash.
  final String url;

  /// dufs user.
  final String user;

  /// dufs password.
  final String password;

  /// Whether every field is filled in.
  bool get complete => url.isNotEmpty && user.isNotEmpty && password.isNotEmpty;
}

/// Keeps the phone's dufs login in the OS keystore.
///
/// Never used by the desktop web build: there the wrapper holds the login
/// and the browser never sees it (a browser has no real keystore).
class LoginStore {
  /// Creates a store over [storage].
  new({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _urlKey = 'dufs_url';
  static const _userKey = 'dufs_user';
  static const _passwordKey = 'dufs_password';

  /// The saved login, with defaults for anything never saved.
  Future<DufsLogin> load() async => DufsLogin(
    url: await _storage.read(key: _urlKey) ?? kDefaultDufsUrl,
    user: await _storage.read(key: _userKey) ?? kDefaultDufsUser,
    password: await _storage.read(key: _passwordKey) ?? '',
  );

  /// Saves [login].
  Future<void> save(DufsLogin login) async {
    await _storage.write(key: _urlKey, value: login.url.trim());
    await _storage.write(key: _userKey, value: login.user.trim());
    await _storage.write(key: _passwordKey, value: login.password.trim());
  }
}
