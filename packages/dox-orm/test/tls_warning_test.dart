import 'package:dox_orm/dox_orm.dart';
import 'package:test/test.dart';

void main() {
  test('postgres require prints one warning, other modes print none', () {
    expect(warnUnverifiedPostgresTls('verify-full'), isFalse);
    expect(warnUnverifiedPostgresTls('disable'), isFalse);
    expect(warnUnverifiedPostgresTls('require'), isTrue);
    expect(warnUnverifiedPostgresTls('require'), isFalse);
  });
}
