import 'package:Pilipili/utils/path_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'renamed Windows product keeps the established accounts and settings root',
    () {
      final company = p.join('user-data', 'com.example');
      final old = p.join(company, 'piliplus');
      expect(
        PathUtils.applicationSupportPath(
          p.join(company, 'Pilipili'),
          windows: true,
        ),
        old,
      );
      expect(PathUtils.applicationSupportPath(old, windows: true), old);
    },
  );

  test('other platforms keep their provider directory', () {
    final directory = p.join('user-data', 'Pilipili');
    expect(
      PathUtils.applicationSupportPath(directory, windows: false),
      directory,
    );
  });
}
