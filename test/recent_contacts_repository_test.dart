import 'package:flutter_test/flutter_test.dart';
import 'package:photomailer/features/contacts/recent_contacts_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late RecentContactsRepository repository;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    repository = const RecentContactsRepository();
  });

  test('rememberRecipient keeps most recent first and limits to five', () async {
    await repository.rememberRecipient('one@example.com');
    await repository.rememberRecipient('two@example.com');
    await repository.rememberRecipient('three@example.com');
    await repository.rememberRecipient('four@example.com');
    await repository.rememberRecipient('five@example.com');
    final result = await repository.rememberRecipient('six@example.com');

    expect(
      result,
      const <String>[
        'six@example.com',
        'five@example.com',
        'four@example.com',
        'three@example.com',
        'two@example.com',
      ],
    );
  });

  test('rememberRecipient deduplicates and normalizes case', () async {
    await repository.rememberRecipient('USER@Example.COM');
    final result = await repository.rememberRecipient('user@example.com');

    expect(result, const <String>['user@example.com']);
  });
}
