import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/live_translation_service.dart';

/// Reusable widget that automatically translates dynamic user text (Crop names, descriptions, bios, locations)
/// into the currently active AppState language in real-time.
class TranslatedText extends StatefulWidget {
  final String text;
  final String? preTranslatedHi;
  final String? preTranslatedEn;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool bilingual; // e.g. "ताज़ा गेहूं (Fresh Wheat)"
  final bool softWrap;

  const TranslatedText(
    this.text, {
    super.key,
    this.preTranslatedHi,
    this.preTranslatedEn,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.bilingual = false,
    this.softWrap = true,
  });

  @override
  State<TranslatedText> createState() => _TranslatedTextState();
}

class _TranslatedTextState extends State<TranslatedText> {
  String? _translatedText;
  String? _lastText;
  String? _lastTargetLang;

  final LiveTranslationService _service = LiveTranslationService();

  @override
  void initState() {
    super.initState();
    _resolveTranslation();
  }

  @override
  void didUpdateWidget(covariant TranslatedText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.preTranslatedHi != widget.preTranslatedHi ||
        oldWidget.preTranslatedEn != widget.preTranslatedEn ||
        oldWidget.bilingual != widget.bilingual) {
      _resolveTranslation();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveTranslation();
  }

  void _resolveTranslation() {
    final appState = Provider.of<AppState>(context, listen: false);
    final targetLang = appState.locale.languageCode; // 'hi' or 'en'
    final rawText = widget.text.trim();

    if (rawText.isEmpty) {
      setState(() {
        _translatedText = '';
        _lastText = rawText;
        _lastTargetLang = targetLang;
      });
      return;
    }

    // 1. Direct match with pre-translated fields
    if (targetLang == 'hi' && widget.preTranslatedHi != null && widget.preTranslatedHi!.isNotEmpty) {
      setState(() {
        _translatedText = widget.bilingual && widget.preTranslatedHi != rawText
            ? '${widget.preTranslatedHi} ($rawText)'
            : widget.preTranslatedHi;
        _lastText = rawText;
        _lastTargetLang = targetLang;
      });
      return;
    }

    if (targetLang == 'en' && widget.preTranslatedEn != null && widget.preTranslatedEn!.isNotEmpty) {
      setState(() {
        _translatedText = widget.preTranslatedEn;
        _lastText = rawText;
        _lastTargetLang = targetLang;
      });
      return;
    }

    // 2. Immediate synchronous check from LiveTranslationService cache or dictionary
    final syncMatch = _service.getCachedSync(rawText, targetLanguage: targetLang);
    if (syncMatch != null) {
      setState(() {
        _translatedText = widget.bilingual && targetLang == 'hi' && syncMatch != rawText
            ? '$syncMatch ($rawText)'
            : syncMatch;
        _lastText = rawText;
        _lastTargetLang = targetLang;
      });
      return;
    }

    // 3. Needs async fetch from Google Translate endpoint
    if (_lastText == rawText && _lastTargetLang == targetLang && _translatedText != null) {
      return;
    }

    _lastText = rawText;
    _lastTargetLang = targetLang;

    _service.translate(rawText, targetLanguage: targetLang).then((result) {
      if (mounted && _lastText == rawText && _lastTargetLang == targetLang) {
        setState(() {
          _translatedText = widget.bilingual && targetLang == 'hi' && result != rawText
              ? '$result ($rawText)'
              : result;
        });
      }
    }).catchError((_) {
      if (mounted) {
        setState(() {
          _translatedText = rawText;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Re-check whenever AppState changes
    final currentLang = context.select<AppState, String>((state) => state.locale.languageCode);
    if (currentLang != _lastTargetLang) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resolveTranslation();
      });
    }

    final displayText = _translatedText ?? widget.text;

    return Text(
      displayText,
      style: widget.style,
      textAlign: widget.textAlign,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      softWrap: widget.softWrap,
    );
  }
}

/// Helpful extensions for quick translation in widgets
extension LiveTranslatedExtension on String {
  Widget toTranslatedText({
    TextStyle? style,
    TextAlign? textAlign,
    int? maxLines,
    TextOverflow? overflow,
    bool bilingual = false,
  }) {
    return TranslatedText(
      this,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
      bilingual: bilingual,
    );
  }
}
