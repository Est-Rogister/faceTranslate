import 'dart:async';
import 'dart:typed_data';

import 'package:facetranslate/app.dart';
import 'package:facetranslate/models.dart';
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
    final gesture = await tester.startGesture(tester.getCenter(microphone));
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.textContaining('正在录音'), findsOneWidget);
    await gesture.up();
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
      ),
    );
    await tester.tap(find.text('开始对话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('允许'));
    await tester.pump(const Duration(milliseconds: 300));

    final microphone = find.byKey(const ValueKey('microphone-a'));
    var gesture = await tester.startGesture(tester.getCenter(microphone));
    await tester.pump(const Duration(milliseconds: 1100));
    await gesture.up();
    await tester.pump();
    expect(createdClients, 1);

    gesture = await tester.startGesture(tester.getCenter(microphone));
    await tester.pump(const Duration(milliseconds: 1100));
    await gesture.up();
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
    expect(find.text('复刻说话人音色'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('api-key-field')),
      'sk-test-key',
    );
    await tester.enterText(
      find.byKey(const ValueKey('custom-endpoint-field')),
      'wss://custom.example.com/api-ws/v1/realtime',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(settings.apiKey, 'sk-test-key');
    expect(settings.endpoint?.host, 'custom.example.com');
    expect(settings.voiceCloneEnabled, isTrue);
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
}

Widget _buildTestApp({LiveTranslateSettings? settings}) {
  return FaceTranslateApp(
    translationClientFactory: _FakeTranslationClient.new,
    audioPlayerFactory: _FakeAudioPlayer.new,
    settings: settings,
  );
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
