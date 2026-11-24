import 'package:flutter/material.dart';

import '../../../../core/config/app_theme.dart';
import '../../../../core/ui/pixel_widgets.dart';
import '../../domain/entities/vocab_card.dart';

class CardEditFormResult {
  final String word;
  final String partOfSpeech;
  final String phoneticUs;
  final String phoneticUk;
  final String translation;
  final String contextSentence;

  const CardEditFormResult({
    required this.word,
    required this.partOfSpeech,
    required this.phoneticUs,
    required this.phoneticUk,
    required this.translation,
    required this.contextSentence,
  });
}

Future<CardEditFormResult?> showPixelEditCardDialog(
  BuildContext context,
  VocabCard card,
) {
  return showDialog<CardEditFormResult>(
    context: context,
    builder: (_) => _PixelEditCardDialog(card: card),
  );
}

Future<bool> showPixelDeleteConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final px = PixelColors.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      child: PixelCard(
        backgroundColor: px.surface,
        borderColor: px.coral,
        borderWidth: 3,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PixelSectionHeader(
                title: title,
                icon: Icons.delete_forever_rounded,
                accentColor: px.coral,
              ),
              const SizedBox(height: 12),
              Text(message),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  PixelButton(
                    label: 'HỦY',
                    backgroundColor: px.surfaceAlt,
                    foregroundColor: px.ink,
                    onPressed: () => Navigator.of(ctx).pop(false),
                  ),
                  const SizedBox(width: 10),
                  PixelButton(
                    label: 'XÓA NGAY',
                    icon: Icons.delete_outline,
                    backgroundColor: px.coral,
                    onPressed: () => Navigator.of(ctx).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return confirmed == true;
}

class _PixelEditCardDialog extends StatefulWidget {
  final VocabCard card;

  const _PixelEditCardDialog({required this.card});

  @override
  State<_PixelEditCardDialog> createState() => _PixelEditCardDialogState();
}

class _PixelEditCardDialogState extends State<_PixelEditCardDialog> {
  static const _commonPos = ['noun', 'verb', 'adj', 'adv', 'phrase', 'vocab'];

  late final TextEditingController _wordCtrl;
  late final TextEditingController _posCtrl;
  late final TextEditingController _usCtrl;
  late final TextEditingController _ukCtrl;
  late final TextEditingController _transCtrl;
  late final TextEditingController _sentenceCtrl;

  @override
  void initState() {
    super.initState();
    _wordCtrl = TextEditingController(text: widget.card.word);
    _posCtrl = TextEditingController(text: widget.card.partOfSpeech);
    _usCtrl = TextEditingController(text: widget.card.effectivePhoneticUs);
    _ukCtrl = TextEditingController(text: widget.card.phoneticUk);
    _transCtrl = TextEditingController(text: widget.card.translation);
    _sentenceCtrl = TextEditingController(text: widget.card.contextSentence);
  }

  @override
  void dispose() {
    _wordCtrl.dispose();
    _posCtrl.dispose();
    _usCtrl.dispose();
    _ukCtrl.dispose();
    _transCtrl.dispose();
    _sentenceCtrl.dispose();
    super.dispose();
  }

  void _save() {
    if (_wordCtrl.text.trim().isEmpty || _transCtrl.text.trim().isEmpty) {
      return;
    }
    Navigator.of(context).pop(
      CardEditFormResult(
        word: _wordCtrl.text.trim(),
        partOfSpeech: _posCtrl.text.trim(),
        phoneticUs: _usCtrl.text.trim(),
        phoneticUk: _ukCtrl.text.trim(),
        translation: _transCtrl.text.trim(),
        contextSentence: _sentenceCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final px = PixelColors.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: PixelCard(
        backgroundColor: px.surface,
        borderColor: px.primary,
        borderWidth: 3,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PixelSectionHeader(
                  title: 'CHỈNH SỬA THẺ & POS',
                  icon: Icons.edit_note_rounded,
                  accentColor: px.primary,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _wordCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Từ vựng (Word)',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _posCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Loại từ (POS: noun, verb, adj, adv...)',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _commonPos.map((pos) {
                    final active =
                        _posCtrl.text.trim().toLowerCase() == pos;
                    return PixelBadge(
                      label: pos.toUpperCase(),
                      backgroundColor: active ? px.primary : px.surfaceAlt,
                      foregroundColor: active ? Colors.white : px.ink,
                      onTap: () => setState(() => _posCtrl.text = pos),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _usCtrl,
                        decoration: const InputDecoration(
                          labelText: 'IPA US',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _ukCtrl,
                        decoration: const InputDecoration(
                          labelText: 'IPA UK',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _transCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Nghĩa Tiếng Việt',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _sentenceCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Câu ví dụ (tự động tạo Cloze)',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    PixelButton(
                      label: 'HỦY',
                      backgroundColor: px.surfaceAlt,
                      foregroundColor: px.ink,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 10),
                    PixelButton(
                      label: 'LƯU THAY ĐỔI',
                      icon: Icons.save_rounded,
                      backgroundColor: px.emerald,
                      onPressed: _save,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
