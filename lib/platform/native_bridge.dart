import 'package:flutter/services.dart';

import '../core/constants.dart';
import '../features/photos/photo_model.dart';
import 'native_contract.dart';

enum PhotoPickSource {
  auto,
  gallery,
  files,
}

String _photoPickSourceId(PhotoPickSource source) {
  switch (source) {
    case PhotoPickSource.auto:
      return 'auto';
    case PhotoPickSource.gallery:
      return 'gallery';
    case PhotoPickSource.files:
      return 'files';
  }
}

class NativeBridge {
  const NativeBridge();

  static const MethodChannel _channel = MethodChannel(
    AppConstants.nativeChannelName,
  );

  Future<List<PhotoDescriptor>> pickPhotos({
    PhotoPickSource source = PhotoPickSource.auto,
  }) async {
    final raw = await _channel.invokeMethod<List<dynamic>>(
      NativeContract.pickPhotos,
      <String, dynamic>{
        'source': _photoPickSourceId(source),
      },
    );
    if (raw == null) {
      return const [];
    }
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map((item) => PhotoDescriptor.fromMap(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<void> saveAppPattern(String pattern) {
    return _channel.invokeMethod<void>(
      NativeContract.saveAppPattern,
      <String, dynamic>{'pattern': pattern},
    );
  }

  Future<bool> verifyAppPattern(String pattern) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      NativeContract.verifyAppPattern,
      <String, dynamic>{'pattern': pattern},
    );
    if (raw == null) {
      return false;
    }
    return Map<String, dynamic>.from(raw)['valid'] == true;
  }

  Future<bool> hasAppPattern() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      NativeContract.hasAppPattern,
    );
    if (raw == null) {
      return false;
    }
    return Map<String, dynamic>.from(raw)['hasPattern'] == true;
  }

  Future<void> clearAppPattern() {
    return _channel.invokeMethod<void>(NativeContract.clearAppPattern);
  }

  Future<void> openExternalEmail({
    required List<PhotoDescriptor> photos,
    required String subject,
    String recipientEmail = '',
    String body = '',
    String chooserTitle = 'Выберите почтовое приложение',
    String targetPackage = '',
  }) {
    return _channel.invokeMethod<void>(
      NativeContract.openExternalEmail,
      <String, dynamic>{
        'recipientEmail': recipientEmail,
        'subject': subject,
        'body': body,
        'chooserTitle': chooserTitle,
        'targetPackage': targetPackage,
        'photos': photos.map((item) => item.toMap()).toList(growable: false),
      },
    );
  }

  Future<YandexAuthState> getYandexAuthState() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      NativeContract.getYandexAuthState,
    );
    final mapped = raw == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(raw);
    return YandexAuthState.fromMap(mapped);
  }

  Future<YandexAuthState> startYandexLogin() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      NativeContract.startYandexLogin,
    );
    final mapped = raw == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(raw);
    return YandexAuthState.fromMap(mapped);
  }

  Future<void> logoutYandex() {
    return _channel.invokeMethod<void>(NativeContract.logoutYandex);
  }

  Future<AccessibilityState> getAccessibilityState() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      NativeContract.getAccessibilityState,
    );
    final mapped = raw == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(raw);
    return AccessibilityState.fromMap(mapped);
  }

  Future<void> openAccessibilitySettings() {
    return _channel
        .invokeMethod<void>(NativeContract.openAccessibilitySettings);
  }

  Future<ShareAutomationState> startShareAutomationSeries({
    required String recipientEmail,
    required String subjectInput,
    required int limitBytes,
    required List<PhotoDescriptor> photos,
  }) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      NativeContract.startShareAutomationSeries,
      <String, dynamic>{
        'recipientEmail': recipientEmail,
        'subjectInput': subjectInput,
        'limitBytes': limitBytes,
        'photos': photos.map((item) => item.toMap()).toList(growable: false),
      },
    );
    final mapped = raw == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(raw);
    return ShareAutomationState.fromMap(mapped);
  }

  Future<ShareAutomationState> getShareAutomationState() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      NativeContract.getShareAutomationState,
    );
    final mapped = raw == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(raw);
    return ShareAutomationState.fromMap(mapped);
  }

  Future<ShareAutomationState> resumeShareAutomation() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      NativeContract.resumeShareAutomation,
    );
    final mapped = raw == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(raw);
    return ShareAutomationState.fromMap(mapped);
  }

  Future<ShareAutomationState> cancelShareAutomation() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      NativeContract.cancelShareAutomation,
    );
    final mapped = raw == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(raw);
    return ShareAutomationState.fromMap(mapped);
  }

  Future<ShareAutomationState> openCurrentShareBatchManually() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      NativeContract.openCurrentShareBatchManually,
    );
    final mapped = raw == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(raw);
    return ShareAutomationState.fromMap(mapped);
  }

  Future<String> enqueueSendJob({
    required String recipientEmail,
    required String subjectInput,
    required int limitBytes,
    required String compressionPreset,
    required List<PhotoDescriptor> photos,
  }) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      NativeContract.enqueueSendJob,
      <String, dynamic>{
        'recipientEmail': recipientEmail,
        'subjectInput': subjectInput,
        'limitBytes': limitBytes,
        'compressionPreset': compressionPreset,
        'photos': photos.map((item) => item.toMap()).toList(growable: false),
      },
    );
    final mapped = raw == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(raw);
    final jobId = mapped['jobId'] as String?;
    if (jobId == null || jobId.isEmpty) {
      throw StateError('Нативный слой не вернул jobId');
    }
    return jobId;
  }

  Future<JobStatus> getJobStatus(String jobId) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      NativeContract.getJobStatus,
      <String, dynamic>{'jobId': jobId},
    );
    if (raw == null) {
      throw StateError('Статус задачи недоступен для $jobId');
    }
    return JobStatus.fromMap(Map<String, dynamic>.from(raw));
  }

  Future<List<LogEntry>> getJobLogs(
    String jobId, {
    int? afterId,
  }) async {
    final raw = await _channel.invokeMethod<List<dynamic>>(
      NativeContract.getJobLogs,
      <String, dynamic>{
        'jobId': jobId,
        'afterId': afterId,
      },
    );
    if (raw == null) {
      return const [];
    }
    return raw
        .whereType<Map<dynamic, dynamic>>()
        .map((item) => LogEntry.fromMap(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Future<JobStatus> cancelSendJob(String jobId) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      NativeContract.cancelSendJob,
      <String, dynamic>{'jobId': jobId},
    );
    if (raw == null) {
      throw StateError('Не удалось отменить задачу $jobId');
    }
    return JobStatus.fromMap(Map<String, dynamic>.from(raw));
  }

  Future<JobStatus?> getLatestJobStatus() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      NativeContract.getLatestJobStatus,
    );
    if (raw == null) {
      return null;
    }
    final mapped = Map<String, dynamic>.from(raw);
    if ((mapped['jobId'] as String?)?.isEmpty ?? true) {
      return null;
    }
    return JobStatus.fromMap(mapped);
  }

  Future<SmtpSelfTestResult> saveAndRunSmtpSelfTest({
    String? appPassword,
  }) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      NativeContract.saveAndRunSmtpSelfTest,
      <String, dynamic>{
        if (appPassword != null) 'appPassword': appPassword,
      },
    );
    if (raw == null) {
      return const SmtpSelfTestResult.empty();
    }
    return SmtpSelfTestResult.fromMap(Map<String, dynamic>.from(raw));
  }

  Future<void> runSmtpSelfTest({
    required String recipientEmail,
  }) {
    return _channel.invokeMethod<void>(
      NativeContract.runSmtpSelfTest,
      <String, dynamic>{
        'recipientEmail': recipientEmail,
      },
    );
  }

  Future<void> saveSmtpAppPassword(String password) {
    return _channel.invokeMethod<void>(
      NativeContract.saveSmtpAppPassword,
      <String, dynamic>{'password': password},
    );
  }

  Future<bool> hasSmtpAppPassword() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      NativeContract.hasSmtpAppPassword,
    );
    if (raw == null) {
      return false;
    }
    return Map<String, dynamic>.from(raw)['hasPassword'] == true;
  }

  Future<void> clearSmtpAppPassword() {
    return _channel.invokeMethod<void>(NativeContract.clearSmtpAppPassword);
  }
}
