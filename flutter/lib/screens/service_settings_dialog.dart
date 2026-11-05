import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/live_translate_settings.dart';

Future<bool?> showServiceSettingsDialog({
  required BuildContext context,
  required LiveTranslateSettings settings,
}) => showDialog<bool>(
  context: context,
  builder: (context) => _ServiceSettingsDialog(settings: settings),
);

class _ServiceSettingsDialog extends StatefulWidget {
  const _ServiceSettingsDialog({required this.settings});

  final LiveTranslateSettings settings;

  @override
  State<_ServiceSettingsDialog> createState() => _ServiceSettingsDialogState();
}

class _ServiceSettingsDialogState extends State<_ServiceSettingsDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _apiKeyController;
  late final TextEditingController _customEndpointController;
  late final TextEditingController _translationTimeoutController;
  late bool _voiceCloneEnabled;
  late RecordingButtonMode _recordingButtonMode;
  bool _obscureApiKey = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController(text: widget.settings.apiKey);
    _customEndpointController = TextEditingController(
      text: widget.settings.customEndpoint,
    );
    _translationTimeoutController = TextEditingController(
      text: widget.settings.translationTimeoutSeconds.toString(),
    );
    _voiceCloneEnabled = widget.settings.voiceCloneEnabled;
    _recordingButtonMode = widget.settings.recordingButtonMode;
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _customEndpointController.dispose();
    _translationTimeoutController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.settings.save(
        apiKey: _apiKeyController.text,
        customEndpoint: _customEndpointController.text,
        voiceCloneEnabled: _voiceCloneEnabled,
        translationTimeoutSeconds: int.parse(
          _translationTimeoutController.text,
        ),
        recordingButtonMode: _recordingButtonMode,
      );
      if (mounted) Navigator.pop(context, true);
    } on FormatException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('配置保存失败，请重试')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      title: Row(
        children: [
          Icon(Icons.tune_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '翻译服务设置',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: '关闭',
            onPressed: _saving ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const ValueKey('api-key-field'),
                  controller: _apiKeyController,
                  obscureText: _obscureApiKey,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: 'sk-...',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.key_rounded),
                    suffixIcon: IconButton(
                      tooltip: _obscureApiKey ? '显示 API Key' : '隐藏 API Key',
                      onPressed: () =>
                          setState(() => _obscureApiKey = !_obscureApiKey),
                      icon: Icon(
                        _obscureApiKey
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? '请输入 API Key'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('custom-endpoint-field'),
                  controller: _customEndpointController,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: '实时 WebSocket 地址',
                    hintText: 'wss://.../api-ws/v1/realtime',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.cloud_outlined),
                  ),
                  validator: (value) =>
                      LiveTranslateSettings.validateEndpoint(value ?? ''),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const ValueKey('translation-timeout-field'),
                  controller: _translationTimeoutController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '翻译超时时间',
                    hintText: '20',
                    suffixText: '秒',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.timer_outlined),
                  ),
                  validator: (value) =>
                      LiveTranslateSettings.validateTranslationTimeout(
                        value ?? '',
                      ),
                ),
                const SizedBox(height: 8),
                Text('麦克风按钮模式', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<RecordingButtonMode>(
                  key: const ValueKey('recording-button-mode'),
                  segments: const [
                    ButtonSegment(
                      value: RecordingButtonMode.tap,
                      icon: Icon(Icons.touch_app_rounded),
                      label: Text('点击启停'),
                    ),
                    ButtonSegment(
                      value: RecordingButtonMode.hold,
                      icon: Icon(Icons.pan_tool_alt_rounded),
                      label: Text('按住说话'),
                    ),
                  ],
                  selected: {_recordingButtonMode},
                  onSelectionChanged: _saving
                      ? null
                      : (selection) {
                          setState(() {
                            _recordingButtonMode = selection.single;
                          });
                        },
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  key: const ValueKey('voice-clone-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('复刻说话人音色'),
                  subtitle: const Text('让翻译语音保留当前说话人的音色'),
                  value: _voiceCloneEnabled,
                  onChanged: _saving
                      ? null
                      : (enabled) {
                          setState(() => _voiceCloneEnabled = enabled);
                        },
                ),
                const SizedBox(height: 12),
                Text(
                  'API Key 将加密保存在当前设备，仅用于连接阿里云实时翻译服务。',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined, size: 19),
          label: const Text('保存'),
        ),
      ],
    );
  }
}
