import 'dart:typed_data';

class PhotoDescriptor {
  const PhotoDescriptor({
    required this.uri,
    required this.name,
    required this.sizeBytes,
    required this.mimeType,
    this.thumbnailBytes,
    this.capturedAtMillis,
  });

  final String uri;
  final String name;
  final int sizeBytes;
  final String? mimeType;
  final Uint8List? thumbnailBytes;
  final int? capturedAtMillis;

  String get duplicateFingerprint {
    final normalizedName = name.trim().toLowerCase();
    return '$normalizedName|$sizeBytes';
  }

  factory PhotoDescriptor.fromMap(Map<String, dynamic> map) {
    return PhotoDescriptor(
      uri: map['uri'] as String? ?? '',
      name: map['name'] as String? ?? 'file',
      sizeBytes: _toInt(map['sizeBytes']),
      mimeType: map['mimeType'] as String?,
      thumbnailBytes: _readBytes(map['thumbnailBytes']),
      capturedAtMillis: _toNullableInt(map['capturedAtMillis']),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'uri': uri,
      'name': name,
      'sizeBytes': sizeBytes,
      'mimeType': mimeType,
      'capturedAtMillis': capturedAtMillis,
    };
  }

  static int _toInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  static int? _toNullableInt(dynamic value) {
    if (value == null) {
      return null;
    }
    final parsed = _toInt(value);
    return parsed <= 0 ? null : parsed;
  }

  static Uint8List? _readBytes(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Uint8List) {
      return value;
    }
    if (value is List<int>) {
      return Uint8List.fromList(value);
    }
    if (value is List) {
      final bytes = value.whereType<int>().toList(growable: false);
      if (bytes.isEmpty) {
        return null;
      }
      return Uint8List.fromList(bytes);
    }
    return null;
  }
}
