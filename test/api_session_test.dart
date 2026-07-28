import 'package:BoltStar/src/network/api_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('persists and restores userToken and jwtToken together', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final session = ApiSession.instance;
    session.clear();
    await session.restore();

    session.setTokens(
      userToken: 'flutter-user-token',
      jwtToken: 'flutter-jwt-token',
    );

    expect(session.isLoggedIn, isTrue);
    expect(session.userToken, 'flutter-user-token');
    expect(session.jwtToken, 'flutter-jwt-token');

    expect(await session.restore(), isTrue);
    expect(session.userToken, 'flutter-user-token');
    expect(session.jwtToken, 'flutter-jwt-token');
  });

  test('rejects a legacy session that has no jwtToken', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'boltstar.userToken': 'legacy-user-token',
    });
    final session = ApiSession.instance;

    expect(await session.restore(), isFalse);
    expect(session.isLoggedIn, isFalse);
    expect(session.userToken, isEmpty);
    expect(session.jwtToken, isEmpty);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('boltstar.userToken'), isFalse);
  });
}
