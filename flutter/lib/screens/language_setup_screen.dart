import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models.dart';

class LanguageSetupScreen extends StatelessWidget {
  const LanguageSetupScreen({
    required this.languageA,
    required this.languageB,
    required this.onLanguagesChanged,
    required this.onStart,
    required this.onOpenSettings,
    this.errorText,
    super.key,
  });

  final LanguageOption languageA;
  final LanguageOption languageB;
  final String? errorText;
  final void Function(LanguageOption languageA, LanguageOption languageB)
  onLanguagesChanged;
  final VoidCallback onStart;
  final VoidCallback onOpenSettings;

  void _selectLanguageA(LanguageOption language) {
    if (language.code == languageB.code) {
      onLanguagesChanged(languageB, languageA);
    } else {
      onLanguagesChanged(language, languageB);
    }
  }

  void _selectLanguageB(LanguageOption language) {
    if (language.code == languageA.code) {
      onLanguagesChanged(languageB, languageA);
    } else {
      onLanguagesChanged(languageA, language);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sameLanguage = languageA.code == languageB.code;
    final visibleError = sameLanguage ? '请选择两种不同的语言' : errorText;

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 44),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(
                          Icons.swap_horiz_rounded,
                          color: Colors.white,
                          size: 23,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        '同声',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      PopupMenuButton<_SetupMenuAction>(
                        key: const ValueKey('setup-menu'),
                        tooltip: '更多设置',
                        icon: const Icon(Icons.more_vert_rounded),
                        onSelected: (action) {
                          if (action == _SetupMenuAction.serviceSettings) {
                            onOpenSettings();
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: _SetupMenuAction.serviceSettings,
                            child: Row(
                              children: [
                                Icon(Icons.tune_rounded, size: 20),
                                SizedBox(width: 10),
                                Text('翻译服务设置'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '先选双方语言',
                    style: TextStyle(
                      fontSize: 28,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '将手机放在两人之间，选择各自使用的语言后开始面对面对话。',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 16,
                      height: 1.6,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(height: 24),
                  _LanguageCard(
                    side: 'A',
                    label: '对面用户的语言',
                    value: languageA,
                    color: theme.colorScheme.primary,
                    background: AppTone.primarySoft(context),
                    onChanged: _selectLanguageA,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Divider(color: theme.colorScheme.outline),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () =>
                            onLanguagesChanged(languageB, languageA),
                        icon: const Icon(Icons.swap_horiz_rounded, size: 19),
                        label: const Text('交换语言'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(112, 44),
                          side: BorderSide(color: theme.colorScheme.outline),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Divider(color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _LanguageCard(
                    side: 'B',
                    label: '这边用户的语言',
                    value: languageB,
                    color: AppTone.success(context),
                    background: AppTone.successSoft(context),
                    onChanged: _selectLanguageB,
                  ),
                  const Spacer(),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 22,
                    child: Center(
                      child: Text(
                        visibleError ?? '',
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton(
                    onPressed: sameLanguage ? null : onStart,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                      elevation: 3,
                      shadowColor: theme.colorScheme.primary.withValues(
                        alpha: 0.28,
                      ),
                    ),
                    child: const Text('开始对话'),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '语言可在对话中随时返回修改',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _SetupMenuAction { serviceSettings }

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({
    required this.side,
    required this.label,
    required this.value,
    required this.color,
    required this.background,
    required this.onChanged,
  });

  final String side;
  final String label;
  final LanguageOption value;
  final Color color;
  final Color background;
  final ValueChanged<LanguageOption> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2A2D50).withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
            ),
            child: Text(
              side,
              style: TextStyle(
                color: color,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                DropdownButtonHideUnderline(
                  child: DropdownButton<LanguageOption>(
                    value: value,
                    isExpanded: true,
                    isDense: true,
                    borderRadius: BorderRadius.circular(12),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                    items: LanguageOption.values
                        .map(
                          (language) => DropdownMenuItem(
                            value: language,
                            child: Text(language.nativeName),
                          ),
                        )
                        .toList(),
                    onChanged: (language) {
                      if (language != null) onChanged(language);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
