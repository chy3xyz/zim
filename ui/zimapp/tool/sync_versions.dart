// Sync versions from versions.yaml into subpackage pubspec.yaml files.
// Dependency-free parser for simple `key: value` lines.
import 'dart:io';

const List<String> packages = <String>[
  '.', // root project
  'openim_common',
  'openim_organization',
  'openim_working_circle',
];

void main() {
  final String root = Directory.current.path;
  final File versionsFile = File('$root/versions.yaml');
  if (!versionsFile.existsSync()) {
    stderr.writeln('versions.yaml not found at $root');
    exit(1);
  }

  final Map<String, String> versions = _parseSimpleYaml(versionsFile.readAsLinesSync());
  if (versions.isEmpty) {
    stderr.writeln('versions.yaml is empty or invalid.');
    exit(1);
  }

  for (final String pkg in packages) {
    final String dir = pkg == '.' ? root : '$root/$pkg';
    final File pubspec = File('$dir/pubspec.yaml');
    if (!pubspec.existsSync()) {
      stdout.writeln('Skip $pkg: pubspec.yaml not found');
      continue;
    }
    final List<String> lines = pubspec.readAsLinesSync();
    final bool changed = _syncFile(lines, versions);
    if (changed) {
      pubspec.writeAsStringSync(lines.join('\n'));
      stdout.writeln('Updated $pkg/pubspec.yaml');
    } else {
      stdout.writeln('No changes for $pkg/pubspec.yaml');
    }
  }
}

Map<String, String> _parseSimpleYaml(List<String> lines) {
  final Map<String, String> map = <String, String>{};
  for (int i = 0; i < lines.length; i++) {
    final String raw = lines[i];
    final String line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;

    final int idx = line.indexOf(':');
    if (idx <= 0) continue;

    final String key = line.substring(0, idx).trim();
    String value = line.substring(idx + 1).trim();

    // If value is empty, it might be a multi-line value (e.g. git dependency)
    if (value.isEmpty) {
      final StringBuffer buffer = StringBuffer();
      // Look ahead for indented lines
      int j = i + 1;
      while (j < lines.length) {
        final String nextRaw = lines[j];
        if (nextRaw.trim().isEmpty) {
          j++;
          continue;
        }
        // Check indentation: must be greater than current line's indentation
        // Simple check: starts with space
        if (!nextRaw.startsWith(' ')) {
          break;
        }
        buffer.writeln(nextRaw);
        j++;
      }
      if (buffer.isNotEmpty) {
        value = '\n${buffer.toString().trimRight()}';
        i = j - 1; // Advance outer loop
      }
    }

    if (key.isNotEmpty) {
      map[key] = value;
    }
  }
  return map;
}

bool _syncFile(List<String> lines, Map<String, String> versions) {
  bool changed = false;
  final Set<String> keys = versions.keys.toSet();

  for (int i = 0; i < lines.length; i++) {
    final String original = lines[i];
    // Capture leading indentation
    int j = 0;
    while (j < original.length && (original[j] == ' ' || original[j] == '\t')) {
      j++;
    }
    final String indent = original.substring(0, j);
    final String rest = original.substring(j);

    // Skip comments or empty lines
    if (rest.startsWith('#') || rest.trim().isEmpty) continue;

    final int colon = rest.indexOf(':');
    if (colon <= 0) continue;

    final String name = rest.substring(0, colon).trim();
    if (!keys.contains(name)) continue;

    final String newVersion = versions[name]!;
    String replacement;

    if (newVersion.contains('\n')) {
      // Multi-line replacement with indentation aligned to the current level.
      final List<String> parts = newVersion.split('\n');
      int baseIndent = -1;
      for (final String part in parts.skip(1)) {
        if (part.trim().isEmpty) continue;
        final int spaces = _leadingSpaces(part);
        if (baseIndent == -1 || spaces < baseIndent) {
          baseIndent = spaces;
        }
      }
      if (baseIndent < 0) baseIndent = 0;

      final StringBuffer adjusted = StringBuffer();
      for (int idx = 0; idx < parts.length; idx++) {
        final String line = parts[idx];
        if (idx == 0) {
          adjusted.write(line);
          continue;
        }
        if (line.trim().isEmpty) {
          adjusted.writeln();
          continue;
        }
        final int relativeIndent = _leadingSpaces(line) - baseIndent;
        final String childIndent = '$indent  ${' ' * (relativeIndent < 0 ? 0 : relativeIndent)}';
        adjusted.write('\n$childIndent${line.trimLeft()}');
      }
      replacement = '$indent$name:${adjusted.toString()}';
    } else {
      // Single-line replacement
      replacement = '$indent$name: $newVersion';
    }

    // Check if we need to update
    // We also need to check if the CURRENT entry in pubspec is multi-line and remove those lines

    // Check if current line matches replacement (only for single line check, multi-line is harder)
    if (original.trim() != replacement.trim() || newVersion.contains('\n')) {
      // If we are here, we might need to replace.
      // First, let's see if the current entry has multi-line children we need to remove.
      int k = i + 1;
      while (k < lines.length) {
        final String nextLine = lines[k];
        if (nextLine.trim().isEmpty) {
          k++;
          continue;
        }
        int nextIndent = 0;
        while (nextIndent < nextLine.length && (nextLine[nextIndent] == ' ' || nextLine[nextIndent] == '\t')) {
          nextIndent++;
        }
        final String trimmedNext = nextLine.trimLeft();
        final bool forceChild = newVersion.contains('\n') &&
            RegExp(r'^(git|hosted|path|url|ref|branch):').hasMatch(trimmedNext);

        if (nextIndent > j || forceChild) {
          k++;
        } else {
          break;
        }
      }

      // Construct the new block
      // If we are replacing, we should check if the content is actually different to avoid "Updated" message if not needed.
      // But for simplicity and correctness with multi-line, let's reconstruct and compare.

      // Extract current full block
      final StringBuffer currentBlock = StringBuffer();
      currentBlock.write(original);
      for (int m = i + 1; m < k; m++) {
        currentBlock.writeln();
        currentBlock.write(lines[m]);
      }

      if (currentBlock.toString().trim() != replacement.trim()) {
        // Perform replacement
        lines[i] = replacement;
        // Remove subsequent lines that were part of the old block
        if (k > i + 1) {
          lines.removeRange(i + 1, k);
        }
        changed = true;
      }
    }
  }
  return changed;
}

int _leadingSpaces(String line) {
  int count = 0;
  while (count < line.length && line[count] == ' ') {
    count++;
  }
  return count;
}
