import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract final class LiveTranslateDefaults {
  static const model = 'qwen3.8-livetranslate-flash-realtime';
  static const apiKey = String.fromEnvironment('ALIYUN_DASHSCOPE_API_KEY');
  static const endpointOverride = String.fromEnvironment(
    'ALIYUN_DASHSCOPE_ENDPOINT',
  );
}

abstract interface class LiveTranslateSettingsStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

enum RecordingButtonMode { tap, hold }

class SecureLiveTranslateSettingsStore implements LiveTranslateSettingsStore {
  const SecureLiveTranslateSettingsStore();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

class LiveTranslateSettings extends ChangeNotifier {
  LiveTranslateSettings({LiveTranslateSettingsStore? store})
    : _store = store ?? const SecureLiveTranslateSettingsStore();

  static final instance = LiveTranslateSettings();

  static const _apiKeyStorageKey = 'aliyun_api_key';
  static const _customEndpointStorageKey = 'aliyun_custom_endpoint';
  static const _voiceCloneEnabledStorageKey = 'aliyun_voice_clone_enabled';
  static const _translationTimeoutStorageKey = 'translation_timeout_seconds';
  static const _recordingButtonModeStorageKey = 'recording_button_mode';
  static const defaultTranslationTimeoutSeconds = 20;
  static const minimumTranslationTimeoutSeconds = 5;
  static const maximumTranslationTimeoutSeconds = 120;

  final LiveTranslateSettingsStore _store;
  String _apiKey = LiveTranslateDefaults.apiKey;
  String _customEndpoint = LiveTranslateDefaults.endpointOverride;
  bool _voiceCloneEnabled = true;
  int _translationTimeoutSeconds = defaultTranslationTimeoutSeconds;
  RecordingButtonMode _recordingButtonMode = RecordingButtonMode.tap;

  String get apiKey => _apiKey.trim();
  String get customEndpoint => _customEndpoint;
  bool get voiceCloneEnabled => _voiceCloneEnabled;
  int get translationTimeoutSeconds => _translationTimeoutSeconds;
  RecordingButtonMode get recordingButtonMode => _recordingButtonMode;

  String get endpointValue => _customEndpoint.trim();

  Uri? get endpoint {
    final validationError = validateEndpoint(endpointValue);
    if (validationError != null) return null;
    final uri = Uri.parse(endpointValue);
    return uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        'model': LiveTranslateDefaults.model,
      },
    );
  }

  bool get isConfigured => apiKey.isNotEmpty && endpoint != null;

  Future<void> load() async {
    final savedApiKey = await _store.read(_apiKeyStorageKey);
    final savedCustomEndpoint = await _store.read(_customEndpointStorageKey);
    final savedVoiceCloneEnabled = await _store.read(
      _voiceCloneEnabledStorageKey,
    );
    final savedTranslationTimeout = await _store.read(
      _translationTimeoutStorageKey,
    );
    final savedRecordingButtonMode = await _store.read(
      _recordingButtonModeStorageKey,
    );

    if (savedApiKey != null && savedApiKey.trim().isNotEmpty) {
      _apiKey = savedApiKey;
    }
    if (savedCustomEndpoint != null && savedCustomEndpoint.trim().isNotEmpty) {
      _customEndpoint = savedCustomEndpoint;
    }
    if (savedVoiceCloneEnabled != null) {
      _voiceCloneEnabled = savedVoiceCloneEnabled == 'true';
    }
    final parsedTranslationTimeout = int.tryParse(
      savedTranslationTimeout ?? '',
    );
    if (parsedTranslationTimeout != null &&
        isValidTranslationTimeout(parsedTranslationTimeout)) {
      _translationTimeoutSeconds = parsedTranslationTimeout;
    }
    _recordingButtonMode = RecordingButtonMode.values.firstWhere(
      (mode) => mode.name == savedRecordingButtonMode,
      orElse: () => RecordingButtonMode.tap,
    );
    notifyListeners();
  }

  Future<void> save({
    required String apiKey,
    required String customEndpoint,
    required bool voiceCloneEnabled,
    required int translationTimeoutSeconds,
    required RecordingButtonMode recordingButtonMode,
  }) async {
    final normalizedApiKey = apiKey.trim();
    if (normalizedApiKey.isEmpty) {
      throw const FormatException('请输入 API Key');
    }
    final selectedEndpoint = customEndpoint.trim();
    final endpointError = validateEndpoint(selectedEndpoint);
    if (endpointError != null) throw FormatException(endpointError);
    if (!isValidTranslationTimeout(translationTimeoutSeconds)) {
      throw const FormatException('翻译超时时间必须在 5–120 秒之间');
    }

    await _store.write(_apiKeyStorageKey, normalizedApiKey);
    await _store.write(_customEndpointStorageKey, selectedEndpoint);
    await _store.write(
      _voiceCloneEnabledStorageKey,
      voiceCloneEnabled.toString(),
    );
    await _store.write(
      _translationTimeoutStorageKey,
      translationTimeoutSeconds.toString(),
    );
    await _store.write(_recordingButtonModeStorageKey, recordingButtonMode.name);
    _apiKey = normalizedApiKey;
    _customEndpoint = selectedEndpoint;
    _voiceCloneEnabled = voiceCloneEnabled;
    _translationTimeoutSeconds = translationTimeoutSeconds;
    _recordingButtonMode = recordingButtonMode;
    notifyListeners();
  }

  static bool isValidTranslationTimeout(int value) =>
      value >= minimumTranslationTimeoutSeconds &&
      value <= maximumTranslationTimeoutSeconds;

  static String? validateTranslationTimeout(String value) {
    final seconds = int.tryParse(value.trim());
    if (seconds == null || !isValidTranslationTimeout(seconds)) {
      return '请输入 5–120 秒';
    }
    return null;
  }

  static String? validateEndpoint(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'wss' || uri.host.isEmpty) {
      return '请输入有效的 wss:// 实时翻译地址';
    }
    if (!uri.path.endsWith('/api-ws/v1/realtime')) {
      return '地址路径必须以 /api-ws/v1/realtime 结尾';
    }
    return null;
  }
}
