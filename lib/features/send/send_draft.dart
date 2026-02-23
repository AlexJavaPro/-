import '../photos/photo_model.dart';

class SendDraft {
  const SendDraft({
    required this.photos,
    required this.subject,
    required this.senderEmail,
    required this.recipientEmail,
    required this.savedAtMillis,
  });

  final List<PhotoDescriptor> photos;
  final String subject;
  final String senderEmail;
  final String recipientEmail;
  final int savedAtMillis;

  bool get hasContent {
    return photos.isNotEmpty ||
        subject.trim().isNotEmpty ||
        senderEmail.trim().isNotEmpty ||
        recipientEmail.trim().isNotEmpty;
  }

  factory SendDraft.fromMap(Map<String, dynamic> map) {
    final rawPhotos = (map['photos'] as List?) ?? const [];
    return SendDraft(
      photos: rawPhotos
          .whereType<Map>()
          .map((item) =>
              PhotoDescriptor.fromMap(Map<String, dynamic>.from(item)))
          .toList(growable: false),
      subject: map['subject'] as String? ?? '',
      senderEmail: map['senderEmail'] as String? ?? '',
      recipientEmail: map['recipientEmail'] as String? ?? '',
      savedAtMillis: _toInt(map['savedAtMillis']),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'photos': photos.map((item) => item.toMap()).toList(growable: false),
      'subject': subject,
      'senderEmail': senderEmail,
      'recipientEmail': recipientEmail,
      'savedAtMillis': savedAtMillis,
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
}
