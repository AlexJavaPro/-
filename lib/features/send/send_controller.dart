import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/constants.dart';
import '../../core/validation.dart';
import '../../platform/native_bridge.dart';
import '../../platform/native_contract.dart';
import '../contacts/recent_contacts_repository.dart';
import '../photos/photo_model.dart';
import '../settings/settings_model.dart';
import '../settings/settings_repository.dart';
import 'send_draft.dart';
import 'send_error_mapper.dart';
import 'send_draft_repository.dart';

enum GalleryPermissionState {
  unknown,
  granted,
  denied,
  limited,
  restricted,
  permanentlyDenied,
}

class EmailBatchPreview {
  const EmailBatchPreview({
    required this.index,
    required this.photosCount,
    required this.totalBytes,
    required this.exceedsSingleMessageLimit,
  });

  final int index;
  final int photosCount;
  final int totalBytes;
  final bool exceedsSingleMessageLimit;
}

class EmailBatchDetails {
  const EmailBatchDetails({
    required this.index,
    required this.photos,
    required this.totalBytes,
    required this.limitRatio,
    required this.exceedsSingleMessageLimit,
  });

  final int index;
  final List<PhotoDescriptor> photos;
  final int totalBytes;
  final double limitRatio;
  final bool exceedsSingleMessageLimit;

  int get photosCount => photos.length;
}

class SendController extends ChangeNotifier {
  SendController({
    required SettingsRepository settingsRepository,
    required NativeBridge nativeBridge,
    RecentContactsRepository? recentContactsRepository,
    SendDraftRepository? draftRepository,
  })  : _settingsRepository = settingsRepository,
        _nativeBridge = nativeBridge,
        _recentContactsRepository =
            recentContactsRepository ?? const RecentContactsRepository(),
        _draftRepository = draftRepository ?? const SendDraftRepository();

  final SettingsRepository _settingsRepository;
  final NativeBridge _nativeBridge;
  final RecentContactsRepository _recentContactsRepository;
  final SendDraftRepository _draftRepository;

  static const Set<String> _compressionPresets = <String>{
    'none',
    'jpeg_light',
    'jpeg_medium',
    'jpeg_strong',
    'webp_light',
    'webp_medium',
  };

  AppSettings settings = AppSettings.defaults();
  List<PhotoDescriptor> photos = const [];

  final Set<String> _selectedPhotoUris = <String>{};
  final Map<String, int> _photoRotateSteps = <String, int>{};
  bool _selectionInitialized = false;
  bool selectionModeEnabled = false;

  List<String> recentRecipients = const [];
  SendDraft? pendingDraft;
  String? errorMessage;
  String? infoMessage;
  UiError? lastUiError;

  bool initialized = false;
  bool isBusy = false;
  bool isSending = false;
  bool isAutomationActionInProgress = false;
  bool isAutoSending = false;

  YandexAuthState yandexAuthState = const YandexAuthState.empty();
  bool hasSmtpAppPassword = false;
  bool? smtpSelfTestSucceeded;
  DateTime? smtpSelfTestUpdatedAt;
  AccessibilityState accessibilityState = const AccessibilityState.empty();
  ShareAutomationState automationState = const ShareAutomationState.empty();
  String? currentAutoJobId;
  JobStatus? currentAutoJobStatus;
  List<LogEntry> currentAutoLogs = const [];
  int? _lastAutoLogId;

  GalleryPermissionState galleryPermissionState =
      GalleryPermissionState.unknown;
  GalleryPermissionState cameraPermissionState = GalleryPermissionState.unknown;

  List<List<PhotoDescriptor>> _plannedBatches = const <List<PhotoDescriptor>>[];
  int _nextBatchIndex = 0;
  int _rangeStartBatchIndex = 0;
  int _rangeEndBatchIndex = -1;
  String _sessionRecipientEmail = '';
  String _sessionSubject = '';
  String _sessionTargetPackage = '';
  String _sessionMailClientLabel = '';
  int _sessionTotalBytes = 0;

  bool _galleryPermissionPromptedOnce = false;
  bool _disposed = false;
  List<PhotoDescriptor> get selectedPhotos {
    if (photos.isEmpty) {
      return const [];
    }
    if (!_selectionInitialized) {
      return photos;
    }
    return photos
        .where((photo) => _selectedPhotoUris.contains(photo.uri))
        .toList(growable: false);
  }

  List<PhotoDescriptor> get orderedPhotos {
    return _orderedPhotosForSending(photos);
  }

  int get selectedFilesCount => selectedPhotos.length;

  int get selectedBytes =>
      selectedPhotos.fold(0, (sum, file) => sum + file.sizeBytes);

  double get selectedSizeMb =>
      selectedBytes / AppConstants.bytesPerMb.toDouble();

  int get estimatedCompressedBytes => selectedBytes;

  double get estimatedCompressedSizeMb =>
      estimatedCompressedBytes / AppConstants.bytesPerMb.toDouble();

  int get totalPickedCount => photos.length;

  int? get limitBytes => Validation.parseLimitBytesFromMb(settings.limitMb);

  double? get limitMbValue {
    final bytes = limitBytes;
    if (bytes == null || bytes <= 0) {
      return null;
    }
    return bytes / AppConstants.bytesPerMb.toDouble();
  }

  int get oversizedSelectedPhotosCount {
    final limit = limitBytes;
    if (limit == null || limit <= 0) {
      return 0;
    }
    return selectedPhotos.where((photo) => photo.sizeBytes > limit).length;
  }

  bool get exceedsLimitBySize => oversizedSelectedPhotosCount > 0;

  bool get hasGalleryPermission {
    return galleryPermissionState == GalleryPermissionState.granted ||
        galleryPermissionState == GalleryPermissionState.limited;
  }

  bool get galleryPermissionRequiresSettings {
    return galleryPermissionState == GalleryPermissionState.permanentlyDenied ||
        galleryPermissionState == GalleryPermissionState.restricted;
  }

  bool get hasPendingDraft => pendingDraft?.hasContent == true;

  int get pendingDraftPhotosCount => pendingDraft?.photos.length ?? 0;

  String get pendingDraftSubject => pendingDraft?.subject.trim() ?? '';

  MailClientOption get preferredMailClientOption {
    return mailClientOptionFromId(settings.preferredMailClient);
  }

  String get preferredMailClientLabel {
    return mailClientOptionLabel(preferredMailClientOption);
  }

  SendOrderOption get sendOrderOption {
    return sendOrderOptionFromId(settings.sendOrder);
  }

  String get sendOrderLabel {
    return sendOrderOptionLabel(sendOrderOption);
  }

  SendMethodOption get sendMethodOption {
    return sendMethodOptionFromId(settings.sendMethod);
  }

  bool get sendViaShare => sendMethodOption == SendMethodOption.share;

  bool get sendViaAutomatic => sendMethodOption == SendMethodOption.automatic;

  PhotoPickSource get defaultPhotoPickSource {
    switch (normalizePhotoPickSourceDefault(settings.photoPickSourceDefault)) {
      case 'gallery':
        return PhotoPickSource.gallery;
      case 'files':
        return PhotoPickSource.files;
      case 'auto':
      default:
        return PhotoPickSource.auto;
    }
  }

  List<EmailBatchDetails> get estimatedEmailBatchDetails {
    final selected = _orderedPhotosForSending(selectedPhotos);
    if (selected.isEmpty) {
      return const <EmailBatchDetails>[];
    }

    final limit = limitBytes;
    final groups = _splitPhotosByLimit(selected, limit ?? 0);

    return List<EmailBatchDetails>.generate(groups.length, (index) {
      final group = groups[index];
      final totalBytes =
          group.fold<int>(0, (sum, photo) => sum + photo.sizeBytes);
      final limitRatio =
          (limit != null && limit > 0) ? totalBytes / limit : 0.0;
      final exceedsSingleMessageLimit =
          limit != null && limit > 0 && totalBytes > limit;
      return EmailBatchDetails(
        index: index + 1,
        photos: List<PhotoDescriptor>.unmodifiable(group),
        totalBytes: totalBytes,
        limitRatio: limitRatio,
        exceedsSingleMessageLimit: exceedsSingleMessageLimit,
      );
    }, growable: false);
  }

  List<EmailBatchPreview> get estimatedEmailBatches {
    final details = estimatedEmailBatchDetails;
    return details
        .map(
          (item) => EmailBatchPreview(
            index: item.index,
            photosCount: item.photosCount,
            totalBytes: item.totalBytes,
            exceedsSingleMessageLimit: item.exceedsSingleMessageLimit,
          ),
        )
        .toList(growable: false);
  }

  int get estimatedEmails => estimatedEmailBatches.length;

  int get totalBatchCount => _plannedBatches.length;

  int get rangeStartBatchNumber {
    if (totalBatchCount <= 0) {
      return 0;
    }
    final start = _effectiveRangeStart;
    return start + 1;
  }

  int get rangeEndBatchNumber {
    if (totalBatchCount <= 0) {
      return 0;
    }
    final end = _effectiveRangeEnd;
    return end + 1;
  }

  bool get hasCustomBatchRange {
    if (!_hasRangeSelection || totalBatchCount <= 0) {
      return false;
    }
    return rangeStartBatchNumber != 1 || rangeEndBatchNumber != totalBatchCount;
  }

  bool get _hasRangeSelection {
    return totalBatchCount > 0 && _rangeEndBatchIndex >= 0;
  }

  int get _effectiveRangeStart {
    if (totalBatchCount <= 0) {
      return 0;
    }
    return _rangeStartBatchIndex.clamp(0, totalBatchCount - 1);
  }

  int get _effectiveRangeEnd {
    if (totalBatchCount <= 0) {
      return -1;
    }
    final start = _effectiveRangeStart;
    if (!_hasRangeSelection) {
      return totalBatchCount - 1;
    }
    return _rangeEndBatchIndex.clamp(start, totalBatchCount - 1);
  }

  int get _activeBatchCount {
    if (totalBatchCount <= 0) {
      return 0;
    }
    final start = _effectiveRangeStart;
    final end = _effectiveRangeEnd;
    return end - start + 1;
  }

  int get openedBatchCount {
    if (totalBatchCount <= 0) {
      return 0;
    }
    final start = _effectiveRangeStart;
    final openedInRange = _nextBatchIndex - start;
    return openedInRange.clamp(0, _activeBatchCount);
  }

  int get remainingBatchCount =>
      (_activeBatchCount - openedBatchCount).clamp(0, _activeBatchCount);

  bool get hasRemainingBatches => remainingBatchCount > 0;

  int get nextBatchNumber {
    if (!hasRemainingBatches) {
      if (totalBatchCount <= 0) {
        return 0;
      }
      return (_rangeEndBatchIndex + 1).clamp(1, totalBatchCount);
    }
    return _nextBatchIndex + 1;
  }

  double? get sendProgressFraction {
    if (_activeBatchCount <= 0) {
      return null;
    }
    final fraction = openedBatchCount / _activeBatchCount;
    return fraction.clamp(0.0, 1.0).toDouble();
  }

  String get sendProgressLabel {
    if (_activeBatchCount <= 0) {
      final estimated = estimatedEmails;
      if (estimated <= 0) {
        return 'Нет писем для отправки';
      }
      return 'Открыто писем: 0 из $estimated';
    }
    final rangeSuffix = hasCustomBatchRange
        ? ' (диапазон $rangeStartBatchNumber-$rangeEndBatchNumber)'
        : '';
    if (hasRemainingBatches) {
      return 'Открыто писем: $openedBatchCount из $_activeBatchCount$rangeSuffix';
    }
    return 'Открыто писем: $_activeBatchCount из $_activeBatchCount$rangeSuffix';
  }

  String get launchButtonLabel {
    if (hasRemainingBatches && isSending) {
      return 'Открыть письмо $nextBatchNumber из $totalBatchCount';
    }
    return 'Начать отправку';
  }

  bool get canLaunchNextBatch {
    return hasRemainingBatches && isSending && !isBusy;
  }

  bool get hasActiveBatchSession => isSending && totalBatchCount > 0;

  bool isPhotoSelected(PhotoDescriptor photo) {
    if (!_selectionInitialized) {
      return true;
    }
    return _selectedPhotoUris.contains(photo.uri);
  }

  Future<void> init() async {
    isBusy = true;
    notifyListeners();

    try {
      settings = await _settingsRepository.load();
      settings = settings.copyWith(
        compressionPreset:
            _normalizeCompressionPreset(settings.compressionPreset),
        preferredMailClient: mailClientOptionId(
          mailClientOptionFromId(settings.preferredMailClient),
        ),
        sendMethod:
            sendMethodOptionId(sendMethodOptionFromId(settings.sendMethod)),
        sendOrder: sendOrderOptionId(sendOrderOptionFromId(settings.sendOrder)),
        photoPickSourceDefault:
            normalizePhotoPickSourceDefault(settings.photoPickSourceDefault),
      );

      try {
        recentRecipients =
            await _recentContactsRepository.loadRecentRecipients();
      } catch (_) {
        recentRecipients = const [];
      }

      try {
        pendingDraft = await _draftRepository.load();
      } catch (_) {
        pendingDraft = null;
      }
      try {
        _galleryPermissionPromptedOnce =
            await _settingsRepository.loadGalleryPermissionPromptedOnce();
      } catch (_) {
        _galleryPermissionPromptedOnce = false;
      }

      await refreshGalleryPermissionStatus(notify: false);
      await refreshCameraPermissionStatus(notify: false);
      await refreshYandexAuthState(notify: false);
      await refreshSmtpAppPasswordState(notify: false);
      await restoreLatestAutoJobState(notify: false);
      initialized = true;
    } catch (error) {
      errorMessage = 'Не удалось загрузить настройки. Повторите попытку.';
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<GalleryPermissionState> refreshGalleryPermissionStatus({
    bool notify = true,
  }) async {
    final state = await _resolveGalleryPermissionState(request: false);
    galleryPermissionState = state;
    if (notify) {
      notifyListeners();
    }
    return state;
  }

  Future<GalleryPermissionState> requestGalleryPermission() async {
    final shouldRequest = !_galleryPermissionPromptedOnce;
    if (shouldRequest) {
      _galleryPermissionPromptedOnce = true;
      unawaited(_settingsRepository.markGalleryPermissionPromptedOnce());
    }

    final state = await _resolveGalleryPermissionState(request: shouldRequest);
    galleryPermissionState = state;
    notifyListeners();
    return state;
  }

  Future<GalleryPermissionState> refreshCameraPermissionStatus({
    bool notify = true,
  }) async {
    final state = await _resolveCameraPermissionState(request: false);
    cameraPermissionState = state;
    if (notify) {
      notifyListeners();
    }
    return state;
  }

  Future<GalleryPermissionState> requestCameraPermission() async {
    final state = await _resolveCameraPermissionState(request: true);
    cameraPermissionState = state;
    notifyListeners();
    return state;
  }

  Future<void> restorePendingDraft() async {
    final draft = pendingDraft;
    if (draft == null || !draft.hasContent) {
      return;
    }

    photos = draft.photos;
    _selectedPhotoUris
      ..clear()
      ..addAll(draft.photos.map((item) => item.uri));
    _selectionInitialized = draft.photos.isNotEmpty;
    selectionModeEnabled = false;
    settings = settings.copyWith(
      recipientEmail: draft.recipientEmail,
      subject: draft.subject,
    );

    _invalidateBatchSession();
    errorMessage = null;
    infoMessage = 'Черновик восстановлен';
    notifyListeners();
    await _saveDraftIfNeeded();
  }

  Future<void> discardPendingDraft({bool notify = true}) async {
    pendingDraft = null;
    try {
      await _draftRepository.clear();
    } catch (_) {
      // Best-effort cleanup.
    }
    if (notify && !_disposed) {
      notifyListeners();
    }
  }

  void updateRecipientEmail(String value) {
    settings = settings.copyWith(recipientEmail: value);
    errorMessage = null;
    _invalidateBatchSession();
    notifyListeners();
    unawaited(_saveDraftIfNeeded());
    unawaited(_persistRecipientIfNeeded());
  }

  void updateSubject(String value) {
    settings = settings.copyWith(subject: value);
    _invalidateBatchSession();
    notifyListeners();
    unawaited(_saveDraftIfNeeded());
  }

  void selectRecentRecipient(String email) {
    final normalized = email.trim();
    if (normalized.isEmpty) {
      return;
    }
    settings = settings.copyWith(recipientEmail: normalized);
    errorMessage = null;
    lastUiError = null;
    _invalidateBatchSession();
    notifyListeners();
    unawaited(_saveDraftIfNeeded());
    unawaited(_persistRecipientIfNeeded());
  }

  Future<void> applySettings(AppSettings updated) async {
    final previousSendMethod = sendMethodOption;
    final limitError = Validation.validateLimitMb(updated.limitMb);
    if (limitError != null) {
      errorMessage = limitError;
      lastUiError = null;
      notifyListeners();
      return;
    }

    settings = updated.copyWith(
      compressionPreset: _normalizeCompressionPreset(updated.compressionPreset),
      preferredMailClient: mailClientOptionId(
        mailClientOptionFromId(updated.preferredMailClient),
      ),
      sendMethod:
          sendMethodOptionId(sendMethodOptionFromId(updated.sendMethod)),
      sendOrder: sendOrderOptionId(sendOrderOptionFromId(updated.sendOrder)),
      photoPickSourceDefault:
          normalizePhotoPickSourceDefault(updated.photoPickSourceDefault),
    );
    final switchedToShare = previousSendMethod != SendMethodOption.share &&
        sendMethodOption == SendMethodOption.share;
    errorMessage = null;
    lastUiError = null;
    if (switchedToShare) {
      infoMessage = null;
    }
    _invalidateBatchSession();
    notifyListeners();
    unawaited(_saveDraftIfNeeded());

    try {
      await _settingsRepository.save(settings);
    } catch (error) {
      errorMessage = 'Не удалось сохранить настройки.';
      notifyListeners();
    }
  }

  Future<void> updateSendOrder(SendOrderOption option) async {
    final normalized = sendOrderOptionId(option);
    if (settings.sendOrder == normalized) {
      return;
    }

    settings = settings.copyWith(sendOrder: normalized);
    errorMessage = null;
    lastUiError = null;
    _invalidateBatchSession();
    notifyListeners();
    unawaited(_saveDraftIfNeeded());

    try {
      await _settingsRepository.save(settings);
    } catch (error) {
      errorMessage = 'Не удалось сохранить порядок сортировки.';
      notifyListeners();
    }
  }

  Future<void> updatePhotoPickSourceDefault(PhotoPickSource source) async {
    final normalized = _photoPickSourceId(source);
    if (settings.photoPickSourceDefault == normalized) {
      return;
    }

    settings = settings.copyWith(photoPickSourceDefault: normalized);
    errorMessage = null;
    lastUiError = null;
    notifyListeners();

    try {
      await _settingsRepository.save(settings);
    } catch (error) {
      errorMessage = 'Не удалось сохранить источник выбора фото.';
      notifyListeners();
    }
  }

  void clearSelectedPhotos() {
    if (isBusy) {
      return;
    }
    photos = const [];
    _selectedPhotoUris.clear();
    _photoRotateSteps.clear();
    _selectionInitialized = false;
    selectionModeEnabled = false;
    _invalidateBatchSession();
    notifyListeners();
    unawaited(_saveDraftIfNeeded());
  }

  void selectAllPhotos() {
    if (photos.isEmpty || isBusy) {
      return;
    }
    _selectedPhotoUris
      ..clear()
      ..addAll(photos.map((item) => item.uri));
    _selectionInitialized = true;
    _invalidateBatchSession();
    notifyListeners();
    unawaited(_saveDraftIfNeeded());
  }

  void clearPhotoSelection() {
    if (photos.isEmpty || isBusy) {
      return;
    }
    _selectionInitialized = true;
    _selectedPhotoUris.clear();
    _invalidateBatchSession();
    notifyListeners();
    unawaited(_saveDraftIfNeeded());
  }

  void setSelectionMode(bool enabled) {
    if (selectionModeEnabled == enabled) {
      return;
    }
    selectionModeEnabled = enabled;
    notifyListeners();
  }

  void onPhotoLongPress(String uri) {
    togglePhotoSelection(uri);
  }

  int photoRotateSteps(String uri) {
    return _photoRotateSteps[uri] ?? 0;
  }

  void rotatePhoto90(String uri) {
    if (isBusy || photos.isEmpty) {
      return;
    }
    final current = _photoRotateSteps[uri] ?? 0;
    final next = (current + 1) % 4;
    if (next == 0) {
      _photoRotateSteps.remove(uri);
    } else {
      _photoRotateSteps[uri] = next;
    }
    notifyListeners();
  }

  void togglePhotoSelection(String uri) {
    if (isBusy) {
      return;
    }
    _ensureSelectionInitialized();
    if (_selectedPhotoUris.contains(uri)) {
      _selectedPhotoUris.remove(uri);
    } else {
      _selectedPhotoUris.add(uri);
    }
    errorMessage = null;
    lastUiError = null;
    _invalidateBatchSession();
    notifyListeners();
    unawaited(_saveDraftIfNeeded());
  }

  void removePhoto(String uri) {
    if (isBusy || photos.isEmpty) {
      return;
    }

    final updated = photos.where((item) => item.uri != uri).toList();
    if (updated.length == photos.length) {
      return;
    }

    photos = updated;
    _selectedPhotoUris.remove(uri);
    _photoRotateSteps.remove(uri);
    if (photos.isEmpty) {
      _selectionInitialized = false;
      selectionModeEnabled = false;
    }
    _invalidateBatchSession();
    notifyListeners();
    unawaited(_saveDraftIfNeeded());
  }

  Future<void> pickPhotos({
    PhotoPickSource source = PhotoPickSource.auto,
  }) async {
    if (isBusy) {
      return;
    }

    isBusy = true;
    errorMessage = null;
    lastUiError = null;
    infoMessage = null;
    notifyListeners();

    try {
      if (source == PhotoPickSource.gallery) {
        final permissionState = _galleryPermissionPromptedOnce
            ? await _resolveGalleryPermissionState(request: false)
            : await requestGalleryPermission();
        galleryPermissionState = permissionState;
        final granted = permissionState == GalleryPermissionState.granted ||
            permissionState == GalleryPermissionState.limited;
        if (!granted) {
          errorMessage =
              'Нет доступа к галерее. Разрешите доступ в настройках приложения.';
          lastUiError = null;
          return;
        }
      }

      final picked = await _nativeBridge.pickPhotos(source: source);
      if (picked.isEmpty) {
        infoMessage = 'Выбор фото отменен';
        return;
      }

      final hadExplicitSelection = _selectionInitialized;
      final mergedByUri = <String, PhotoDescriptor>{
        for (final item in photos) item.uri: item,
      };

      var addedCount = 0;
      var duplicateCount = 0;
      final addedUris = <String>{};
      for (final item in picked) {
        if (!mergedByUri.containsKey(item.uri)) {
          addedCount++;
          addedUris.add(item.uri);
        } else {
          duplicateCount++;
        }
        mergedByUri[item.uri] = item;
      }

      // Preserve insertion order from the picker to avoid reversed send order.
      final merged = mergedByUri.values.toList(growable: false);
      photos = merged;
      selectionModeEnabled = false;

      if (hadExplicitSelection) {
        _selectedPhotoUris.retainWhere(mergedByUri.containsKey);
        _selectedPhotoUris.addAll(addedUris);
      }

      _invalidateBatchSession();

      if (addedCount > 0 && duplicateCount > 0) {
        infoMessage =
            'Добавлено $addedCount фото, пропущено дубликатов: $duplicateCount';
      } else if (addedCount > 0) {
        infoMessage = 'Добавлено $addedCount фото';
      } else {
        infoMessage = 'Новые фото не добавлены: все уже в списке';
      }

      await _saveDraftIfNeeded();
    } catch (error) {
      if (error is PlatformException && error.code == 'picker_launch_failed') {
        errorMessage = 'Не удалось открыть галерею. Попробуйте позже.';
      } else {
        _applyMappedError(error);
      }
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> startSending({
    int? startPart,
    int? endPart,
    DateTime? reportDate,
    bool includeDate = true,
  }) async {
    if (isBusy) {
      return;
    }
    if (sendViaAutomatic) {
      errorMessage =
          'Для режима «Автоматически» используйте кнопку «Отправить автоматически».';
      lastUiError = null;
      notifyListeners();
      return;
    }

    final recipientEmail = settings.recipientEmail.trim();
    if (recipientEmail.isNotEmpty) {
      final recipientError = Validation.validateEmail(
        recipientEmail,
        fieldLabel: 'email получателя',
      );
      if (recipientError != null) {
        errorMessage = recipientError;
        lastUiError = null;
        notifyListeners();
        return;
      }
    }

    final limitError = Validation.validateLimitMb(settings.limitMb);
    if (limitError != null) {
      errorMessage = limitError;
      lastUiError = null;
      notifyListeners();
      return;
    }

    final parsedLimit = limitBytes;
    if (parsedLimit == null || parsedLimit <= 0) {
      errorMessage = 'Не удалось определить лимит письма.';
      lastUiError = null;
      notifyListeners();
      return;
    }

    final photosToSend = _orderedPhotosForSending(selectedPhotos);
    if (photosToSend.isEmpty) {
      errorMessage = 'Выберите фотографии для отправки';
      lastUiError = null;
      notifyListeners();
      return;
    }

    final plannedBatches = _splitPhotosByLimit(photosToSend, parsedLimit);
    if (plannedBatches.isEmpty) {
      errorMessage = 'Не удалось сформировать письма для отправки';
      lastUiError = null;
      notifyListeners();
      return;
    }

    final resolvedStartPart = startPart ?? 1;
    final resolvedEndPart = endPart ?? plannedBatches.length;
    final rangeError = _validateBatchRange(
      startPart: resolvedStartPart,
      endPart: resolvedEndPart,
      totalParts: plannedBatches.length,
    );
    if (rangeError != null) {
      errorMessage = rangeError;
      lastUiError = null;
      notifyListeners();
      return;
    }

    isBusy = true;
    errorMessage = null;
    lastUiError = null;
    infoMessage = null;
    notifyListeners();

    try {
      await _settingsRepository.save(settings);

      _plannedBatches = plannedBatches;
      _rangeStartBatchIndex = resolvedStartPart - 1;
      _rangeEndBatchIndex = resolvedEndPart - 1;
      _nextBatchIndex = _rangeStartBatchIndex;
      _sessionRecipientEmail = recipientEmail;
      _sessionSubject = _resolveSubject(
        settings.subject,
        reportDate: reportDate,
        includeDate: includeDate,
      );
      _sessionTargetPackage =
          mailClientPackageName(preferredMailClientOption) ?? '';
      _sessionMailClientLabel = preferredMailClientLabel;
      _sessionTotalBytes =
          photosToSend.fold<int>(0, (sum, item) => sum + item.sizeBytes);
      isSending = true;

      if (recipientEmail.isNotEmpty) {
        unawaited(_rememberRecentRecipient(recipientEmail));
      }

      await discardPendingDraft(notify: false);
      await _openNextBatchInternal(manageBusy: false);
    } catch (error) {
      _applyMappedError(error);
      isSending = false;
      _plannedBatches = const <List<PhotoDescriptor>>[];
      _nextBatchIndex = 0;
      _rangeStartBatchIndex = 0;
      _rangeEndBatchIndex = -1;
      _sessionTotalBytes = 0;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  Future<void> startSinglePartSending(int partNumber) {
    return startSending(startPart: partNumber, endPart: partNumber);
  }

  Future<void> openNextBatch() async {
    if (isBusy || !isSending) {
      return;
    }
    await _openNextBatchInternal(manageBusy: true);
  }

  void resetBatchSession() {
    _invalidateBatchSession();
    infoMessage = null;
    notifyListeners();
  }

  void clearError() {
    if (errorMessage == null) {
      return;
    }
    errorMessage = null;
    lastUiError = null;
    notifyListeners();
  }

  void clearInfo() {
    if (infoMessage == null) {
      return;
    }
    infoMessage = null;
    notifyListeners();
  }

  bool get isYandexAuthorized => yandexAuthState.authorized;

  bool get isAccessibilityEnabled => accessibilityState.enabled;

  bool get isAutoSendEnabled => settings.autoSendEnabled;

  bool get isSmtpReady => yandexAuthState.smtpReady;

  bool get hasValidSmtpIdentity {
    final candidate = yandexAuthState.smtpIdentity.trim();
    return Validation.validateEmail(candidate, fieldLabel: 'email SMTP') == null;
  }

  bool get hasSmtpCredential {
    if (!yandexAuthState.authorized) {
      return false;
    }
    return hasSmtpAppPassword || yandexAuthState.authorized;
  }

  bool get canUseAutoMode =>
      sendViaAutomatic &&
      isAutoSendEnabled &&
      preferredMailClientOption == MailClientOption.yandex &&
      yandexAuthState.authorized &&
      yandexAuthState.smtpReady &&
      hasValidSmtpIdentity &&
      hasSmtpCredential;

  bool get canStartAutoSending {
    if (isBusy || isAutoSending || isAutomationActionInProgress) {
      return false;
    }
    if (!canUseAutoMode) {
      return false;
    }
    if (selectedPhotos.isEmpty) {
      return false;
    }
    final recipientEmail = settings.recipientEmail.trim();
    if (recipientEmail.isEmpty) {
      return false;
    }
    return Validation.validateEmail(
          recipientEmail,
          fieldLabel: 'email получателя',
        ) ==
        null;
  }

  String get autoSendStageLabel {
    final status = currentAutoJobStatus;
    if (status == null) {
      return 'Нет активной задачи';
    }
    switch (status.state) {
      case 'queued':
        return 'В очереди';
      case 'running':
        return 'Выполняется';
      case 'retrying':
        return 'Повторная попытка';
      case 'succeeded':
        return 'Успешно';
      case 'failed':
        return 'Ошибка';
      case 'cancelled':
        return 'Остановлено';
      default:
        return 'Неизвестно';
    }
  }

  String get autoSendLastEvent {
    if (currentAutoLogs.isEmpty) {
      return '';
    }
    final last = currentAutoLogs.last;
    final raw = last.message.trim();
    if (raw.isEmpty) {
      return '';
    }
    final level = last.level.trim().toUpperCase();
    if (level == 'ERROR') {
      return _toUserMessage(raw);
    }
    if (level == 'WARN' && _looksLikeTechnicalError(raw)) {
      return _toUserMessage(raw);
    }
    return raw;
  }

  String get autoSendLastEventRaw {
    if (currentAutoLogs.isEmpty) {
      return '';
    }
    return currentAutoLogs.last.message.trim();
  }

  DateTime? get autoSendUpdatedAt {
    final updated = currentAutoJobStatus?.updatedAt ?? 0;
    if (updated <= 0) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(updated);
  }

  bool get autoSendCanCancel {
    final status = currentAutoJobStatus;
    return currentAutoJobId != null &&
        currentAutoJobId!.isNotEmpty &&
        status != null &&
        !status.isTerminal &&
        !isAutomationActionInProgress &&
        !isBusy;
  }

  bool get canStartAutomatedSeries {
    if (isBusy || isAutomationActionInProgress) {
      return false;
    }
    if (selectedPhotos.isEmpty) {
      return false;
    }
    final recipientEmail = settings.recipientEmail.trim();
    if (recipientEmail.isEmpty) {
      return false;
    }
    return Validation.validateEmail(
          recipientEmail,
          fieldLabel: 'email получателя',
        ) ==
        null;
  }

  Future<void> refreshYandexAuthState({bool notify = true}) async {
    try {
      yandexAuthState = await _nativeBridge.getYandexAuthState();
    } catch (_) {
      yandexAuthState = const YandexAuthState.empty();
    }
    if (notify && !_disposed) {
      notifyListeners();
    }
  }

  Future<void> refreshSmtpAppPasswordState({bool notify = true}) async {
    try {
      hasSmtpAppPassword = await _nativeBridge.hasSmtpAppPassword();
    } catch (_) {
      hasSmtpAppPassword = false;
    }
    if (notify && !_disposed) {
      notifyListeners();
    }
  }

  Future<void> startYandexLogin() async {
    if (isAutomationActionInProgress) {
      return;
    }
    isAutomationActionInProgress = true;
    errorMessage = null;
    notifyListeners();
    try {
      yandexAuthState = await _nativeBridge.startYandexLogin();
      if (yandexAuthState.authorized) {
        if (yandexAuthState.smtpReady) {
          infoMessage = 'Вход в Яндекс выполнен';
        } else {
          infoMessage =
              'Вход выполнен, но профиль SMTP не подтвержден. Выполните тест отправки в настройках.';
        }
      }
      await refreshAutomationState(notify: false);
    } on PlatformException catch (error) {
      _applyMappedError(error);
    } catch (error) {
      _applyMappedError(error);
    } finally {
      isAutomationActionInProgress = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  Future<void> logoutYandex() async {
    if (isAutomationActionInProgress) {
      return;
    }
    isAutomationActionInProgress = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _nativeBridge.logoutYandex();
      yandexAuthState = const YandexAuthState.empty();
      infoMessage = 'Вы вышли из аккаунта Яндекса';
      await refreshAutomationState(notify: false);
    } catch (error) {
      _applyMappedError(error);
    } finally {
      isAutomationActionInProgress = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  Future<void> refreshAccessibilityState({bool notify = true}) async {
    try {
      accessibilityState = await _nativeBridge.getAccessibilityState();
    } catch (_) {
      accessibilityState = const AccessibilityState.empty();
    }
    if (notify && !_disposed) {
      notifyListeners();
    }
  }

  Future<void> openAccessibilitySettings() async {
    try {
      await _nativeBridge.openAccessibilitySettings();
    } catch (error) {
      _applyMappedError(error);
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  Future<void> refreshAutomationState({bool notify = true}) async {
    try {
      automationState = await _nativeBridge.getShareAutomationState();
    } catch (_) {
      automationState = const ShareAutomationState.empty();
    }
    if (notify && !_disposed) {
      notifyListeners();
    }
  }

  Future<void> startAutomatedShareSeries({
    DateTime? reportDate,
    bool includeDate = true,
  }) async {
    if (!canStartAutomatedSeries) {
      if (settings.recipientEmail.trim().isEmpty) {
        errorMessage = 'Введите email получателя';
      }
      notifyListeners();
      return;
    }
    final parsedLimit = limitBytes;
    if (parsedLimit == null || parsedLimit <= 0) {
      errorMessage = 'Некорректный лимит письма';
      notifyListeners();
      return;
    }
    if (!yandexAuthState.authorized) {
      errorMessage = 'Выполните вход в Яндекс';
      notifyListeners();
      return;
    }
    if (!accessibilityState.enabled) {
      errorMessage = 'Включите сервис доступности для автосерии';
      notifyListeners();
      return;
    }

    final recipientEmail = settings.recipientEmail.trim();
    final photosToSend = _orderedPhotosForSending(selectedPhotos);
    final subject = _resolveSubject(
      settings.subject,
      reportDate: reportDate,
      includeDate: includeDate,
    );

    isAutomationActionInProgress = true;
    errorMessage = null;
    infoMessage = null;
    notifyListeners();
    try {
      automationState = await _nativeBridge.startShareAutomationSeries(
        recipientEmail: recipientEmail,
        subjectInput: subject,
        limitBytes: parsedLimit,
        photos: photosToSend,
      );
      if (recipientEmail.isNotEmpty) {
        unawaited(_rememberRecentRecipient(recipientEmail));
      }
      await discardPendingDraft(notify: false);
      infoMessage = 'Автосерия запущена';
    } catch (error) {
      _applyMappedError(error);
    } finally {
      isAutomationActionInProgress = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  Future<void> resumeAutomatedSeries() async {
    if (isAutomationActionInProgress) {
      return;
    }
    isAutomationActionInProgress = true;
    errorMessage = null;
    notifyListeners();
    try {
      automationState = await _nativeBridge.resumeShareAutomation();
      infoMessage = 'Автосерия продолжена';
    } catch (error) {
      _applyMappedError(error);
    } finally {
      isAutomationActionInProgress = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  Future<void> cancelAutomatedSeries() async {
    if (isAutomationActionInProgress) {
      return;
    }
    isAutomationActionInProgress = true;
    errorMessage = null;
    notifyListeners();
    try {
      automationState = await _nativeBridge.cancelShareAutomation();
      infoMessage = 'Автосерия остановлена';
    } catch (error) {
      _applyMappedError(error);
    } finally {
      isAutomationActionInProgress = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  Future<void> openCurrentBatchManually() async {
    if (isAutomationActionInProgress) {
      return;
    }
    isAutomationActionInProgress = true;
    errorMessage = null;
    notifyListeners();
    try {
      automationState = await _nativeBridge.openCurrentShareBatchManually();
      infoMessage = 'Текущий пакет открыт вручную';
    } catch (error) {
      _applyMappedError(error);
    } finally {
      isAutomationActionInProgress = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  Future<void> _openNextBatchInternal({required bool manageBusy}) async {
    if (!isSending) {
      return;
    }
    if (_nextBatchIndex < _rangeStartBatchIndex) {
      _nextBatchIndex = _rangeStartBatchIndex;
    }
    if (_nextBatchIndex > _rangeEndBatchIndex ||
        _nextBatchIndex >= _plannedBatches.length) {
      final hadCustomRange = _rangeStartBatchIndex > 0 ||
          _rangeEndBatchIndex < _plannedBatches.length - 1;
      isSending = false;
      if (hadCustomRange) {
        infoMessage =
            'Письма $rangeStartBatchNumber-$rangeEndBatchNumber подготовлены к отправке.';
      } else {
        infoMessage = 'Все письма подготовлены к отправке.';
      }
      return;
    }

    if (manageBusy) {
      isBusy = true;
      notifyListeners();
    }

    final batchIndex = _nextBatchIndex;
    final total = _plannedBatches.length;
    final batch = _plannedBatches[batchIndex];

    try {
      final currentPart = batchIndex + 1;
      final subject = _buildBatchSubject(
        baseSubject: _sessionSubject,
        current: currentPart,
        total: total,
      );
      final body = _buildBatchBody(
        batch: batch,
        current: currentPart,
        total: total,
        totalSessionBytes: _sessionTotalBytes,
      );

      await _nativeBridge.openExternalEmail(
        photos: batch,
        recipientEmail: _sessionRecipientEmail,
        subject: subject,
        body: body,
        targetPackage: _sessionTargetPackage,
      );

      _nextBatchIndex = currentPart;
      final completedRange = _nextBatchIndex > _rangeEndBatchIndex;
      if (completedRange) {
        final hadCustomRange =
            _rangeStartBatchIndex > 0 || _rangeEndBatchIndex < total - 1;
        isSending = false;
        if (hadCustomRange) {
          infoMessage =
              'Открыты письма $rangeStartBatchNumber-$rangeEndBatchNumber в клиенте "$_sessionMailClientLabel".';
        } else {
          infoMessage =
              'Открыты все $total писем в клиенте "$_sessionMailClientLabel".';
        }
      } else {
        infoMessage =
            'Открыто письмо $currentPart из $total в клиенте "$_sessionMailClientLabel".';
      }
      errorMessage = null;
    } catch (error) {
      if (_sessionTargetPackage.isNotEmpty) {
        errorMessage =
            'Не удалось открыть "$_sessionMailClientLabel". Проверьте, что приложение установлено.';
      } else {
        _applyMappedError(error);
      }
    } finally {
      if (manageBusy) {
        isBusy = false;
      }
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  List<List<PhotoDescriptor>> _splitPhotosByLimit(
    List<PhotoDescriptor> selected,
    int maxBytesPerEmail,
  ) {
    if (selected.isEmpty) {
      return const <List<PhotoDescriptor>>[];
    }
    if (maxBytesPerEmail <= 0) {
      return <List<PhotoDescriptor>>[selected];
    }

    final batches = <List<PhotoDescriptor>>[];
    var currentBatch = <PhotoDescriptor>[];
    var currentBytes = 0;

    for (final photo in selected) {
      final photoBytes = photo.sizeBytes;

      if (photoBytes > maxBytesPerEmail) {
        if (currentBatch.isNotEmpty) {
          batches.add(currentBatch);
          currentBatch = <PhotoDescriptor>[];
          currentBytes = 0;
        }
        batches.add(<PhotoDescriptor>[photo]);
        continue;
      }

      if (currentBatch.isNotEmpty &&
          currentBytes + photoBytes > maxBytesPerEmail) {
        batches.add(currentBatch);
        currentBatch = <PhotoDescriptor>[];
        currentBytes = 0;
      }

      currentBatch.add(photo);
      currentBytes += photoBytes;
    }

    if (currentBatch.isNotEmpty) {
      batches.add(currentBatch);
    }

    return batches;
  }

  String? _validateBatchRange({
    required int startPart,
    required int endPart,
    required int totalParts,
  }) {
    if (startPart < 1 || endPart < 1) {
      return 'Неверный диапазон: номер письма должен быть не меньше 1';
    }
    if (startPart > endPart) {
      return 'Неверный диапазон: начало больше конца';
    }
    if (startPart > totalParts || endPart > totalParts) {
      return 'Неверный диапазон. Доступно писем: $totalParts';
    }
    return null;
  }

  Future<void> setAutoSendEnabled(bool enabled) async {
    if (settings.autoSendEnabled == enabled) {
      return;
    }
    settings = settings.copyWith(autoSendEnabled: enabled);
    notifyListeners();
    try {
      await _settingsRepository.save(settings);
    } catch (_) {
      errorMessage = 'Не удалось сохранить настройку автоотправки.';
      notifyListeners();
    }
  }

  Future<void> saveSmtpAppPassword(String value) async {
    if (isAutomationActionInProgress) {
      return;
    }
    final validation = Validation.validateAppPassword(value);
    if (validation != null) {
      errorMessage = validation;
      notifyListeners();
      return;
    }

    isAutomationActionInProgress = true;
    errorMessage = null;
    infoMessage = null;
    notifyListeners();
    try {
      await _nativeBridge.saveSmtpAppPassword(value.trim());
      await refreshSmtpAppPasswordState(notify: false);
      infoMessage = 'Пароль приложения сохранён.';
    } catch (error) {
      _applyMappedError(error);
    } finally {
      isAutomationActionInProgress = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  Future<void> clearSmtpAppPassword() async {
    if (isAutomationActionInProgress) {
      return;
    }
    isAutomationActionInProgress = true;
    errorMessage = null;
    infoMessage = null;
    notifyListeners();
    try {
      await _nativeBridge.clearSmtpAppPassword();
      await refreshSmtpAppPasswordState(notify: false);
      infoMessage = 'Пароль приложения удалён.';
    } catch (error) {
      _applyMappedError(error);
    } finally {
      isAutomationActionInProgress = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  Future<void> runSmtpSelfTest({
    required String recipientEmail,
  }) async {
    if (isAutomationActionInProgress) {
      return;
    }
    final email = recipientEmail.trim();
    final validation = Validation.validateEmail(
      email,
      fieldLabel: 'email получателя',
    );
    if (validation != null) {
      errorMessage = validation;
      notifyListeners();
      return;
    }
    if (!yandexAuthState.authorized) {
      errorMessage = 'Сначала выполните вход в Яндекс.';
      notifyListeners();
      return;
    }

    isAutomationActionInProgress = true;
    errorMessage = null;
    infoMessage = null;
    notifyListeners();
    try {
      await _nativeBridge.runSmtpSelfTest(recipientEmail: email);
      await refreshYandexAuthState(notify: false);
      smtpSelfTestSucceeded = true;
      smtpSelfTestUpdatedAt = DateTime.now();
      infoMessage = 'Тестовое письмо отправлено.';
    } catch (error) {
      await refreshYandexAuthState(notify: false);
      smtpSelfTestSucceeded = false;
      smtpSelfTestUpdatedAt = DateTime.now();
      _applyMappedError(error);
    } finally {
      isAutomationActionInProgress = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  Future<void> savePasswordAndRunSelfTest(String passwordInput) async {
    if (isAutomationActionInProgress) {
      return;
    }
    if (!yandexAuthState.authorized) {
      errorMessage = 'Сначала выполните вход в Яндекс.';
      notifyListeners();
      return;
    }

    final normalizedPassword = passwordInput.trim().replaceAll(
          RegExp(r'[\s-]+'),
          '',
        );
    if (normalizedPassword.isNotEmpty) {
      final validation = Validation.validateAppPassword(normalizedPassword);
      if (validation != null) {
        errorMessage = validation;
        notifyListeners();
        return;
      }
    } else if (!hasSmtpAppPassword) {
      errorMessage =
          'Введите пароль приложения или сохраните его ранее в настройках.';
      notifyListeners();
      return;
    }

    isAutomationActionInProgress = true;
    errorMessage = null;
    infoMessage = null;
    notifyListeners();
    try {
      final outcome = await _nativeBridge.saveAndRunSmtpSelfTest(
        appPassword: normalizedPassword.isEmpty ? null : normalizedPassword,
      );
      await refreshYandexAuthState(notify: false);
      await refreshSmtpAppPasswordState(notify: false);
      smtpSelfTestSucceeded = outcome.success;
      smtpSelfTestUpdatedAt = DateTime.now();
      final authModeText =
          outcome.authMode == 'app_password' ? 'пароль приложения' : 'OAuth2';
      final recipient = outcome.recipientEmail.trim();
      infoMessage = recipient.isEmpty
          ? 'Тестовое письмо отправлено ($authModeText).'
          : 'Тестовое письмо отправлено на $recipient ($authModeText).';
    } catch (error) {
      await refreshYandexAuthState(notify: false);
      await refreshSmtpAppPasswordState(notify: false);
      smtpSelfTestSucceeded = false;
      smtpSelfTestUpdatedAt = DateTime.now();
      _applyMappedError(error);
    } finally {
      isAutomationActionInProgress = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  Future<void> restoreLatestAutoJobState({bool notify = true}) async {
    try {
      final latest = await _nativeBridge.getLatestJobStatus();
      if (latest == null) {
        currentAutoJobId = null;
        currentAutoJobStatus = null;
        currentAutoLogs = const [];
        _lastAutoLogId = null;
        isAutoSending = false;
      } else {
        currentAutoJobId = latest.jobId;
        currentAutoJobStatus = latest;
        currentAutoLogs = const [];
        _lastAutoLogId = null;
        isAutoSending = !latest.isTerminal;
        await refreshAutoJobStatus(notify: false, updateMessages: false);
      }
    } catch (_) {
      // Keep current state if restore failed.
    } finally {
      if (notify && !_disposed) {
        notifyListeners();
      }
    }
  }

  Future<void> startAutoSending({
    DateTime? reportDate,
    bool includeDate = true,
  }) async {
    if (isBusy) {
      return;
    }
    final recipientEmail = settings.recipientEmail.trim();
    final recipientError = Validation.validateEmail(
      recipientEmail,
      fieldLabel: 'email получателя',
    );
    if (recipientError != null) {
      errorMessage = recipientError;
      lastUiError = null;
      notifyListeners();
      return;
    }

    if (!hasValidSmtpIdentity) {
      errorMessage = 'Укажите email для SMTP.';
      lastUiError = null;
      notifyListeners();
      return;
    }

    if (!hasSmtpCredential) {
      errorMessage = 'Укажите пароль приложения или войдите в Яндекс.';
      lastUiError = null;
      notifyListeners();
      return;
    }

    if (!canUseAutoMode) {
      errorMessage =
          'Автоотправка недоступна. Проверьте настройки отправки, вход в Яндекс и тест отправки.';
      lastUiError = null;
      notifyListeners();
      return;
    }
    final parsedLimit = limitBytes;
    if (parsedLimit == null || parsedLimit <= 0) {
      errorMessage = 'Некорректный лимит письма.';
      lastUiError = null;
      notifyListeners();
      return;
    }
    final photosToSend = _orderedPhotosForSending(selectedPhotos);
    if (photosToSend.isEmpty) {
      errorMessage = 'Выберите фотографии для отправки.';
      lastUiError = null;
      notifyListeners();
      return;
    }

    isBusy = true;
    isAutoSending = true;
    errorMessage = null;
    lastUiError = null;
    infoMessage = null;
    notifyListeners();

    try {
      final subject = _resolveSubject(
        settings.subject,
        reportDate: reportDate,
        includeDate: includeDate,
      );

      final jobId = await _nativeBridge.enqueueSendJob(
        recipientEmail: recipientEmail,
        subjectInput: subject,
        limitBytes: parsedLimit,
        compressionPreset: settings.compressionPreset,
        photos: photosToSend,
      );

      currentAutoJobId = jobId;
      currentAutoJobStatus = null;
      currentAutoLogs = const [];
      _lastAutoLogId = null;
      infoMessage = 'Фоновая отправка запущена.';

      if (recipientEmail.isNotEmpty) {
        unawaited(_rememberRecentRecipient(recipientEmail));
      }
      await discardPendingDraft(notify: false);
      await refreshAutoJobStatus(notify: false);
    } on PlatformException catch (error) {
      isAutoSending = false;
      _applyMappedError(error);
    } catch (error) {
      isAutoSending = false;
      _applyMappedError(error);
    } finally {
      isBusy = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  Future<void> cancelAutoSending() async {
    final jobId = currentAutoJobId;
    if (jobId == null || jobId.isEmpty || !autoSendCanCancel) {
      return;
    }
    isAutomationActionInProgress = true;
    errorMessage = null;
    notifyListeners();
    try {
      final status = await _nativeBridge.cancelSendJob(jobId);
      currentAutoJobStatus = status;
      isAutoSending = !status.isTerminal;
      infoMessage = 'Отправка остановлена.';
      await refreshAutoJobStatus(notify: false);
    } catch (error) {
      _applyMappedError(error);
    } finally {
      isAutomationActionInProgress = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  Future<void> refreshAutoJobStatus({
    bool notify = true,
    bool updateMessages = true,
  }) async {
    final jobId = currentAutoJobId;
    if (jobId == null || jobId.isEmpty) {
      if (notify && !_disposed) {
        notifyListeners();
      }
      return;
    }

    try {
      final canUpdateMessages = updateMessages && sendViaAutomatic;
      final status = await _nativeBridge.getJobStatus(jobId);
      currentAutoJobStatus = status;
      isAutoSending = !status.isTerminal;

      final newLogs =
          await _nativeBridge.getJobLogs(jobId, afterId: _lastAutoLogId);
      if (newLogs.isNotEmpty) {
        currentAutoLogs = List<LogEntry>.unmodifiable(
          <LogEntry>[...currentAutoLogs, ...newLogs],
        );
        _lastAutoLogId = newLogs.last.id;
      }

      if (status.isTerminal) {
        if (canUpdateMessages) {
          if (status.state == 'succeeded') {
            infoMessage = 'Отправка завершена успешно.';
            errorMessage = null;
            lastUiError = null;
          } else if (status.state == 'cancelled') {
            infoMessage = 'Отправка остановлена.';
            errorMessage = null;
            lastUiError = null;
          } else {
            _applyMappedError(status.lastError ?? 'failed');
          }
        }
      }
    } catch (error) {
      if (updateMessages && sendViaAutomatic) {
        _applyMappedError(error);
      }
    } finally {
      if (notify && !_disposed) {
        notifyListeners();
      }
    }
  }

  String _buildBatchSubject({
    required String baseSubject,
    required int current,
    required int total,
  }) {
    if (total <= 1) {
      return baseSubject;
    }
    return '$baseSubject (Часть $current из $total)';
  }

  String _buildBatchBody({
    required List<PhotoDescriptor> batch,
    required int current,
    required int total,
    required int totalSessionBytes,
  }) {
    final batchBytes = batch.fold<int>(0, (sum, item) => sum + item.sizeBytes);
    final percentage =
        totalSessionBytes > 0 ? (batchBytes / totalSessionBytes) * 100 : 0.0;
    final buffer = StringBuffer();
    buffer.writeln('Письмо: часть $current из $total');
    buffer.writeln('Количество файлов: ${batch.length}');
    buffer.writeln('Размер текущего письма: ${_formatBytes(batchBytes)}');
    buffer.writeln(
        'Общий размер выбранных фото: ${_formatBytes(totalSessionBytes)}');
    buffer.writeln('Доля текущего письма: ${_formatPercent(percentage)}');
    buffer.writeln('');
    buffer.writeln('Список файлов:');
    for (var index = 0; index < batch.length; index++) {
      final file = batch[index];
      buffer.writeln(
        '${index + 1}. ${file.name} (${_formatBytes(file.sizeBytes)})',
      );
    }
    return buffer.toString().trimRight();
  }

  Future<GalleryPermissionState> _resolveGalleryPermissionState({
    required bool request,
  }) async {
    if (kIsWeb) {
      return GalleryPermissionState.granted;
    }

    try {
      final photosStatus = request
          ? await Permission.photos.request()
          : await Permission.photos.status;
      final mappedPhotoStatus = _mapPermissionStatus(photosStatus);
      if (mappedPhotoStatus == GalleryPermissionState.granted ||
          mappedPhotoStatus == GalleryPermissionState.limited) {
        return mappedPhotoStatus;
      }

      if (!Platform.isAndroid) {
        return mappedPhotoStatus;
      }

      final storageStatus = request
          ? await Permission.storage.request()
          : await Permission.storage.status;
      final mappedStorageStatus = _mapPermissionStatus(storageStatus);
      if (mappedStorageStatus == GalleryPermissionState.granted ||
          mappedStorageStatus == GalleryPermissionState.limited) {
        return mappedStorageStatus;
      }

      if (mappedPhotoStatus == GalleryPermissionState.permanentlyDenied ||
          mappedStorageStatus == GalleryPermissionState.permanentlyDenied) {
        return GalleryPermissionState.permanentlyDenied;
      }
      if (mappedPhotoStatus == GalleryPermissionState.restricted ||
          mappedStorageStatus == GalleryPermissionState.restricted) {
        return GalleryPermissionState.restricted;
      }
      return GalleryPermissionState.denied;
    } catch (error) {
      _applyMappedError(error);
      return GalleryPermissionState.denied;
    }
  }

  Future<GalleryPermissionState> _resolveCameraPermissionState({
    required bool request,
  }) async {
    if (kIsWeb) {
      return GalleryPermissionState.granted;
    }

    try {
      final cameraStatus = request
          ? await Permission.camera.request()
          : await Permission.camera.status;
      return _mapPermissionStatus(cameraStatus);
    } catch (error) {
      _applyMappedError(error);
      return GalleryPermissionState.denied;
    }
  }

  GalleryPermissionState _mapPermissionStatus(PermissionStatus status) {
    if (status.isGranted) {
      return GalleryPermissionState.granted;
    }
    if (status.isLimited) {
      return GalleryPermissionState.limited;
    }
    if (status.isPermanentlyDenied) {
      return GalleryPermissionState.permanentlyDenied;
    }
    if (status.isRestricted) {
      return GalleryPermissionState.restricted;
    }
    return GalleryPermissionState.denied;
  }

  Future<void> _rememberRecentRecipient(String recipientEmail) async {
    try {
      recentRecipients =
          await _recentContactsRepository.rememberRecipient(recipientEmail);
      if (!_disposed) {
        notifyListeners();
      }
    } catch (_) {
      // Main flow must not fail because of history persistence.
    }
  }

  Future<void> _persistRecipientIfNeeded() async {
    if (!settings.rememberRecipientEmail) {
      return;
    }
    try {
      await _settingsRepository.save(settings);
    } catch (_) {
      // Best-effort persistence while editing recipient.
    }
  }

  Future<void> _saveDraftIfNeeded() async {
    final currentDraft = SendDraft(
      photos: selectedPhotos,
      subject: settings.subject,
      senderEmail: '',
      recipientEmail: settings.recipientEmail,
      savedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );

    if (!currentDraft.hasContent) {
      pendingDraft = null;
      try {
        await _draftRepository.clear();
      } catch (_) {
        // Best-effort cleanup.
      }
      return;
    }

    pendingDraft = currentDraft;
    try {
      await _draftRepository.save(currentDraft);
    } catch (_) {
      // Draft persistence is optional.
    }
  }

  List<PhotoDescriptor> _orderedPhotosForSending(
    List<PhotoDescriptor> source,
  ) {
    if (source.length <= 1) {
      return source;
    }

    final indexed = source.asMap().entries.toList(growable: false);

    int compareByCaptured(
      MapEntry<int, PhotoDescriptor> left,
      MapEntry<int, PhotoDescriptor> right, {
      required bool descending,
    }) {
      final leftCaptured = left.value.capturedAtMillis;
      final rightCaptured = right.value.capturedAtMillis;
      if (leftCaptured != null && rightCaptured != null) {
        final byDate = leftCaptured.compareTo(rightCaptured);
        if (byDate != 0) {
          return descending ? -byDate : byDate;
        }
      }
      final byIndex = left.key.compareTo(right.key);
      return descending ? -byIndex : byIndex;
    }

    final ordered = List<MapEntry<int, PhotoDescriptor>>.from(indexed);
    switch (sendOrderOptionFromId(settings.sendOrder)) {
      case SendOrderOption.addedAsc:
        ordered.sort((a, b) => compareByCaptured(a, b, descending: false));
        return ordered.map((entry) => entry.value).toList(growable: false);
      case SendOrderOption.addedDesc:
        ordered.sort((a, b) => compareByCaptured(a, b, descending: true));
        return ordered.map((entry) => entry.value).toList(growable: false);
      case SendOrderOption.sizeAsc:
        ordered.sort((a, b) {
          final bySize = a.value.sizeBytes.compareTo(b.value.sizeBytes);
          if (bySize != 0) {
            return bySize;
          }
          return a.value.name
              .toLowerCase()
              .compareTo(b.value.name.toLowerCase());
        });
        return ordered.map((entry) => entry.value).toList(growable: false);
      case SendOrderOption.sizeDesc:
        ordered.sort((a, b) {
          final bySize = b.value.sizeBytes.compareTo(a.value.sizeBytes);
          if (bySize != 0) {
            return bySize;
          }
          return a.value.name
              .toLowerCase()
              .compareTo(b.value.name.toLowerCase());
        });
        return ordered.map((entry) => entry.value).toList(growable: false);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) {
      return '0 Б';
    }
    final units = <String>['Б', 'КБ', 'МБ', 'ГБ'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    final fractionDigits = value >= 100 ? 0 : (value >= 10 ? 1 : 2);
    final formatted = value.toStringAsFixed(fractionDigits);
    return '$formatted ${units[unitIndex]}';
  }

  String _formatPercent(double value) {
    final clamped = value.clamp(0, 999).toDouble();
    final digits = clamped >= 10 ? 1 : 2;
    return '${clamped.toStringAsFixed(digits)}%';
  }

  String _resolveSubject(
    String input, {
    DateTime? reportDate,
    bool includeDate = true,
  }) {
    final rawBase = input.trim().isEmpty ? 'Фото' : input.trim();
    final compact = rawBase.replaceAll(RegExp(r'\s+'), ' ').trim();
    final baseWithoutDate = compact
        .replaceFirst(
          RegExp(r'\s+от\s+\d{2}\.\d{2}\.\d{4}$', caseSensitive: false),
          '',
        )
        .trim();
    final normalizedBase = baseWithoutDate.isEmpty ? 'Фото' : baseWithoutDate;
    if (!includeDate) {
      return normalizedBase;
    }
    final datePart = _resolveReportDate(reportDate);
    return '$normalizedBase от $datePart';
  }

  String _resolveReportDate(DateTime? reportDate) {
    final effectiveDate = reportDate ?? DateTime.now();
    return DateFormat('dd.MM.yyyy').format(effectiveDate);
  }

  void _applyMappedError(Object error) {
    final mapped = SendErrorMapper.map(error);
    lastUiError = mapped;
    errorMessage = mapped.message;
  }

  UiError mapErrorToUi(Object error) {
    return SendErrorMapper.map(error);
  }

  String _toUserMessage(Object error) {
    return mapErrorToUi(error).message;
  }

  String mapErrorToMessage(Object error) {
    return _toUserMessage(error);
  }

  bool _looksLikeTechnicalError(String message) {
    final normalized = message.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    return normalized.contains('535') ||
        normalized.contains('5.7.8') ||
        normalized.contains('smtp') ||
        normalized.contains('auth') ||
        normalized.contains('exception') ||
        normalized.contains('error');
  }

  String _normalizeCompressionPreset(String input) {
    final normalized = input.trim().toLowerCase();
    if (_compressionPresets.contains(normalized)) {
      return normalized;
    }
    return 'none';
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

  void _ensureSelectionInitialized() {
    if (_selectionInitialized) {
      return;
    }
    _selectedPhotoUris
      ..clear()
      ..addAll(photos.map((item) => item.uri));
    _selectionInitialized = true;
  }

  void _invalidateBatchSession() {
    if (_plannedBatches.isEmpty && !isSending && _nextBatchIndex == 0) {
      return;
    }
    _plannedBatches = const <List<PhotoDescriptor>>[];
    _nextBatchIndex = 0;
    _rangeStartBatchIndex = 0;
    _rangeEndBatchIndex = -1;
    isSending = false;
    _sessionRecipientEmail = '';
    _sessionSubject = '';
    _sessionTargetPackage = '';
    _sessionMailClientLabel = '';
    _sessionTotalBytes = 0;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
