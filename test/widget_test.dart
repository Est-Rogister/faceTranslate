import 'dart:async';
import 'dart:typed_data';

import 'package:facetranslate/app.dart';
import 'package:facetranslate/models.dart';
import 'package:facetranslate/services/conversation_history_store.dart';
import 'package:facetranslate/services/live_translate_service.dart';
import 'package:facetranslate/services/live_translate_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds a qwen 3.8 realtime voice clone session update', () {
    final event = buildLiveTranslateSessionUpdate(
      targetLanguage: 'ko',
      voiceCloneEnabled: true,
    );
    final session = event['session'] as Map<String, dynamic>;

    expect(event['type'], 'session.update');
    expect(session['output_modalities'], ['text', 'audio']);
    expect(session.containsKey('modalities'), isFalse);
    expect(session['voice'], 'default');
    expect(session['enable_voice_clone'], isTrue);
    expect(session['voice_clone_options'], {'frequency': 'once'});
    expect(session['translation'], {'language': 'ko'});
  });

  test('validates the server voice clone session response', () {
    final error = validateVoiceCloneSessionUpdate({
      'session': {
        'voice': 'default',
        'enable_voice_clone': true,
        'voice_clone_options': {'frequency': 'once'},
      },
    });

    expect(error, isNull);
  });

  test('leaves the realtime WebSocket endpoint empty by default', () {
    final settings = LiveTranslateSettings(store: _MemorySettingsStore());

    expect(settings.customEndpoint, isEmpty);
    expect(settings.endpoint, isNull);
    expect(settings.translationTimeoutSeconds, 20);
    expect(settings.recordingButtonMode, RecordingButtonMode.tap);
    expect(settings.isConfigured, isFalse);
  });

  test('validates the configurable translation timeout range', () {
    expect(LiveTranslateSettings.validateTranslationTimeout('5'), isNull);
    expect(LiveTranslateSettings.validateTranslationTimeout('120'), isNull);
    expect(LiveTranslateSettings.validateTranslationTimeout('4'), isNotNull);
    expect(LiveTranslateSettings.validateTranslationTimeout('121'), isNotNull);
    expect(LiveTranslateSettings.validateTranslationTimeout(''), isNotNull);
  });

  testWidgets('starts on language setup and opens the permission dialog', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());

    expect(find.text('先选双方语言'), findsOneWidget);
    expect(find.text('开始对话'), findsOneWidget);

    await tester.tap(find.text('开始对话'));
    await tester.pumpAndSettle();

    expect(find.text('允许使用麦克风'), findsOneWidget);
    expect(find.text('暂不允许'), findsOneWidget);
    expect(find.text('允许'), findsOneWidget);
  });

  testWidgets('enters the face-to-face conversation after permission', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());

    await tester.tap(find.text('开始对话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('允许'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('microphone-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('microphone-b')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('conversation-language-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('conversation-language-b')),
      findsOneWidget,
    );
  });

  testWidgets('playing indicator does not overflow', (tester) async {
    await tester.pumpWidget(_buildTestApp());

    await tester.tap(find.text('开始对话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('允许'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final microphone = find.byKey(const ValueKey('microphone-b'));
    await tester.tap(microphone);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.textContaining('正在录音'), findsOneWidget);
    await tester.tap(microphone);
    await tester.pump();

    expect(find.text('Playing translation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reuses one translation client for repeated turns on one side', (
    tester,
  ) async {
    var createdClients = 0;
    await tester.pumpWidget(
      FaceTranslateApp(
        translationClientFactory: () {
          createdClients++;
          return _FakeTranslationClient();
        },
        audioPlayerFactory: _FakeAudioPlayer.new,
        historyStore: _MemoryHistoryStore(),
      ),
    );
    await tester.tap(find.text('开始对话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('允许'));
    await tester.pump(const Duration(milliseconds: 300));

    final microphone = find.byKey(const ValueKey('microphone-a'));
    await tester.tap(microphone);
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.tap(microphone);
    await tester.pump();
    expect(createdClients, 1);

    await tester.tap(microphone);
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.tap(microphone);
    await tester.pump();
    expect(createdClients, 1);
  });

  testWidgets('opens and saves translation service settings', (tester) async {
    final settings = LiveTranslateSettings(store: _MemorySettingsStore());
    await tester.pumpWidget(_buildTestApp(settings: settings));

    await tester.tap(find.byKey(const ValueKey('setup-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('翻译服务设置'));
    await tester.pumpAndSettle();

    expect(find.text('API Key'), findsOneWidget);
    expect(find.text('实时 WebSocket 地址'), findsOneWidget);
    expect(find.text('翻译超时时间'), findsOneWidget);
    expect(find.text('麦克风按钮模式'), findsOneWidget);
    expect(find.text('复刻说话人音色'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('api-key-field')),
      'sk-test-key',
    );
    await tester.enterText(
      find.byKey(const ValueKey('custom-endpoint-field')),
      'wss://custom.example.com/api-ws/v1/realtime',
    );
    await tester.enterText(
      find.byKey(const ValueKey('translation-timeout-field')),
      '12',
    );
    await tester.tap(find.text('按住说话'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(settings.apiKey, 'sk-test-key');
    expect(settings.endpoint?.host, 'custom.example.com');
    expect(settings.translationTimeoutSeconds, 12);
    expect(settings.recordingButtonMode, RecordingButtonMode.hold);
    expect(settings.voiceCloneEnabled, isTrue);
  });

  testWidgets('hold mode records while pressed and translates on release', (
    tester,
  ) async {
    final settings = LiveTranslateSettings(store: _MemorySettingsStore());
    await settings.save(
      apiKey: 'sk-test-key',
      customEndpoint: 'wss://custom.example.com/api-ws/v1/realtime',
      voiceCloneEnabled: true,
      translationTimeoutSeconds: 20,
      recordingButtonMode: RecordingButtonMode.hold,
    );
    await tester.pumpWidget(_buildTestApp(settings: settings));
    await tester.tap(find.text('开始对话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('允许'));
    await tester.pump(const Duration(milliseconds: 300));

    final microphone = find.byKey(const ValueKey('microphone-a'));
    final gesture = await tester.startGesture(tester.getCenter(microphone));
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.textContaining('正在录音'), findsOneWidget);
    await gesture.up();
    await tester.pump();

    expect(find.text('Playing translation'), findsOneWidget);
  });

  testWidgets('selecting the other side language swaps both sides', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.tap(find.text('开始对话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('允许'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final languageB = find.descendant(
      of: find.byKey(const ValueKey('conversation-language-b')),
      matching: find.byType(DropdownButton<LanguageOption>),
    );
    await tester.tap(languageB);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('中文').last);
    await tester.pump(const Duration(milliseconds: 300));

    final dropdownA = tester.widget<DropdownButton<LanguageOption>>(
      find.descendant(
        of: find.byKey(const ValueKey('conversation-language-a')),
        matching: find.byType(DropdownButton<LanguageOption>),
      ),
    );
    final dropdownB = tester.widget<DropdownButton<LanguageOption>>(
      find.descendant(
        of: find.byKey(const ValueKey('conversation-language-b')),
        matching: find.byType(DropdownButton<LanguageOption>),
      ),
    );
    expect(dropdownA.value, LanguageOption.english);
    expect(dropdownB.value, LanguageOption.chinese);
  });

  testWidgets('restores translation history after the app restarts', (
    tester,
  ) async {
    final historyStore = _MemoryHistoryStore(
      ConversationHistorySnapshot(
        languageA: LanguageOption.chinese,
        languageB: LanguageOption.values[3],
        messagesA: const [],
        messagesB: [
          TranscriptMessage(
            source: '你好，很高兴认识你。',
            translation: '안녕하세요, 만나서 반가워요.',
            sourceLanguage: LanguageOption.chinese,
            targetLanguage: LanguageOption.values[3],
            createdAt: DateTime(2026, 10, 14, 10, 30),
          ),
        ],
      ),
    );
    await tester.pumpWidget(_buildTestApp(historyStore: historyStore));
    await tester.pump();

    await tester.tap(find.text('开始对话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('允许'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('你好，很高兴认识你。'), findsOneWidget);
    expect(find.text('안녕하세요, 만나서 반가워요.'), findsOneWidget);
  });

  testWidgets('saves a completed translation immediately', (tester) async {
    final historyStore = _MemoryHistoryStore();
    await tester.pumpWidget(_buildTestApp(historyStore: historyStore));
    await tester.tap(find.text('开始对话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('允许'));
    await tester.pump(const Duration(milliseconds: 300));

    final microphone = find.byKey(const ValueKey('microphone-b'));
    await tester.tap(microphone);
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.tap(microphone);
    await tester.pump();

    expect(historyStore.snapshot.messagesA, hasLength(1));
    expect(
      historyStore.snapshot.messagesA.single.translation,
      'Excuse me, how do I get to the nearest subway station?',
    );
  });

  testWidgets('dragging the divider keeps a microphone in the collapsed side', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.tap(find.text('开始对话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('允许'));
    await tester.pump(const Duration(milliseconds: 300));

    final panelA = find.byKey(const ValueKey('party-panel-a'));
    final panelB = find.byKey(const ValueKey('party-panel-b'));
    final initialPanelAHeight = tester.getSize(panelA).height;

    await tester.drag(
      find.byKey(const ValueKey('conversation-divider-handle')),
      const Offset(0, 400),
    );
    await tester.pump();

    expect(tester.getSize(panelA).height, greaterThan(initialPanelAHeight));
    expect(tester.getSize(panelB).height, closeTo(108, 0.1));
    expect(find.byKey(const ValueKey('microphone-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('party-feed-b')), findsNothing);
    expect(find.byKey(const ValueKey('conversation-language-b')), findsNothing);
  });

  testWidgets('switches to compact mode before the panel can overflow', (
    tester,
  ) async {
    await tester.pumpWidget(_buildTestApp());
    await tester.tap(find.text('开始对话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('允许'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.drag(
      find.byKey(const ValueKey('conversation-divider-handle')),
      const Offset(0, 80),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('microphone-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('party-feed-b')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget _buildTestApp({
  LiveTranslateSettings? settings,
  ConversationHistoryStore? historyStore,
}) {
  return FaceTranslateApp(
    translationClientFactory: _FakeTranslationClient.new,
    audioPlayerFactory: _FakeAudioPlayer.new,
    settings: settings,
    historyStore: historyStore ?? _MemoryHistoryStore(),
  );
}

class _MemoryHistoryStore implements ConversationHistoryStore {
  _MemoryHistoryStore([
    this.snapshot = const ConversationHistorySnapshot.empty(),
  ]);

  ConversationHistorySnapshot snapshot;

  @override
  Future<ConversationHistorySnapshot> load() async => snapshot;

  @override
  Future<void> save(ConversationHistorySnapshot snapshot) async {
    this.snapshot = snapshot;
  }
}

class _MemorySettingsStore implements LiveTranslateSettingsStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _FakeTranslationClient implements TranslationClient {
  @override
  bool get isConfigured => true;

  @override
  Future<void> start({
    required String targetLanguage,
    required TextUpdateCallback onSourceText,
    required TextUpdateCallback onTranslationText,
  }) async {
    onSourceText('请问，附近的地铁站怎么走？');
    onTranslationText('Excuse me, how do I get to the nearest subway station?');
  }

  @override
  Future<LiveTranslation> stop() async {
    return LiveTranslation(
      sourceText: '请问，附近的地铁站怎么走？',
      translatedText: 'Excuse me, how do I get to the nearest subway station?',
      audioPcm: Uint8List.fromList([0, 0]),
    );
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

class _FakeAudioPlayer implements TranslationAudioPlayer {
  Completer<void>? _playback;

  @override
  Future<void> play(Uint8List pcmBytes) {
    _playback = Completer<void>();
    return _playback!.future;
  }

  @override
  Future<void> stop() async {
    if (_playback case final playback? when !playback.isCompleted) {
      playback.complete();
    }
  }

  @override
  Future<void> dispose() => stop();
}
