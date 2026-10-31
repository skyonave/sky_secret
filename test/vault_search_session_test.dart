import 'package:flutter_test/flutter_test.dart';
import 'package:skysecret/core/desktop/search/controllers/search_session.dart';

void main() {
  test('query filters the active vault and empty input restores it', () {
    var unlocked = true;
    var activities = 0;
    final queries = <String>[];
    final session = VaultSearchSession(
      isValid: () => unlocked,
      onQueryChanged: queries.add,
      activity: () => activities++,
    );
    expect(session.search('first'), isTrue);
    expect(session.search('second'), isTrue);
    expect(session.search(''), isTrue);
    expect(queries, ['first', 'second', '']);
    unlocked = false;
    expect(session.search('fourth'), isFalse);
    expect(queries, ['first', 'second', '']);
    expect(activities, 3);
  });

  test('closed search stays revoked after unlock and rejects excessive input', () {
    var unlocked = true;
    final queries = <String>[];
    final session = VaultSearchSession(isValid: () => unlocked, onQueryChanged: queries.add, activity: () {});
    expect(session.search('x' * 257), isFalse);
    expect(queries, isEmpty);
    expect(session.search('x' * 256), isTrue);
    session.close();
    unlocked = false;
    unlocked = true;
    expect(session.search('x'), isFalse);
    expect(queries, ['x' * 256]);
  });
}
