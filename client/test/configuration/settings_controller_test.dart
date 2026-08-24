import 'package:arion_client/configuration/api_base_url.dart';
import 'package:arion_client/configuration/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';

void main() {
  test('accepts and normalizes absolute HTTP and HTTPS URLs', () {
    expect(
      ApiBaseUrl.parse(' http://arion.test:8000/ ').toString(),
      'http://arion.test:8000',
    );
    expect(
      ApiBaseUrl.parse('https://arion.test/api///').toString(),
      'https://arion.test/api',
    );
  });

  test('rejects relative and unsupported URLs', () {
    expect(() => ApiBaseUrl.parse('/api'), throwsFormatException);
    expect(() => ApiBaseUrl.parse('ftp://arion.test'), throwsFormatException);
    expect(
      () => ApiBaseUrl.parse('http://arion.test?q=1'),
      throwsFormatException,
    );
  });

  test('saved value takes precedence over Dart definition seed', () async {
    final store = FakeSettingsStore(value: 'http://saved.test:8000/');
    final controller = SettingsController(
      store,
      seedBaseUrl: 'https://seed.test',
    );

    await controller.load();

    expect(controller.baseUrl.toString(), 'http://saved.test:8000');
  });

  test('seed is used when no saved value exists', () async {
    final controller = SettingsController(
      FakeSettingsStore(),
      seedBaseUrl: 'https://seed.test/',
    );

    await controller.load();

    expect(controller.baseUrl.toString(), 'https://seed.test');
  });

  test('invalid input leaves saved configuration unchanged', () async {
    final store = FakeSettingsStore(value: 'http://saved.test');
    final controller = SettingsController(store);
    await controller.load();

    expect(await controller.save('not a URL'), isFalse);
    expect(store.value, 'http://saved.test');
    expect(controller.error, isNotNull);
  });

  test('saved normalized value reloads asynchronously', () async {
    final store = FakeSettingsStore();
    final first = SettingsController(store);

    expect(await first.save('https://arion.test/'), isTrue);
    final reloaded = SettingsController(store);
    await reloaded.load();

    expect(store.value, 'https://arion.test');
    expect(reloaded.baseUrl.toString(), 'https://arion.test');
  });
}
