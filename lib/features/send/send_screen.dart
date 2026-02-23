import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/validation.dart';
import '../../platform/native_bridge.dart';
import '../photos/photo_model.dart';
import '../settings/settings_model.dart';
import '../settings/settings_repository.dart';
import 'send_controller.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> with WidgetsBindingObserver {
  late final SendController _controller;
  late final ScrollController _sendScrollController;
  final GlobalKey _sendCardKey = GlobalKey();
  late final TextEditingController _recipientController;
  late final TextEditingController _subjectController;
  late final TextEditingController _rangeStartController;
  late final TextEditingController _rangeEndController;
  late final TextEditingController _reportDateController;
  late final DateFormat _reportDateFormat;
  int _tabIndex = 0;
  bool _showSplashScreen = true;
  bool _sendWithoutDate = false;
  String? _lastHandledInfo;
  String? _lastStatusSignature;
  String? _lastAutoJobSignature;
  Timer? _statusAutoHideTimer;
  Timer? _automationPollTimer;
  int _lastEstimatedEmails = -1;
  int _securityStepCounter = 0;
  DateTime _lastSecurityStepTap = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = SendController(
      settingsRepository: const SettingsRepository(),
      nativeBridge: const NativeBridge(),
    )..addListener(_onControllerChanged);
    _sendScrollController = ScrollController();
    _recipientController = TextEditingController();
    _subjectController = TextEditingController();
    _rangeStartController = TextEditingController();
    _rangeEndController = TextEditingController();
    _reportDateFormat = DateFormat('dd.MM.yyyy');
    _reportDateController = TextEditingController(
      text: _reportDateFormat.format(DateTime.now()),
    );
    _recipientController.addListener(
      () => _controller.updateRecipientEmail(_recipientController.text),
    );
    _subjectController.addListener(
      () => _controller.updateSubject(_subjectController.text),
    );
    _reportDateController.addListener(() {
      if (mounted) setState(() {});
    });
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final startedAt = DateTime.now();
    await _controller.init();
    if (!mounted) return;
    _syncTextFieldsFromState();
    _syncRangeInputsFromEstimate(force: true);
    const minSplashTime = Duration(milliseconds: 700);
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed < minSplashTime) {
      await Future<void>.delayed(minSplashTime - elapsed);
    }
    if (!mounted) return;
    _startAutomationStatePolling();
    setState(() { _showSplashScreen = false; });
    
    if (_controller.pendingDraft != null && _controller.photos.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Черновик успешно загружен'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFF1A3F8F),
          ),
        );
      });
    }
  }

  void _startAutomationStatePolling() {
    _automationPollTimer?.cancel();
    _automationPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      unawaited(_controller.refreshAutoJobStatus(updateMessages: false));
      if (!_controller.yandexAuthState.authorized) {
        unawaited(_controller.refreshYandexAuthState());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.refreshGalleryPermissionStatus());
      unawaited(_controller.refreshYandexAuthState());
      unawaited(_controller.refreshAutoJobStatus(updateMessages: false));
      if (_controller.hasActiveBatchSession || _controller.isAutoSending) {
        _scheduleScrollToSendCard(animated: false);
      }
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    _syncTextFieldsFromState();
    _syncRangeInputsFromEstimate();
    final info = _controller.infoMessage;
    if (info != null && info.isNotEmpty && info != _lastHandledInfo) {
      _lastHandledInfo = info;
      if (_controller.hasActiveBatchSession ||
          _controller.hasRemainingBatches ||
          _controller.isAutoSending) {
        _scheduleScrollToSendCard();
      }
    }
    final autoStatus = _controller.currentAutoJobStatus;
    final autoSignature = autoStatus == null
        ? ''
        : '${autoStatus.jobId}:${autoStatus.state}:${autoStatus.sentBatches}:${autoStatus.totalBatches}:${autoStatus.updatedAt}';
    if (autoSignature.isNotEmpty &&
        autoSignature != _lastAutoJobSignature &&
        _controller.isAutoSending) {
      _lastAutoJobSignature = autoSignature;
      _scheduleScrollToSendCard(animated: false);
    } else if (autoSignature.isEmpty) {
      _lastAutoJobSignature = null;
    }
    _syncStatusBannerAndAutoHide();
  }

  void _syncStatusBannerAndAutoHide() {
    final error = _controller.errorMessage?.trim();
    final info = _controller.infoMessage?.trim();
    final hasError = error != null && error.isNotEmpty;
    final hasInfo = info != null && info.isNotEmpty;
    final signature = hasError ? 'error:$error' : hasInfo ? 'info:$info' : '';
    final messenger = ScaffoldMessenger.of(context);
    final changed = _lastStatusSignature != signature;
    _lastStatusSignature = signature;
    _statusAutoHideTimer?.cancel();
    if (signature.isEmpty) {
      messenger.hideCurrentMaterialBanner();
      return;
    }
    final bannerText = hasError ? error : info;
    if (bannerText == null || bannerText.isEmpty) return;
    if (changed) {
      messenger.hideCurrentMaterialBanner();
      messenger.showMaterialBanner(
        MaterialBanner(
          content: Text(
            bannerText,
            style: TextStyle(
              color: hasError ? const Color(0xFF8E1A2B) : const Color(0xFF1F6A2A),
              fontWeight: FontWeight.w600,
            ),
          ),
          leading: Icon(
            hasError ? Icons.error_outline : Icons.check_circle_outline,
            color: hasError ? const Color(0xFF8E1A2B) : const Color(0xFF1F6A2A),
          ),
          backgroundColor: hasError ? const Color(0xFFFBE7EA) : const Color(0xFFE7F4EA),
          actions: [
            TextButton(
              onPressed: () {
                messenger.hideCurrentMaterialBanner();
                if (hasError) _controller.clearError();
                else _controller.clearInfo();
              },
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
    }
    _statusAutoHideTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      messenger.hideCurrentMaterialBanner();
      if (_controller.errorMessage?.trim().isNotEmpty ?? false) _controller.clearError();
      if (_controller.infoMessage?.trim().isNotEmpty ?? false) _controller.clearInfo();
    });
  }

  void _syncTextFieldsFromState() {
    _syncControllerValue(_recipientController, _controller.settings.recipientEmail);
    _syncControllerValue(_subjectController, _controller.settings.subject);
  }

  void _syncControllerValue(TextEditingController controller, String next) {
    if (controller.text == next) return;
    final selection = controller.selection;
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: selection.isValid
            ? selection.baseOffset.clamp(0, next.length)
            : next.length,
      ),
    );
  }

  void _syncRangeInputsFromEstimate({bool force = false}) {
    final estimated = _controller.estimatedEmails;
    if (!force && estimated == _lastEstimatedEmails) return;
    _lastEstimatedEmails = estimated;
    if (_controller.hasActiveBatchSession) return;
    if (estimated <= 0) {
      _syncControllerValue(_rangeStartController, '');
      _syncControllerValue(_rangeEndController, '');
      return;
    }
    final start = _parseIntOrFallback(_rangeStartController.text, 1);
    final end = _parseIntOrFallback(_rangeEndController.text, estimated);
    final clampedStart = start.clamp(1, estimated);
    final clampedEnd = end.clamp(clampedStart, estimated);
    if (force || _rangeStartController.text.trim().isEmpty || _rangeEndController.text.trim().isEmpty) {
      _syncControllerValue(_rangeStartController, '1');
      _syncControllerValue(_rangeEndController, '$estimated');
      return;
    }
    _syncControllerValue(_rangeStartController, '$clampedStart');
    _syncControllerValue(_rangeEndController, '$clampedEnd');
  }

  int _parseIntOrFallback(String value, int fallback) =>
      int.tryParse(value.trim()) ?? fallback;

  DateTime? _parseReportDateOrNull(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    try { return _reportDateFormat.parseStrict(normalized); } catch (_) { return null; }
  }

  String? get _reportDateError {
    final raw = _reportDateController.text.trim();
    if (raw.isEmpty) return 'Укажите дату отчета';
    if (_parseReportDateOrNull(raw) == null) return 'Дата в формате ДД.ММ.ГГГГ';
    return null;
  }

  void _scrollToBottom(ScrollController controller, {bool animated = true}) {
    if (!mounted || !controller.hasClients) return;
    final target = controller.position.maxScrollExtent;
    if (animated) {
      controller.animateTo(target,
          duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
    } else {
      controller.jumpTo(target);
    }
  }

  void _scheduleScrollToSendCard({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetContext = _sendCardKey.currentContext;
      if (targetContext == null) {
        _scrollToBottom(_sendScrollController, animated: animated);
        return;
      }
      Scrollable.ensureVisible(targetContext,
          duration: animated ? const Duration(milliseconds: 260) : Duration.zero,
          curve: Curves.easeOutCubic,
          alignment: 0.08);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusAutoHideTimer?.cancel();
    _automationPollTimer?.cancel();
    _controller..removeListener(_onControllerChanged)..dispose();
    _sendScrollController.dispose();
    _recipientController.dispose();
    _subjectController.dispose();
    _rangeStartController.dispose();
    _rangeEndController.dispose();
    _reportDateController.dispose();
    super.dispose();
  }

  String? get _recipientError {
    final value = _recipientController.text.trim();
    if (value.isEmpty) return null;
    return Validation.validateEmail(value, fieldLabel: 'email получателя');
  }

  String? get _rangeError {
    if (_controller.hasActiveBatchSession) return null;
    final total = _controller.estimatedEmails;
    if (total <= 0) return null;
    final start = int.tryParse(_rangeStartController.text.trim());
    final end = int.tryParse(_rangeEndController.text.trim());
    if (start == null || end == null) return 'Укажите номера частей цифрами';
    if (start < 1 || end < 1) return 'Номер части должен быть не меньше 1';
    if (start > end) return 'Начало диапазона не может быть больше конца';
    if (end > total) return 'Доступно частей: $total';
    return null;
  }

  bool get _canStartSend {
    if (_controller.isBusy || _controller.selectedFilesCount == 0) return false;
    return _recipientError == null &&
        _rangeError == null &&
        (_sendWithoutDate || _reportDateError == null);
  }

  Future<void> _openSendSettingsPage() async {
    final result = await Navigator.of(context).push<_SendSettingsResult>(
      MaterialPageRoute<_SendSettingsResult>(
        builder: (context) => _SendSettingsPage(
          controller: _controller,
          initialLimitMb: _controller.settings.limitMb,
          initialSendMethod: _controller.sendMethodOption,
          initialPhotoSource: _controller.defaultPhotoPickSource,
          initialCompression: compressionPresetFromId(_controller.settings.compressionPreset),
          initialAutoSendEnabled: _controller.settings.autoSendEnabled,
          initialSendOrder: _controller.sendOrderOption,
        ),
      ),
    );
    if (result == null || !mounted) return;
    
    final implicitMailClient = result.sendMethod == SendMethodOption.automatic 
        ? MailClientOption.yandex 
        : MailClientOption.system;

    await _controller.applySettings(
      _controller.settings.copyWith(
        limitMb: result.limitMb,
        preferredMailClient: mailClientOptionId(implicitMailClient),
        sendMethod: sendMethodOptionId(result.sendMethod),
        photoPickSourceDefault: _photoPickSourceId(result.photoSource),
        compressionPreset: compressionPresetId(result.compression),
        autoSendEnabled: result.autoSendEnabled,
        sendOrder: sendOrderOptionId(result.sendOrder),
      ),
    );
  }

  Future<void> _requestGalleryPermission() async {
    final state = await _controller.requestGalleryPermission();
    if (!mounted) return;
    final granted = state == GalleryPermissionState.granted ||
        state == GalleryPermissionState.limited;
    if (granted && _controller.hasActiveBatchSession) {
      _scheduleScrollToSendCard();
    }
  }

  Future<void> _handleSendAction() async {
    if (_controller.hasActiveBatchSession && _controller.hasRemainingBatches) {
      await _controller.openNextBatch();
      _scheduleScrollToSendCard();
      return;
    }
    final estimated = _controller.estimatedEmails;
    final startPart = _parseIntOrFallback(_rangeStartController.text, 1);
    final endPart = _parseIntOrFallback(_rangeEndController.text, estimated > 0 ? estimated : 1);
    final includeDate = !_sendWithoutDate;
    final reportDate = includeDate
        ? (_parseReportDateOrNull(_reportDateController.text) ?? DateTime.now())
        : null;
    await _controller.startSending(
        startPart: startPart, endPart: endPart, reportDate: reportDate, includeDate: includeDate);
    _scheduleScrollToSendCard();
  }

  Future<void> _handleAutoSendStart() async {
    final includeDate = !_sendWithoutDate;
    final reportDate = includeDate
        ? (_parseReportDateOrNull(_reportDateController.text) ?? DateTime.now())
        : null;
    await _controller.startAutoSending(reportDate: reportDate, includeDate: includeDate);
    _scheduleScrollToSendCard();
  }

  bool get _usingAutomaticMode => _controller.sendViaAutomatic;

  String _currentSendMethodLabel() => sendMethodOptionLabel(_controller.sendMethodOption);

  String _shareActionLabel() {
    final total = _controller.hasActiveBatchSession
        ? _controller.totalBatchCount
        : _controller.estimatedEmails;
    final safeTotal = total > 0 ? total : 1;
    final current = _controller.hasActiveBatchSession ? _controller.nextBatchNumber : 1;
    return 'Открыть письмо $current из $safeTotal';
  }

  String _primarySendActionLabel() {
    if (!_usingAutomaticMode) return _shareActionLabel();
    final status = _controller.currentAutoJobStatus;
    if (_controller.isAutoSending && status != null) {
      return 'Отправка: ${status.sentBatches}/${status.totalBatches}';
    }
    if (_controller.isAutoSending) return 'Автоматическая отправка выполняется';
    return 'Отправить автоматически';
  }

  Future<void> _handlePrimarySendAction() async {
    if (!_usingAutomaticMode) { await _handleSendAction(); return; }
    if (_controller.isAutoSending) return;
    await _handleAutoSendStart();
  }

  Future<void> _addPhotosAsIs() async {
    if (_controller.isBusy) return;
    await _controller.pickPhotos(source: _controller.defaultPhotoPickSource);
  }

  String _photoPickSourceId(PhotoPickSource source) {
    switch (source) {
      case PhotoPickSource.auto: return 'auto';
      case PhotoPickSource.gallery: return 'gallery';
      case PhotoPickSource.files: return 'files';
    }
  }

  String _photoPickSourceLabel(PhotoPickSource source) {
    switch (source) {
      case PhotoPickSource.auto: return 'Системный выбор';
      case PhotoPickSource.gallery: return 'Галерея';
      case PhotoPickSource.files: return 'Файлы';
    }
  }

  Future<void> _addPhotosWithSourceOverride() async {
    if (_controller.isBusy) return;
    final initialSource = _controller.defaultPhotoPickSource;
    var selectedSource = initialSource;
    var saveAsDefault = false;
    final result = await showModalBottomSheet<_PhotoSourceSelectionResult>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(builder: (context, setSheetState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Выбор источника фото',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1C4A95))),
                  const SizedBox(height: 10),
                  RadioGroup<PhotoPickSource>(
                    groupValue: selectedSource,
                    onChanged: (value) {
                      if (value == null) return;
                      setSheetState(() { selectedSource = value; });
                    },
                    child: Column(
                      children: PhotoPickSource.values.map((source) => RadioListTile<PhotoPickSource>(
                        value: source,
                        contentPadding: EdgeInsets.zero,
                        title: Text(_photoPickSourceLabel(source)),
                      )).toList(growable: false),
                    ),
                  ),
                  const SizedBox(height: 4),
                  CheckboxListTile(
                    value: saveAsDefault,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Сделать источником по умолчанию'),
                    onChanged: (value) { setSheetState(() { saveAsDefault = value ?? false; }); },
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена'))),
                    const SizedBox(width: 10),
                    Expanded(child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(_PhotoSourceSelectionResult(source: selectedSource, saveAsDefault: saveAsDefault)),
                      child: const Text('Выбрать'),
                    )),
                  ]),
                ],
              ),
            ),
          );
        });
      },
    );
    if (!mounted || result == null) return;
    if (result.saveAsDefault) await _controller.updatePhotoPickSourceDefault(result.source);
    await _controller.pickPhotos(source: result.source);
  }

  void _setRangeToAll() {
    final total = _controller.estimatedEmails;
    if (total <= 0) return;
    _syncControllerValue(_rangeStartController, '1');
    _syncControllerValue(_rangeEndController, '$total');
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_showSplashScreen) return const _SplashScreen();

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: const Color(0xFFF2F6FF),
          appBar: _buildAppBar(),
          body: IndexedStack(
            index: _tabIndex,
            children: [
              _buildTabPhotos(),
              _buildTabLettersAndCompose(),
              _buildTabSend(),
            ],
          ),
          bottomNavigationBar: _buildBottomNav(),
          floatingActionButton: _tabIndex == 0 ? _buildFabPhotos() : null,
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    String title = 'ФотоПочта';
    if (_tabIndex == 0) title = 'Фотографии';
    if (_tabIndex == 1) title = 'Письма и данные';
    if (_tabIndex == 2) title = 'Отправка';

    return AppBar(
      backgroundColor: const Color(0xFF1A3F8F),
      foregroundColor: Colors.white,
      elevation: 0,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          onPressed: _openSendSettingsPage,
          tooltip: 'Настройки',
        ),
      ],
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, -2))
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (index) => setState(() => _tabIndex = index),
        selectedItemColor: const Color(0xFF1A3F8F),
        unselectedItemColor: const Color(0xFF7A9ADB),
        backgroundColor: Colors.white,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.photo_library), label: 'Фото'),
          BottomNavigationBarItem(icon: Icon(Icons.email), label: 'Письма'),
          BottomNavigationBarItem(icon: Icon(Icons.send), label: 'Отправка'),
        ],
      ),
    );
  }

  Widget _buildTabPhotos() {
    final photos = _controller.photos;
    if (photos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_library_outlined, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            const Text('Нет фотографий', style: TextStyle(color: Colors.grey, fontSize: 16)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _addPhotosAsIs, child: const Text('Добавить фото')),
          ],
        ),
      );
    }

    return Column(
      children: [
        _buildPhotosHeader(),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: photos.length,
            itemBuilder: (context, index) {
              final photo = photos[index];
              return _PhotoTile(
                photo: photo,
                selected: true,
                rotationAngle: 0,
                subtitle: '',
                onTap: () {},
                onLongPress: () {},
                onRemove: () => _controller.removePhoto(photo.uri),
              );
            },
          ),
        ),
        _buildDeveloperFooter(),
      ],
    );
  }

  Widget _buildPhotosHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          _QuickStatChip(icon: Icons.image, text: '${_controller.totalPickedCount} шт.'),
          const SizedBox(width: 8),
          _QuickStatChip(icon: Icons.straighten, text: '${_controller.selectedSizeMb.toStringAsFixed(1)} МБ'),
          const Spacer(),
          TextButton(
            onPressed: () => _controller.clearAllPhotos(),
            child: const Text('Очистить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildFabPhotos() {
    return FloatingActionButton.extended(
      onPressed: _addPhotosWithSourceOverride,
      backgroundColor: const Color(0xFF1A3F8F),
      foregroundColor: Colors.white,
      icon: const Icon(Icons.add_a_photo),
      label: const Text('Добавить'),
    );
  }

  Widget _buildTabLettersAndCompose() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildComposeCard(),
          const SizedBox(height: 16),
          _buildLetterAnalyticsCard(),
          const SizedBox(height: 16),
          _buildBatchList(),
        ],
      ),
    );
  }

  Widget _buildComposeCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _recipientController,
              decoration: InputDecoration(
                labelText: 'Кому',
                prefixIcon: const Icon(Icons.person_outline),
                errorText: _recipientError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subjectController,
              decoration: const InputDecoration(
                labelText: 'Тема',
                prefixIcon: const Icon(Icons.subject),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _reportDateController,
                    decoration: InputDecoration(
                      labelText: 'Дата отчета',
                      prefixIcon: const Icon(Icons.calendar_today_outlined),
                      errorText: _reportDateError,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.today, color: Color(0xFF1A3F8F)),
                  onPressed: () => setState(() => _reportDateController.text = _reportDateFormat.format(DateTime.now())),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLetterAnalyticsCard() {
    final batches = _controller.estimatedEmailBatches;
    final totalSize = _controller.selectedSizeMb.toStringAsFixed(1);
    
    return Card(
      elevation: 0,
      color: const Color(0xFFEEF4FF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFD0E0FF))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Письма не открывают вложения и ещё не дают взаимодействия с файлами',
              style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1A3F8F), fontSize: 13),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _AnalyticsItem(label: 'Всего писем:', value: '${batches.length}'),
                const SizedBox(width: 20),
                _AnalyticsItem(label: 'Общий вес:', value: '$totalSize МБ'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBatchList() {
    final batches = _controller.estimatedEmailBatches;
    if (batches.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text('Распределение по частям', style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF5A6E9A))),
        ),
        ...batches.map((b) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              CircleAvatar(backgroundColor: const Color(0xFF1A3F8F), radius: 12, child: Text('${b.index}', style: const TextStyle(fontSize: 10, color: Colors.white))),
              const SizedBox(width: 12),
              Expanded(child: Text('Часть ${b.index}: ${b.photosCount} фото')),
              Text('${(b.totalBytes / 1024 / 1024).toStringAsFixed(1)} МБ', style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        )),
      ],
    );
  }

  Widget _buildTabSend() {
    final isAuto = _usingAutomaticMode;

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSendProgressHeader(),
          const SizedBox(height: 48),
          if (!_controller.isAutoSending) ...[
            FilledButton.icon(
              onPressed: _canStartSend ? _handlePrimarySendAction : null,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 20),
                backgroundColor: const Color(0xFF1A3F8F),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              icon: const Icon(Icons.send, size: 24),
              label: Text(_primarySendActionLabel(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
          ] else ...[
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 24),
            Text(_primarySendActionLabel(), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () => _controller.cancelAutoSending(), child: const Text('Остановить', style: TextStyle(color: Colors.red))),
          ],
          if (isAuto && !_controller.isAutoSending) ...[
            const SizedBox(height: 12),
            Text(
              _controller.yandexAuthState.smtpReady ? 'Готов к автоматической отправке' : 'Требуется авторизация Яндекс',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: _controller.yandexAuthState.smtpReady ? Colors.green : Colors.orange),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSendProgressHeader() {
    return Column(
      children: [
        const Icon(Icons.cloud_upload_outlined, size: 84, color: Color(0xFF1A3F8F)),
        const SizedBox(height: 16),
        const Text('Готовность к отправке', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text('${_controller.selectedFilesCount} фото в ${_controller.estimatedEmails} письмах', style: const TextStyle(color: Colors.grey)),
      ],
    );
  }

  Widget _buildDeveloperFooter() {
    return GestureDetector(
      onTap: _handleSecurityEasterEgg,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        child: Text(
          'Разработал Aлексей',
          style: TextStyle(color: Colors.grey[400], fontSize: 12, decoration: TextDecoration.underline),
        ),
      ),
    );
  }

  void _handleSecurityEasterEgg() {
    final now = DateTime.now();
    if (now.difference(_lastSecurityStepTap).inSeconds > 2) {
      _securityStepCounter = 1;
    } else {
      _securityStepCounter++;
    }
    _lastSecurityStepTap = now;

    if (_securityStepCounter >= 5) {
      _securityStepCounter = 0;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('5 шагов безопасности'),
          content: const Text(
            '1) Сделай паузу и продумай работу.\n\n'
            '2) Определи опасности и возможные последствия.\n\n'
            '3) Реши, как защитить себя и других от этих опасностей.\n\n'
            '4) Реши, что делать в экстренных случаях.\n\n'
            '5) Прими решение: начинать/продолжать работу или нет.',
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Понял'))],
        ),
      );
    }
  }

  String _photoSourceLabel(PhotoPickSource source) {
    switch (source) {
      case PhotoPickSource.auto: return 'Системный выбор';
      case PhotoPickSource.gallery: return 'Галерея';
      case PhotoPickSource.files: return 'Файлы';
    }
  }
}

class _AnalyticsItem extends StatelessWidget {
  const _AnalyticsItem({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF5A6E9A))),
        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1A3F8F))),
      ],
    );
  }
}

class _NoneClass { // Placeholder to match structure


class _QuickStatChip extends StatelessWidget {
  const _QuickStatChip({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF3F8FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD7E6FF)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFF2D73E0), size: 16),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(
                color: Color(0xFF315785),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.photo,
    required this.selected,
    required this.rotationAngle,
    required this.onTap,
    required this.onLongPress,
    required this.onRemove,
    required this.subtitle,
  });

  final PhotoDescriptor photo;
  final bool selected;
  final double rotationAngle;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onRemove;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  selected ? const Color(0xFF2E74FF) : const Color(0xFFD7E6FF),
              width: selected ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Transform.rotate(
                  angle: rotationAngle,
                  child: photo.thumbnailBytes != null
                      ? Image.memory(photo.thumbnailBytes!, fit: BoxFit.cover)
                      : const ColoredBox(
                          color: Color(0xFFE9F1FF),
                          child: Icon(
                            Icons.image_outlined,
                            color: Color(0xFF5D7FB8),
                          ),
                        ),
                ),
                if (selected)
                  Container(color: Colors.black.withValues(alpha: 0.18)),
                if (selected)
                  const Positioned(
                    top: 6,
                    left: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xFF2E74FF),
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(2),
                        child: Icon(
                          Icons.check,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: SizedBox(
                    width: 46,
                    height: 46,
                    child: Align(
                      alignment: Alignment.topRight,
                      child: _TileActionButton(
                        icon: Icons.close,
                        onTap: onRemove,
                        semanticLabel: 'Удалить фото',
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                    color: Colors.black54,
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TileActionButton extends StatelessWidget {
  const _TileActionButton({
    required this.icon,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Material(
          color: Colors.black54,
          shape: const CircleBorder(),
          child: SizedBox(
            width: 28,
            height: 28,
            child: Center(
              child: Icon(
                icon,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}


// ═══════════════════════════════════════════════════════════════
//  Вспомогательные виджеты страницы настроек отправки
// ═══════════════════════════════════════════════════════════════

class _SettingGroupCard extends StatelessWidget {
  const _SettingGroupCard({
    required this.title,
    required this.icon,
    required this.child,
    this.statusColor,
    this.statusLabel,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final Color? statusColor;
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD7E6FF)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A3F8F).withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: const BoxDecoration(
              color: Color(0xFFF0F5FF),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 22, color: const Color(0xFF1A3F8F)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: Color(0xFF1A3060),
                    ),
                  ),
                ),
                if (statusLabel != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (statusColor ?? const Color(0xFF2E9A53)).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusLabel!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: statusColor ?? const Color(0xFF2E9A53),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _AuthStatusRow extends StatelessWidget {
  const _AuthStatusRow({required this.authorized, this.displayName});
  final bool authorized;
  final String? displayName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: authorized ? const Color(0xFFEAF7EE) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: authorized ? const Color(0xFF9FD6A8) : const Color(0xFFCCCCCC),
        ),
      ),
      child: Row(
        children: [
          Icon(
            authorized ? Icons.check_circle : Icons.account_circle_outlined,
            color: authorized ? const Color(0xFF2E9A53) : const Color(0xFF888888),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              authorized
                  ? 'Яндекс подключён: ${displayName ?? ''}'
                  : 'Яндекс не подключён',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: authorized ? const Color(0xFF1F6A2A) : const Color(0xFF555555),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: const Color(0xFF5A6E9A)),
        const SizedBox(width: 6),
        Text('$label: ', style: const TextStyle(color: Color(0xFF5A6E9A), fontSize: 13)),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _PasswordSavedBadge extends StatelessWidget {
  const _PasswordSavedBadge({this.onClear});
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F4EA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF9FD6A8)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_outlined, size: 18, color: Color(0xFF1F6A2A)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Пароль приложения сохранён',
              style: TextStyle(color: Color(0xFF1F6A2A), fontWeight: FontWeight.w700),
            ),
          ),
          if (onClear != null)
            TextButton(
              onPressed: onClear,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF9C2B36),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: const Text('Удалить'),
            ),
        ],
      ),
    );
  }
}

class _SmtpTestingIndicator extends StatelessWidget {
  const _SmtpTestingIndicator();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F5FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB3CFFF)),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1A3F8F)),
          ),
          SizedBox(width: 12),
          Text(
            'Проверяется подключение к SMTP…',
            style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1A3060)),
          ),
        ],
      ),
    );
  }
}

class _SmtpResultBanner extends StatelessWidget {
  const _SmtpResultBanner({
    super.key,
    required this.success,
    required this.message,
    required this.updatedAt,
  });
  final bool success;
  final String message;
  final String updatedAt;

  @override
  Widget build(BuildContext context) {
    final bg = success ? const Color(0xFFE7F4EA) : const Color(0xFFFBE7EA);
    final border = success ? const Color(0xFF9FD6A8) : const Color(0xFFF0A0AA);
    final textColor = success ? const Color(0xFF1F6A2A) : const Color(0xFF8E1A2B);
    final icon = success ? Icons.check_circle_outline : Icons.error_outline;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: textColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(fontWeight: FontWeight.w700, color: textColor),
                ),
              ),
            ],
          ),
          if (updatedAt.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              updatedAt,
              style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.7)),
            ),
          ],
        ],
      ),
    );
  }
}

class _SmtpTroubleshootingHint extends StatelessWidget {
  const _SmtpTroubleshootingHint();

  Future<void> _openYandexAppPasswords() async {
    final uri = Uri.parse('https://id.yandex.ru/security/app-passwords');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openYandexMailSettings() async {
    final uri = Uri.parse('https://mail.yandex.ru/#setup/client');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD88A)),
      ),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: const Color(0xFF8A6000),
        collapsedIconColor: const Color(0xFF8A6000),
        title: const Row(
          children: [
            Icon(Icons.help_outline, size: 18, color: Color(0xFF8A6000)),
            SizedBox(width: 8),
            Text(
              'Не удалось войти? Инструкция',
              style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF5C3D00), fontSize: 13),
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _StepInstruction(
            stepNumber: 1,
            title: 'Включите доступ по IMAP',
            description: 'В настройках почты Яндекса (Настройки → Почтовые программы) должна стоять галочка на "С сервера imap.yandex.ru по протоколу IMAP" и "Пароли приложений и OAuth-токены".',
            buttonLabel: 'Настройки почты',
            buttonIcon: Icons.settings_outlined,
            onPressed: _openYandexMailSettings,
          ),
          const SizedBox(height: 12),
          _StepInstruction(
            stepNumber: 2,
            title: 'Создайте пароль приложения',
            description: 'В Яндекс ID (Безопасность → Пароли приложений) создайте новый пароль. Выберите тип "Почта".',
            buttonLabel: 'Пароли приложений',
            buttonIcon: Icons.vpn_key_outlined,
            onPressed: _openYandexAppPasswords,
          ),
          const SizedBox(height: 12),
          const _StepInstruction(
            stepNumber: 3,
            title: 'Скопируйте и вставьте',
            description: 'Полученный 16-значный пароль вставьте в поле выше. Пробелы можно не стирать, приложение уберёт их автоматически.',
          ),
        ],
      ),
    );
  }
}

class _StepInstruction extends StatelessWidget {
  const _StepInstruction({
    required this.stepNumber,
    required this.title,
    required this.description,
    this.buttonLabel,
    this.buttonIcon,
    this.onPressed,
  });

  final int stepNumber;
  final String title;
  final String description;
  final String? buttonLabel;
  final IconData? buttonIcon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFFFD88A),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            '$stepNumber',
            style: const TextStyle(
              color: Color(0xFF5C3D00),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF5C3D00), fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(color: Color(0xFF5C3D00), fontSize: 13, height: 1.4),
              ),
              if (buttonLabel != null && onPressed != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF8A6000),
                    side: const BorderSide(color: Color(0xFFFFD88A)),
                    textStyle: const TextStyle(fontSize: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  onPressed: onPressed,
                  icon: Icon(buttonIcon, size: 14),
                  label: Text(buttonLabel!),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _HintText extends StatelessWidget {
  const _HintText({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 14, color: Color(0xFF5A6E9A)),
        const SizedBox(width: 4),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFF5A6E9A))),
        ),
      ],
    );
  }
}
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.photo_library_outlined,
                size: 54, color: Color(0xFF2E74FF)),
            SizedBox(height: 10),
            Text(
              'ФотоПочта',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Color(0xFF244C95),
              ),
            ),
            SizedBox(height: 14),
            CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class _SendSettingsResult {
  const _SendSettingsResult({
    required this.limitMb,
    required this.sendMethod,
    required this.photoSource,
    required this.compression,
    required this.autoSendEnabled,
    required this.sendOrder,
  });

  final String limitMb;
  final SendMethodOption sendMethod;
  final PhotoPickSource photoSource;
  final CompressionPreset compression;
  final bool autoSendEnabled;
  final SendOrderOption sendOrder;
}

class _SendSettingsPage extends StatefulWidget {
  const _SendSettingsPage({
    required this.controller,
    required this.initialLimitMb,
    required this.initialSendMethod,
    required this.initialPhotoSource,
    required this.initialCompression,
    required this.initialAutoSendEnabled,
    required this.initialSendOrder,
  });

  final SendController controller;
  final String initialLimitMb;
  final SendMethodOption initialSendMethod;
  final PhotoPickSource initialPhotoSource;
  final CompressionPreset initialCompression;
  final bool initialAutoSendEnabled;
  final SendOrderOption initialSendOrder;

  @override
  State<_SendSettingsPage> createState() => _SendSettingsPageState();
}

class _SendSettingsPageState extends State<_SendSettingsPage> {
  late final TextEditingController _limitController;
  late final TextEditingController _appPasswordController;
  late PhotoPickSource _selectedPhotoSource;
  late CompressionPreset _selectedCompression;
  late SendMethodOption _selectedSendMethod;
  late SendOrderOption _selectedSendOrder;
  late bool _autoSendEnabled;
  bool _editingAppPassword = false;
  String? _limitError;

  @override
  void initState() {
    super.initState();
    _limitController = TextEditingController(text: widget.initialLimitMb);
    _appPasswordController = TextEditingController();
    _selectedPhotoSource = widget.initialPhotoSource;
    _selectedCompression = widget.initialCompression;
    _selectedSendMethod = widget.initialSendMethod;
    _selectedSendOrder = widget.initialSendOrder;
    _autoSendEnabled = widget.initialAutoSendEnabled;
  }

  @override
  void dispose() {
    _limitController.dispose();
    _appPasswordController.dispose();
    super.dispose();
  }

  void _save() {
    final limit = _limitController.text.trim();
    if (limit.isEmpty) {
      setState(() => _limitError = 'Укажите лимит');
      return;
    }
    Navigator.of(context).pop(_SendSettingsResult(
      limitMb: limit,
      sendMethod: _selectedSendMethod,
      photoSource: _selectedPhotoSource,
      compression: _selectedCompression,
      autoSendEnabled: _autoSendEnabled,
      sendOrder: _selectedSendOrder,
    ));
  }

  Future<void> _loginYandex() => widget.controller.startYandexLogin();
  Future<void> _logoutYandex() => widget.controller.logoutYandex();

  Future<void> _saveAndRunSelfTest() async {
    final pw = _appPasswordController.text.trim().replaceAll(' ', '');
    await widget.controller.saveSmtpAppPassword(pw);
    setState(() {
      _editingAppPassword = false;
      _appPasswordController.clear();
    });
    await widget.controller.runSmtpSelfTest(
      recipientEmail: widget.controller.settings.recipientEmail,
    );
  }

  Future<void> _clearSmtpAppPassword() async {
    await widget.controller.clearSmtpAppPassword();
    setState(() => _editingAppPassword = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A3F8F),
        foregroundColor: Colors.white,
        title: const Text('Настройки', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(onPressed: _save, icon: const Icon(Icons.check)),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildExpansionGroup(
              title: '1. Источник фото',
              icon: Icons.photo_library_outlined,
              initiallyExpanded: true,
              children: [
                _buildPhotoSourceGrid(),
              ],
            ),
            const SizedBox(height: 12),
            _buildExpansionGroup(
              title: '4. Сжатие фото',
              icon: Icons.compress,
              children: [
                _buildCompressionOptions(),
              ],
            ),
            const SizedBox(height: 12),
            _buildExpansionGroup(
              title: '5. Лимит письма',
              icon: Icons.data_usage_outlined,
              children: [
                _buildLimitInput(),
              ],
            ),
            const SizedBox(height: 12),
            _buildExpansionGroup(
              title: '2. Способ отправки',
              icon: Icons.send_outlined,
              children: [
                _buildSendMethodOptions(),
              ],
            ),
            if (_selectedSendMethod == SendMethodOption.automatic) ...[
              const SizedBox(height: 12),
              _buildExpansionGroup(
                title: '3. Авторизация Яндекс',
                icon: Icons.lock_outlined,
                children: [
                  _buildYandexAuthContent(),
                ],
              ),
            ],
            const SizedBox(height: 12),
            _buildExpansionGroup(
              title: '6. Порядок файлов',
              icon: Icons.sort,
              children: [
                _buildOrderOptions(),
              ],
            ),
            const SizedBox(height: 12),
            _buildExpansionGroup(
              title: '7. Автоотправка',
              icon: Icons.autorenew,
              children: [
                _buildAutoSendToggle(),
              ],
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                backgroundColor: const Color(0xFF1A3F8F),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.save),
              label: const Text('Применить все настройки', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpansionGroup({
    required String title,
    required IconData icon,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          leading: Icon(icon, color: const Color(0xFF1A3F8F)),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1A3060), fontSize: 15),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _buildPhotoSourceGrid() {
    return Column(
      children: PhotoPickSource.values.map((source) {
        final selected = _selectedPhotoSource == source;
        return RadioListTile<PhotoPickSource>(
          value: source,
          groupValue: _selectedPhotoSource,
          title: Text(_photoSourceLabel(source)),
          onChanged: (v) => setState(() => _selectedPhotoSource = v!),
          contentPadding: EdgeInsets.zero,
          activeColor: const Color(0xFF1A3F8F),
        );
      }).toList(),
    );
  }

  Widget _buildCompressionOptions() {
    return Column(
      children: CompressionPreset.values.map((preset) {
        return RadioListTile<CompressionPreset>(
          value: preset,
          groupValue: _selectedCompression,
          title: Text(compressionPresetLabel(preset)),
          subtitle: Text(compressionPresetDescription(preset), style: const TextStyle(fontSize: 12)),
          onChanged: (v) => setState(() => _selectedCompression = v!),
          contentPadding: EdgeInsets.zero,
          activeColor: const Color(0xFF1A3F8F),
        );
      }).toList(),
    );
  }

  Widget _buildLimitInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _limitController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'МБ',
            errorText: _limitError,
            filled: true,
            fillColor: const Color(0xFFF8FBFF),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [10, 20, 25, 50].map((v) => ActionChip(
            label: Text('$v МБ'),
            onPressed: () => setState(() => _limitController.text = '$v'),
          )).toList(),
        ),
      ],
    );
  }

  Widget _buildSendMethodOptions() {
    return Column(
      children: SendMethodOption.values.map((option) {
        return RadioListTile<SendMethodOption>(
          value: option,
          groupValue: _selectedSendMethod,
          title: Text(sendMethodOptionLabel(option)),
          subtitle: Text(option == SendMethodOption.automatic ? 'Фоновая отправка через Яндекс' : 'Системное меню'),
          onChanged: (v) => setState(() => _selectedSendMethod = v!),
          contentPadding: EdgeInsets.zero,
          activeColor: const Color(0xFF1A3F8F),
        );
      }).toList(),
    );
  }

  Widget _buildOrderOptions() {
    return Column(
      children: SendOrderOption.values.map((option) {
        return RadioListTile<SendOrderOption>(
          value: option,
          groupValue: _selectedSendOrder,
          title: Text(sendOrderOptionLabel(option)),
          onChanged: (v) => setState(() => _selectedSendOrder = v!),
          contentPadding: EdgeInsets.zero,
          activeColor: const Color(0xFF1A3F8F),
        );
      }).toList(),
    );
  }

  Widget _buildAutoSendToggle() {
    return SwitchListTile(
      value: _autoSendEnabled,
      onChanged: (v) => setState(() => _autoSendEnabled = v),
      title: const Text('Отправлять пакеты без пауз'),
      contentPadding: EdgeInsets.zero,
      activeColor: const Color(0xFF1A3F8F),
    );
  }

  Widget _buildYandexAuthContent() {
    // Reusing children logic from _buildYandexAuthCard
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final auth = widget.controller.yandexAuthState;
        final busy = widget.controller.isAutomationActionInProgress;
        final hasAppPassword = widget.controller.hasSmtpAppPassword;
        final selfEmail = auth.smtpIdentity.trim().isNotEmpty ? auth.smtpIdentity.trim() : auth.email.trim();
        final smtpReady = auth.smtpReady;
        final selfTestError = widget.controller.errorMessage?.trim();
        final hasSelfTestError = selfTestError != null && selfTestError.isNotEmpty;
        final selfTestSucceeded = widget.controller.smtpSelfTestSucceeded;
        final selfTestUpdatedAt = widget.controller.smtpSelfTestUpdatedAt;
        final selfTestUpdatedAtText = selfTestUpdatedAt == null ? '' : DateFormat('dd.MM HH:mm').format(selfTestUpdatedAt);
        final hasTypedPassword = _appPasswordController.text.trim().isNotEmpty;
        final canSaveAndRun = auth.authorized && !busy && selfEmail.isNotEmpty && (hasTypedPassword || hasAppPassword);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AuthStatusRow(authorized: auth.authorized, displayName: auth.authorized ? auth.displayName : null),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: FilledButton.icon(onPressed: busy ? null : _loginYandex, icon: const Icon(Icons.login), label: const Text('Войти'))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(onPressed: (!auth.authorized || busy) ? null : _logoutYandex, icon: const Icon(Icons.logout), label: const Text('Выйти'))),
              ],
            ),
            if (selfEmail.isNotEmpty) ...[
              const SizedBox(height: 10),
              _InfoTile(icon: Icons.send, label: 'Email', value: selfEmail),
            ],
            const Divider(height: 24),
            const Text('Пароль приложения', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (hasAppPassword && !_editingAppPassword)
              _PasswordSavedBadge(onClear: busy ? null : _clearSmtpAppPassword)
            else ...[
              TextField(
                controller: _appPasswordController,
                obscureText: true,
                decoration: InputDecoration(hintText: 'abcd fgih jklm nopq', prefixIcon: const Icon(Icons.vpn_key)),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 6),
              const Text('16-значный пароль из Яндекс ID.', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
            const SizedBox(height: 12),
            if (busy) const _SmtpTestingIndicator()
            else FilledButton(onPressed: canSaveAndRun ? _saveAndRunSelfTest : null, child: const Text('Проверить доступ')),
            if (hasSelfTestError || selfTestSucceeded == true) ...[
              const SizedBox(height: 12),
              _SmtpResultBanner(success: selfTestSucceeded == true, message: hasSelfTestError ? selfTestError! : 'Доступ подтвержден', updatedAt: selfTestUpdatedAtText),
            ],
            if (hasSelfTestError) ...[
              const SizedBox(height: 10),
              const _SmtpTroubleshootingHint(),
            ],
          ],
        );
      },
    );
  }

  String _photoSourceLabel(PhotoPickSource source) {
    switch (source) {
      case PhotoPickSource.auto: return 'Системный';
      case PhotoPickSource.gallery: return 'Галерея';
      case PhotoPickSource.files: return 'Файлы';
    }
  }
}

