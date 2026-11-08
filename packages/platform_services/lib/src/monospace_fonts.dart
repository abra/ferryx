import 'package:flutter/services.dart';

/// Family names (not individual faces) understood by the system font resolver.
Future<List<String>> readMonospaceFontFamilies(MethodChannel channel) async {
  final values = await channel.invokeListMethod<String>(
    'fonts.monospaceFamilies',
  );
  if (values == null) {
    throw PlatformException(
      code: 'font_catalog_unavailable',
      message: 'The platform did not return its font families.',
    );
  }
  final families =
      {
        for (final value in values)
          if (value.trim().isNotEmpty) value.trim(),
      }.toList()..sort((a, b) {
        final order = a.toLowerCase().compareTo(b.toLowerCase());
        return order == 0 ? a.compareTo(b) : order;
      });
  return List.unmodifiable(families);
}
