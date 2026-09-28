import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract final class LiveTranslateDefaults {
  static const model = 'qwen3.8-livetranslate-flash-realtime';
  static const apiKey = String.fromEnvironment('ALIYUN_DASHSCOPE_API_KEY');
  static const workspaceId = String.fromEnvironment(
    'ALIYUN_DASHSCOPE_WORKSPACE_ID',
    defaultValue: 'llm-hwbr9urj522b3vx3',
  );
  static const region = String.fromEnvironment(
    'ALIYUN_DASHSCOPE_REGION',
    defaultValue: 'cn-beijing',
  );
  static const endpointOverride = String.fromEnvironment(
    'ALIYUN_DASHSCOPE_ENDPOINT',
  );
}

abstract interface class LiveTranslateSettingsStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

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
  static const _defaultEndpoint =
      'wss://${LiveTranslateDefaults.workspaceId}.cn-beijing.maas.aliyuncs.com/api-ws/v1/realtime';

  final LiveTranslateSettingsStore _store;
  String _apiKey = LiveTranslateDefaults.apiKey;
  String _customEndpoint = LiveTranslateDefaults.endpointOverride.isEmpty
      ? _defaultEndpoint
      : LiveTranslateDefaults.endpointOverride;
  bool _voiceCloneEnabled = true;

  String get apiKey => _apiKey.trim();
  String get customEndpoint => _customEndpoint;
  bool get voiceCloneEnabled => _voiceCloneEnabled;

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

    if (savedApiKey != null && savedApiKey.trim().isNotEmpty) {
      _apiKey = savedApiKey;
    }
    if (savedCustomEndpoint != null && savedCustomEndpoint.trim().isNotEmpty) {
      _customEndpoint = savedCustomEndpoint;
    }
    if (savedVoiceCloneEnabled != null) {
      _voiceCloneEnabled = savedVoiceCloneEnabled == 'true';
    }
    notifyListeners();
  }

  Future<void> save({
    required String apiKey,
    required String customEndpoint,
    required bool voiceCloneEnabled,
  }) async {
    final normalizedApiKey = apiKey.trim();
    if (normalizedApiKey.isEmpty) {
      throw const FormatException('请输入 API Key');
    }
    final selectedEndpoint = customEndpoint.trim();
    final endpointError = validateEndpoint(selectedEndpoint);
    if (endpointError != null) throw FormatException(endpointError);

    await _store.write(_apiKeyStorageKey, normalizedApiKey);
    await _store.write(_customEndpointStorageKey, selectedEndpoint);
    await _store.write(
      _voiceCloneEnabledStorageKey,
      voiceCloneEnabled.toString(),
    );
    _apiKey = normalizedApiKey;
    _customEndpoint = selectedEndpoint;
    _voiceCloneEnabled = voiceCloneEnabled;
    notifyListeners();
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
