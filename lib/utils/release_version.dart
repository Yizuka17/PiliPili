/// App versions compare numeric build numbers after semantic version fields.
/// Android's commit-hash suffix identifies a build, rather than a prerelease.
class ReleaseVersion implements Comparable<ReleaseVersion> {
  const ReleaseVersion(
    this.major,
    this.minor,
    this.patch,
    this.build,
    this.pre,
  );
  final int major, minor, patch, build;
  final String pre;
  static final _pattern = RegExp(
    r'(?:^|[^\d.])(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+(\d+))?',
  );

  static ReleaseVersion? parse(String value, {int build = 0}) {
    final match = _pattern.firstMatch(value);
    if (match == null) return null;
    var pre = match[4] ?? '';
    if (RegExp(r'^[0-9a-f]{7,40}$', caseSensitive: false).hasMatch(pre)) {
      pre = '';
    }
    return ReleaseVersion(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
      match[5] == null ? build : int.parse(match[5]!),
      pre,
    );
  }

  @override
  int compareTo(ReleaseVersion other) {
    for (final pair in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      final difference = pair.$1.compareTo(pair.$2);
      if (difference != 0) return difference;
    }
    if (pre != other.pre) {
      if (pre.isEmpty) return 1;
      if (other.pre.isEmpty) return -1;
      final a = pre.split('.'), b = other.pre.split('.');
      for (var i = 0; i < a.length && i < b.length; i++) {
        if (a[i] == b[i]) continue;
        final an = int.tryParse(a[i]), bn = int.tryParse(b[i]);
        if (an != null && bn != null) return an.compareTo(bn);
        if (an != null) return -1;
        if (bn != null) return 1;
        return a[i].compareTo(b[i]);
      }
      final length = a.length.compareTo(b.length);
      if (length != 0) return length;
    }
    return build.compareTo(other.build);
  }

  static ReleaseVersion? fromRelease(Map release) {
    // Some release tags omit +build while names and package names include it.
    final tag = parse(release['tag_name']?.toString() ?? '');
    ReleaseVersion? result = tag;
    final sources = [
      release['name']?.toString() ?? '',
      for (final asset in release['assets'] as List? ?? const [])
        if (asset is Map) asset['name']?.toString() ?? '',
    ];
    for (final source in sources) {
      final candidate = parse(source);
      if (candidate == null) continue;
      if (tag != null &&
          (candidate.major != tag.major ||
              candidate.minor != tag.minor ||
              candidate.patch != tag.patch ||
              candidate.pre != tag.pre)) {
        continue;
      }
      if (result == null || candidate.compareTo(result) > 0) result = candidate;
    }
    return result;
  }

  static Map<String, dynamic>? latestRelease(
    List releases, {
    bool includePrerelease = false,
  }) {
    Map<String, dynamic>? latest;
    ReleaseVersion? latestVersion;
    for (final item in releases) {
      if (item is! Map ||
          item['draft'] == true ||
          (!includePrerelease && item['prerelease'] == true)) {
        continue;
      }
      final version = fromRelease(item);
      if (version == null || (!includePrerelease && version.pre.isNotEmpty)) {
        continue;
      }
      if (latestVersion == null || version.compareTo(latestVersion) > 0) {
        latestVersion = version;
        latest = Map<String, dynamic>.from(item);
      }
    }
    return latest;
  }
}
