import 'dart:convert';

class Utils {
  static List<T> toList<T>(String value, T Function(Map<String, dynamic> map) f) =>
      (formatJson(value) as List).map((e) => f(e)).toList();

  static T toObj<T>(String value, T Function(Map<String, dynamic> map) f) => f(formatJson(value));

  static List<dynamic> toListMap(String value) => formatJson(value);

  static dynamic formatJson(String value) => jsonDecode(value);

  static String checkOperationID(String? obj) => obj ?? DateTime.now().millisecondsSinceEpoch.toString();

  static Map<String, dynamic> cleanMap(Map<String, dynamic> map) {
    // Copy first — the input may be an unmodifiable map literal; also recurse
    // into nested maps with fresh copies so removeWhere never mutates a
    // caller-owned (or unmodifiable) structure.
    return Map<String, dynamic>.from(map)
      ..removeWhere((key, value) {
        if (value is Map<String, dynamic>) {
          final nested = Map<String, dynamic>.from(value);
          cleanMap(nested);
          if (nested.length != (value as Map).length) {
            map[key] = nested;
          }
        }
        return value == null;
      });
  }
}
