import 'package:book_guard_app/src/login_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an empty keystore loads the defaults with no password', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final login = await LoginStore().load();
    expect(login.url, kDefaultDufsUrl);
    expect(login.user, kDefaultDufsUser);
    expect(login.password, '');
    expect(login.complete, isFalse);
  });

  test('save trims and load reads it back', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = LoginStore(storage: const FlutterSecureStorage());
    await store.save(
      const DufsLogin(url: ' https://h ', user: ' u ', password: ' p\n'),
    );
    final login = await store.load();
    expect([login.url, login.user, login.password], ['https://h', 'u', 'p']);
    expect(login.complete, isTrue);
  });

  test('complete needs every field', () {
    String blank() => '';
    expect(DufsLogin(url: blank(), user: 'u', password: 'p').complete, isFalse);
    expect(DufsLogin(url: 'x', user: blank(), password: 'p').complete, isFalse);
    expect(kWrapperDavPath, '/dav');
  });
}
