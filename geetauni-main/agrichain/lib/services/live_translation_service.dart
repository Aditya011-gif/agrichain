import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Free, Zero-Cost Live Translation Service for AgriChain
/// Uses Google's public translation gateway with dual-layer caching (Memory + SharedPreferences).
class LiveTranslationService {
  static final LiveTranslationService _instance = LiveTranslationService._internal();
  factory LiveTranslationService() => _instance;
  LiveTranslationService._internal();

  // In-memory cache for ultra-fast 0ms UI lookups
  final Map<String, String> _memoryCache = {};
  SharedPreferences? _prefs;
  bool _isPrefsLoaded = false;

  /// Common Agricultural dictionary for instant, accurate 0ms translations
  static final Map<String, String> _agriDictionaryEnToHi = {
    'wheat': 'गेहूं',
    'rice': 'चावल',
    'paddy': 'धान',
    'basmati': 'बासमती',
    'basmati rice': 'बासमती चावल',
    'sharbati wheat': 'शरबती गेहूं',
    'potato': 'आलू',
    'tomato': 'टमाटर',
    'onion': 'प्याज',
    'mustard': 'सरसों',
    'cotton': 'कपास',
    'soybean': 'सोयाबीन',
    'maize': 'मक्का',
    'corn': 'मक्का',
    'sugarcane': 'गन्ना',
    'mango': 'आम',
    'apple': 'सेब',
    'banana': 'केला',
    'pulses': 'दालें',
    'grains': 'अनाज',
    'vegetables': 'सब्जियां',
    'fruits': 'फल',
    'oilseeds': 'तिलहन',
    'spices': 'मसाले',
    'quintal': 'क्विंटल',
    'tonne': 'टन',
    'metric tonne': 'मीट्रिक टन',
    'kg': 'किग्रा',
    'per quintal': 'प्रति क्विंटल',
    'per kg': 'प्रति किग्रा',
    'fresh': 'ताज़ा',
    'organic': 'जैविक',
    'grade a': 'ग्रेड ए (उत्कृष्ट)',
    'grade 1': 'ग्रेड 1 (उत्तम)',
    'standard': 'मानक',
    'harvested': 'काटा गया',
    'farmgate': 'फार्मगेट (खेत से)',
    'godown': 'गोदाम',
    'verified': 'सत्यापित',
    'high quality': 'उच्च गुणवत्ता',
    'direct trade': 'सीधा व्यापार',
  };

  static final Map<String, String> _agriDictionaryHiToEn = {
    'गेहूं': 'Wheat',
    'चावल': 'Rice',
    'धान': 'Paddy',
    'बासमती': 'Basmati',
    'आलू': 'Potato',
    'टमाटर': 'Tomato',
    'प्याज': 'Onion',
    'सरसों': 'Mustard',
    'कपास': 'Cotton',
    'सोयाबीन': 'Soybean',
    'मक्का': 'Maize',
    'गन्ना': 'Sugarcane',
    'आम': 'Mango',
    'सेब': 'Apple',
    'केला': 'Banana',
    'दालें': 'Pulses',
    'अनाज': 'Grains',
    'सब्जियां': 'Vegetables',
    'फल': 'Fruits',
    'तिलहन': 'Oilseeds',
    'क्विंटल': 'Quintal',
    'टन': 'Tonne',
    'ताज़ा': 'Fresh',
    'जैविक': 'Organic',
  };

  /// Initialize persistent disk cache
  Future<void> init() async {
    if (_isPrefsLoaded) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      _isPrefsLoaded = true;
    } catch (e) {
      debugPrint('[LiveTranslationService] Init error: $e');
    }
  }

  /// Check if text contains Devanagari characters (Hindi script)
  bool isHindi(String text) {
    return RegExp(r'[\u0900-\u097F]').hasMatch(text);
  }

  /// Check if text is predominantly English/Latin script
  bool isEnglish(String text) {
    return RegExp(r'[a-zA-Z]').hasMatch(text);
  }

  /// Synchronous instant lookup if already cached in memory or dictionary
  String? getCachedSync(String text, {required String targetLanguage}) {
    if (text.trim().isEmpty) return text;
    final clean = text.trim();

    // If already in target language script, return as-is
    if (targetLanguage == 'hi' && isHindi(clean) && !isEnglish(clean)) {
      return clean;
    }
    if (targetLanguage == 'en' && isEnglish(clean) && !isHindi(clean)) {
      return clean;
    }

    final cacheKey = '${targetLanguage}_$clean';

    // 1. Check in-memory cache
    if (_memoryCache.containsKey(cacheKey)) {
      return _memoryCache[cacheKey];
    }

    // 2. Check Agri Dictionary (case-insensitive for single/double words)
    final lower = clean.toLowerCase();
    if (targetLanguage == 'hi' && _agriDictionaryEnToHi.containsKey(lower)) {
      final res = _agriDictionaryEnToHi[lower]!;
      _memoryCache[cacheKey] = res;
      return res;
    } else if (targetLanguage == 'en' && _agriDictionaryHiToEn.containsKey(lower)) {
      final res = _agriDictionaryHiToEn[lower]!;
      _memoryCache[cacheKey] = res;
      return res;
    }

    // 3. Check SharedPreferences if loaded
    if (_prefs != null) {
      final stored = _prefs!.getString('trans_$cacheKey');
      if (stored != null && stored.isNotEmpty) {
        _memoryCache[cacheKey] = stored;
        return stored;
      }
    }

    return null;
  }

  /// Asynchronously translates any arbitrary string to target language ('hi' or 'en')
  /// 100% Free, zero-cost, no API key required.
  Future<String> translate(
    String text, {
    String targetLanguage = 'hi',
    String? sourceLanguage,
  }) async {
    if (text.trim().isEmpty) return text;
    final clean = text.trim();

    // 1. Immediate sync check
    final syncMatch = getCachedSync(clean, targetLanguage: targetLanguage);
    if (syncMatch != null) return syncMatch;

    final cacheKey = '${targetLanguage}_$clean';
    final sl = sourceLanguage ?? 'auto';
    final tl = targetLanguage;

    try {
      // 2. Query Google's public translation endpoint
      final url = Uri.parse(
        'https://translate.googleapis.com/translate_a/single?client=gtx&sl=$sl&tl=$tl&dt=t&q=${Uri.encodeComponent(clean)}',
      );

      final response = await http.get(url).timeout(
        const Duration(seconds: 4),
        onTimeout: () => http.Response('', 408),
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List && decoded.isNotEmpty && decoded[0] is List) {
          final buffer = StringBuffer();
          for (final part in decoded[0]) {
            if (part is List && part.isNotEmpty && part[0] != null) {
              buffer.write(part[0].toString());
            }
          }

          final translated = buffer.toString().trim();
          if (translated.isNotEmpty) {
            // Save in memory cache
            _memoryCache[cacheKey] = translated;

            // Save in persistent storage in background
            _saveToDisk(cacheKey, translated);

            return translated;
          }
        }
      }
    } catch (e) {
      debugPrint('[LiveTranslationService] Translation failed for "$clean": $e');
    }

    // Fallback: return original text if translation fails or times out
    return clean;
  }

  /// Batch translate multiple strings concurrently
  Future<Map<String, String>> translateBatch(
    List<String> texts, {
    String targetLanguage = 'hi',
  }) async {
    final Map<String, String> results = {};
    final futures = texts.map((t) async {
      final res = await translate(t, targetLanguage: targetLanguage);
      results[t] = res;
    });
    await Future.wait(futures);
    return results;
  }

  void _saveToDisk(String key, String value) async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setString('trans_$key', value);
    } catch (_) {}
  }
}
