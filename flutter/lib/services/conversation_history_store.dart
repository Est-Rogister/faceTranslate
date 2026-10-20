import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models.dart';

class ConversationHistorySnapshot {
  const ConversationHistorySnapshot({
    required this.languageA,
    required this.languageB,
    required this.messagesA,
    required this.messagesB,
  });

  const ConversationHistorySnapshot.empty()
    : languageA = LanguageOption.chinese,
      languageB = LanguageOption.english,
      messagesA = const [],
      messagesB = const [];

  final LanguageOption languageA;
  final LanguageOption languageB;
  final List<TranscriptMessage> messagesA;
  final List<TranscriptMessage> messagesB;

  Map<String, dynamic> toJson() => {
    'version': 1,
    'languageA': languageA.code,
    'languageB': languageB.code,
    'messagesA': messagesA.map(_messageToJson).toList(),
    'messagesB': messagesB.map(_messageToJson).toList(),
  };

  static ConversationHistorySnapshot fromJson(Map<String, dynamic> json) {
    return ConversationHistorySnapshot(
      languageA:
          LanguageOption.fromCode(json['languageA'] as String?) ??
          LanguageOption.chinese,
      languageB:
          LanguageOption.fromCode(json['languageB'] as String?) ??
          LanguageOption.english,
      messagesA: _messagesFromJson(json['messagesA']),
      messagesB: _messagesFromJson(json['messagesB']),
    );
  }

  static Map<String, dynamic> _messageToJson(TranscriptMessage message) => {
    'source': message.source,
    'translation': message.translation,
    'sourceLanguage': message.sourceLanguage.code,
    'targetLanguage': message.targetLanguage.code,
    'createdAt': message.createdAt.toIso8601String(),
  };

  static List<TranscriptMessage> _messagesFromJson(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value
        .whereType<Map>()
        .map((entry) => _messageFromJson(Map<String, dynamic>.from(entry)))
        .whereType<TranscriptMessage>()
        .toList(growable: false);
  }

  static TranscriptMessage? _messageFromJson(Map<String, dynamic> json) {
    final source = json['source'];
    final translation = json['translation'];
    final sourceLanguage = LanguageOption.fromCode(
      json['sourceLanguage'] as String?,
    );
    final targetLanguage = LanguageOption.fromCode(
      json['targetLanguage'] as String?,
    );
    final createdAt = DateTime.tryParse(json['createdAt'] as String? ?? '');
    if (source is! String ||
        translation is! String ||
        sourceLanguage == null ||
        targetLanguage == null ||
        createdAt == null) {
      return null;
    }
    return TranscriptMessage(
      source: source,
      translation: translation,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      createdAt: createdAt,
    );
  }
}

abstract interface class ConversationHistoryStore {
  Future<ConversationHistorySnapshot> load();

  Future<void> save(ConversationHistorySnapshot snapshot);
}

class FileConversationHistoryStore implements ConversationHistoryStore {
  Future<void> _writeQueue = Future.value();

  @override
  Future<ConversationHistorySnapshot> load() async {
    try {
      final file = await _historyFile();
      if (!await file.exists()) {
        return const ConversationHistorySnapshot.empty();
      }
      final json = jsonDecode(await file.readAsString());
      if (json is! Map) {
        return const ConversationHistorySnapshot.empty();
      }
      return ConversationHistorySnapshot.fromJson(
        Map<String, dynamic>.from(json),
      );
    } catch (_) {
      return const ConversationHistorySnapshot.empty();
    }
  }

  @override
  Future<void> save(ConversationHistorySnapshot snapshot) {
    return _enqueueWrite(() async {
      final file = await _historyFile();
      await file.parent.create(recursive: true);
      final temporaryFile = File('${file.path}.tmp');
      await temporaryFile.writeAsString(
        jsonEncode(snapshot.toJson()),
        flush: true,
      );
      await temporaryFile.rename(file.path);
    });
  }

  Future<File> _historyFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/conversation_history.json');
  }

  Future<void> _enqueueWrite(Future<void> Function() operation) {
    final next = _writeQueue.then(
      (_) => operation(),
      onError: (_) => operation(),
    );
    _writeQueue = next;
    return next;
  }
}
