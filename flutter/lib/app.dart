import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'screens/home_shell.dart';
import 'services/live_translate_service.dart';
import 'services/live_translate_settings.dart';

class FaceTranslateApp extends StatelessWidget {
  const FaceTranslateApp({
    this.translationClientFactory,
    this.audioPlayerFactory,
    this.settings,
    super.key,
  });

  final TranslationClientFactory? translationClientFactory;
  final TranslationAudioPlayerFactory? audioPlayerFactory;
  final LiveTranslateSettings? settings;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '同声',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: HomeShell(
        translationClientFactory: translationClientFactory,
        audioPlayerFactory: audioPlayerFactory,
        settings: settings,
      ),
    );
  }
}
