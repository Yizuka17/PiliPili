import 'package:Pilipili/utils/release_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  int compare(String a, String b) =>
      ReleaseVersion.parse(a)!.compareTo(ReleaseVersion.parse(b)!);
  test(
    'compares numeric versions and builds rather than timestamps or strings',
    () {
      expect(compare('v2.1.10+1', '2.1.9+9999'), greaterThan(0));
      expect(compare('2.1.5+5447', '2.1.5+5446'), greaterThan(0));
      expect(compare('2.1.4+9999', '2.1.5+1'), lessThan(0));
      expect(ReleaseVersion.parse('SNAPSHOT'), isNull);
    },
  );
  test('handles Android commit suffix and semantic prereleases', () {
    final android = ReleaseVersion.parse('2.1.5-e445c9adb', build: 5446)!;
    expect(android.compareTo(ReleaseVersion.parse('2.1.5+5446')!), 0);
    expect(compare('2.1.6', '2.1.6-rc.10'), greaterThan(0));
    expect(compare('2.1.6-rc.10', '2.1.6-rc.9'), greaterThan(0));
  });
  test('reads omitted build from release name or matching package name', () {
    expect(
      ReleaseVersion.fromRelease({
        'tag_name': 'v2.1.5',
        'name': 'Pilipili 2.1.5+5446',
      })!.build,
      5446,
    );
    expect(
      ReleaseVersion.fromRelease({
        'tag_name': 'v2.1.5',
        'assets': [
          {'name': 'Pilipili_windows_2.1.5+5447_x64_setup.exe'},
          {'name': 'Pilipili_windows_2.2.0+6000_x64_setup.exe'},
        ],
      })!.build,
      5447,
    );
  });
  test('chooses highest version across unsorted releases and skips drafts and beta', () {
    final releases = [
      {'tag_name': 'v2.1.4', 'created_at': '2099-01-01'},
      {'tag_name': 'v2.1.6', 'name': 'Pilipili 2.1.6+5447'},
      {'tag_name': 'v2.1.7', 'draft': true},
      {'tag_name': 'v2.2.0-beta.1', 'prerelease': true},
      {'tag_name': 'release18', 'name': 'invalid'},
    ];
    expect(ReleaseVersion.latestRelease(releases)!['tag_name'], 'v2.1.6');
    expect(
      ReleaseVersion.latestRelease(
        releases,
        includePrerelease: true,
      )!['tag_name'],
      'v2.2.0-beta.1',
    );
  });
}
