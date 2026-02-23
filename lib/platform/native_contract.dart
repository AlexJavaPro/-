class NativeContract {
  NativeContract._();

  static const String pickPhotos = 'pickPhotos';
  static const String saveAppPattern = 'saveAppPattern';
  static const String verifyAppPattern = 'verifyAppPattern';
  static const String hasAppPattern = 'hasAppPattern';
  static const String clearAppPattern = 'clearAppPattern';
  static const String openExternalEmail = 'openExternalEmail';
  static const String getYandexAuthState = 'getYandexAuthState';
  static const String startYandexLogin = 'startYandexLogin';
  static const String logoutYandex = 'logoutYandex';
  static const String getAccessibilityState = 'getAccessibilityState';
  static const String openAccessibilitySettings = 'openAccessibilitySettings';
  static const String startShareAutomationSeries = 'startShareAutomationSeries';
  static const String getShareAutomationState = 'getShareAutomationState';
  static const String resumeShareAutomation = 'resumeShareAutomation';
  static const String cancelShareAutomation = 'cancelShareAutomation';
  static const String openCurrentShareBatchManually =
      'openCurrentShareBatchManually';
  static const String enqueueSendJob = 'enqueueSendJob';
  static const String getJobStatus = 'getJobStatus';
  static const String getJobLogs = 'getJobLogs';
  static const String cancelSendJob = 'cancelSendJob';
  static const String getLatestJobStatus = 'getLatestJobStatus';
  static const String runSmtpSelfTest = 'runSmtpSelfTest';
  static const String saveAndRunSmtpSelfTest = 'saveAndRunSmtpSelfTest';
  static const String saveSmtpAppPassword = 'saveSmtpAppPassword';
  static const String hasSmtpAppPassword = 'hasSmtpAppPassword';
  static const String clearSmtpAppPassword = 'clearSmtpAppPassword';
}

int _toInt(dynamic value) {
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

class YandexAuthState {
  const YandexAuthState({
    required this.authorized,
    required this.email,
    required this.login,
    required this.userId,
    required this.identifier,
    required this.savedAtMillis,
    required this.smtpReady,
    required this.smtpIdentity,
  });

  const YandexAuthState.empty()
      : authorized = false,
        email = '',
        login = '',
        userId = '',
        identifier = '',
        savedAtMillis = 0,
        smtpReady = false,
        smtpIdentity = '';

  final bool authorized;
  final String email;
  final String login;
  final String userId;
  final String identifier;
  final int savedAtMillis;
  final bool smtpReady;
  final String smtpIdentity;

  String get displayName => email.trim().isNotEmpty ? email : identifier;

  YandexIdentity get yandexIdentity => YandexIdentity(
      id: userId,
      login: login,
      displayName: displayName,
      email: email.trim().isEmpty ? null : email.trim(),
    );

  SmtpIdentity get smtpIdentityState => SmtpIdentity(
      smtpUsernameEmail: smtpIdentity.trim(),
      ready: smtpReady,
      hasCredential: authorized,
      lastVerifiedAtMillis: savedAtMillis,
    );

  factory YandexAuthState.fromMap(Map<String, dynamic> map) {
    return YandexAuthState(
      authorized: map['authorized'] == true,
      email: map['email'] as String? ?? '',
      login: map['login'] as String? ?? '',
      userId: map['userId'] as String? ?? '',
      identifier: map['identifier'] as String? ?? '',
      savedAtMillis: _toInt(map['savedAtMillis']),
      smtpReady: map['smtpReady'] == true,
      smtpIdentity: map['smtpIdentity'] as String? ?? '',
    );
  }
}

class YandexIdentity {
  const YandexIdentity({
    required this.id,
    required this.login,
    required this.displayName,
    required this.email,
  });

  final String id;
  final String login;
  final String displayName;
  final String? email;
}

class SmtpIdentity {
  const SmtpIdentity({
    required this.smtpUsernameEmail,
    required this.ready,
    required this.hasCredential,
    this.lastVerifiedAtMillis,
  });

  final String smtpUsernameEmail;
  final bool ready;
  final bool hasCredential;
  final int? lastVerifiedAtMillis;
}

class AccessibilityState {
  const AccessibilityState({
    required this.enabled,
    required this.connected,
    required this.currentPackage,
    required this.inYandexMail,
    required this.lastSendClickAt,
  });

  const AccessibilityState.empty()
      : enabled = false,
        connected = false,
        currentPackage = '',
        inYandexMail = false,
        lastSendClickAt = 0;

  final bool enabled;
  final bool connected;
  final String currentPackage;
  final bool inYandexMail;
  final int lastSendClickAt;

  factory AccessibilityState.fromMap(Map<String, dynamic> map) {
    return AccessibilityState(
      enabled: map['enabled'] == true,
      connected: map['connected'] == true,
      currentPackage: map['currentPackage'] as String? ?? '',
      inYandexMail: map['inYandexMail'] == true,
      lastSendClickAt: _toInt(map['lastSendClickAt']),
    );
  }
}

enum ShareAutomationStatus {
  idle,
  precheck,
  openingBatch,
  awaitingSendButton,
  autoClickingSend,
  awaitingMailResult,
  nextBatchTransition,
  completed,
  pausedManualActionRequired,
  authReloginRequired,
  failed,
  cancelled,
}

ShareAutomationStatus shareAutomationStatusFromId(String id) {
  switch (id) {
    case 'precheck':
      return ShareAutomationStatus.precheck;
    case 'opening_batch':
      return ShareAutomationStatus.openingBatch;
    case 'awaiting_send_button':
      return ShareAutomationStatus.awaitingSendButton;
    case 'auto_clicking_send':
      return ShareAutomationStatus.autoClickingSend;
    case 'awaiting_mail_result':
      return ShareAutomationStatus.awaitingMailResult;
    case 'next_batch_transition':
      return ShareAutomationStatus.nextBatchTransition;
    case 'completed':
      return ShareAutomationStatus.completed;
    case 'paused_manual_action_required':
      return ShareAutomationStatus.pausedManualActionRequired;
    case 'auth_relogin_required':
      return ShareAutomationStatus.authReloginRequired;
    case 'failed':
      return ShareAutomationStatus.failed;
    case 'cancelled':
      return ShareAutomationStatus.cancelled;
    case 'idle':
    default:
      return ShareAutomationStatus.idle;
  }
}

class ShareAutomationState {
  const ShareAutomationState({
    required this.sessionId,
    required this.status,
    required this.currentBatchIndex,
    required this.currentBatchNumber,
    required this.totalBatches,
    required this.lastError,
    required this.updatedAt,
    required this.recipientEmail,
  });

  const ShareAutomationState.empty()
      : sessionId = '',
        status = ShareAutomationStatus.idle,
        currentBatchIndex = 0,
        currentBatchNumber = 0,
        totalBatches = 0,
        lastError = '',
        updatedAt = 0,
        recipientEmail = '';

  final String sessionId;
  final ShareAutomationStatus status;
  final int currentBatchIndex;
  final int currentBatchNumber;
  final int totalBatches;
  final String lastError;
  final int updatedAt;
  final String recipientEmail;

  bool get isRunning {
    return status == ShareAutomationStatus.precheck ||
        status == ShareAutomationStatus.openingBatch ||
        status == ShareAutomationStatus.awaitingSendButton ||
        status == ShareAutomationStatus.autoClickingSend ||
        status == ShareAutomationStatus.awaitingMailResult ||
        status == ShareAutomationStatus.nextBatchTransition;
  }

  bool get isPaused {
    return status == ShareAutomationStatus.pausedManualActionRequired ||
        status == ShareAutomationStatus.authReloginRequired;
  }

  bool get isTerminal {
    return status == ShareAutomationStatus.completed ||
        status == ShareAutomationStatus.failed ||
        status == ShareAutomationStatus.cancelled;
  }

  factory ShareAutomationState.fromMap(Map<String, dynamic> map) {
    return ShareAutomationState(
      sessionId: map['sessionId'] as String? ?? '',
      status: shareAutomationStatusFromId(map['state'] as String? ?? 'idle'),
      currentBatchIndex: _toInt(map['currentBatchIndex']),
      currentBatchNumber: _toInt(map['currentBatchNumber']),
      totalBatches: _toInt(map['totalBatches']),
      lastError: map['lastError'] as String? ?? '',
      updatedAt: _toInt(map['updatedAt']),
      recipientEmail: map['recipientEmail'] as String? ?? '',
    );
  }
}

class JobStatus {
  const JobStatus({
    required this.jobId,
    required this.state,
    required this.sentBatches,
    required this.totalBatches,
    required this.lastError,
    required this.updatedAt,
  });

  final String jobId;
  final String state;
  final int sentBatches;
  final int totalBatches;
  final String? lastError;
  final int updatedAt;

  bool get isTerminal {
    return state == 'succeeded' || state == 'failed' || state == 'cancelled';
  }

  factory JobStatus.fromMap(Map<String, dynamic> map) {
    return JobStatus(
      jobId: map['jobId'] as String? ?? '',
      state: map['state'] as String? ?? 'unknown',
      sentBatches: _toInt(map['sentBatches']),
      totalBatches: _toInt(map['totalBatches']),
      lastError: map['lastError'] as String?,
      updatedAt: _toInt(map['updatedAt']),
    );
  }
}

class LogEntry {
  const LogEntry({
    required this.id,
    required this.jobId,
    required this.level,
    required this.message,
    required this.createdAt,
    this.batchIndex,
  });

  final int id;
  final String jobId;
  final String level;
  final String message;
  final int createdAt;
  final int? batchIndex;

  factory LogEntry.fromMap(Map<String, dynamic> map) {
    return LogEntry(
      id: _toInt(map['id']),
      jobId: map['jobId'] as String? ?? '',
      level: map['level'] as String? ?? 'INFO',
      message: map['message'] as String? ?? '',
      batchIndex: map['batchIndex'] == null ? null : _toInt(map['batchIndex']),
      createdAt: _toInt(map['createdAt']),
    );
  }
}

class SmtpSelfTestResult {
  const SmtpSelfTestResult({
    required this.success,
    required this.authMode,
    required this.recipientEmail,
    required this.message,
  });

  const SmtpSelfTestResult.empty()
      : success = false,
        authMode = '',
        recipientEmail = '',
        message = '';

  final bool success;
  final String authMode;
  final String recipientEmail;
  final String message;

  factory SmtpSelfTestResult.fromMap(Map<String, dynamic> map) {
    return SmtpSelfTestResult(
      success: map['success'] == true,
      authMode: map['authMode'] as String? ?? '',
      recipientEmail: map['recipientEmail'] as String? ?? '',
      message: map['message'] as String? ?? '',
    );
  }
}
