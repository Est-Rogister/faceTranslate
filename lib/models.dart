enum PartySide {
  a,
  b;

  PartySide get other => this == PartySide.a ? PartySide.b : PartySide.a;
  String get letter => name.toUpperCase();
}

class LanguageOption {
  const LanguageOption({
    required this.code,
    required this.nativeName,
    required this.englishName,
  });

  final String code;
  final String nativeName;
  final String englishName;

  bool get isChinese => code == 'zh-CN';

  String get modelCode => code.split('-').first;

  static const chinese = LanguageOption(
    code: 'zh-CN',
    nativeName: '中文',
    englishName: 'Chinese',
  );
  static const english = LanguageOption(
    code: 'en-US',
    nativeName: 'English',
    englishName: 'English',
  );

  static const values = [
    chinese,
    english,
    LanguageOption(code: 'ja-JP', nativeName: '日本語', englishName: 'Japanese'),
    LanguageOption(code: 'ko-KR', nativeName: '한국어', englishName: 'Korean'),
    LanguageOption(
      code: 'fr-FR',
      nativeName: 'Français',
      englishName: 'French',
    ),
    LanguageOption(
      code: 'es-ES',
      nativeName: 'Español',
      englishName: 'Spanish',
    ),
  ];

  static LanguageOption? fromCode(String? code) {
    for (final language in values) {
      if (language.code == code) return language;
    }
    return null;
  }
}

class SpeechSample {
  const SpeechSample({
    required this.source,
    required this.translationZh,
    required this.translationEn,
  });

  final String source;
  final String translationZh;
  final String translationEn;

  static const byLanguage = <String, SpeechSample>{
    'zh-CN': SpeechSample(
      source: '请问，附近的地铁站怎么走？',
      translationZh: '请问，附近的地铁站怎么走？',
      translationEn: 'Excuse me, how do I get to the nearest subway station?',
    ),
    'en-US': SpeechSample(
      source: 'Could you recommend a nearby place for dinner?',
      translationZh: '你能推荐一家附近适合吃晚餐的地方吗？',
      translationEn: 'Could you recommend a nearby place for dinner?',
    ),
    'ja-JP': SpeechSample(
      source: '駅はどこにありますか？',
      translationZh: '请问车站在哪里？',
      translationEn: 'Where is the station, please?',
    ),
    'ko-KR': SpeechSample(
      source: '이 근처에 카페가 있나요?',
      translationZh: '这附近有咖啡馆吗？',
      translationEn: 'Is there a cafe nearby?',
    ),
    'fr-FR': SpeechSample(
      source: 'Où se trouve la gare, s’il vous plaît ?',
      translationZh: '请问火车站在哪里？',
      translationEn: 'Where is the train station, please?',
    ),
    'es-ES': SpeechSample(
      source: '¿Puede ayudarme a encontrar este lugar?',
      translationZh: '你能帮我找到这个地方吗？',
      translationEn: 'Could you help me find this place?',
    ),
  };
}

class TranscriptMessage {
  const TranscriptMessage({
    required this.source,
    required this.translation,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.createdAt,
  });

  final String source;
  final String translation;
  final LanguageOption sourceLanguage;
  final LanguageOption targetLanguage;
  final DateTime createdAt;
}
