import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/models.dart';
import 'ai_key_store.dart';

/// Outcome of an AI configuration test / chat turn.
///
/// [ok] is true only when the remote model actually answered; [detail]
/// carries the model's reply (truncated for tests) or a plain-language
/// reason it did not.
class AiResult {
  const AiResult({required this.ok, required this.detail});

  final bool ok;
  final String detail;
}

/// One chat exchange with the model (debug playground for now).
class AiChatTurn {
  const AiChatTurn({required this.prompt, required this.response});

  final String prompt;
  final String response;
}

/// Provider contract. Gemini is the first implementation; another backend
/// later = another class implementing this, nothing else changes.
abstract class AiProvider {
  /// Sends [prompt], returns the model's answer or a friendly error.
  Future<AiResult> send(String prompt);

  /// Convenience: minimal "does this configuration work?" ping.
  Future<AiResult> testConnection() => send('Reply with exactly: OK');
}

/// One estimated food item from the AI food-logging flow.
@immutable
class AiFoodEstimate {
  const AiFoodEstimate({
    required this.name,
    required this.mealType,
    required this.kcal,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.fiber,
    required this.sugar,
    required this.sodium,
    required this.portion,
    this.note = '',
  });

  final String name;
  final MealType mealType;
  final double kcal;
  final double protein;
  final double carbs;
  final double fat;
  final double fiber; // grams
  final double sugar; // grams
  final double sodium; // milligrams
  final double portion;
  final String note;

  factory AiFoodEstimate.fromJson(Map<String, dynamic> json) {
    double toDouble(Object? v) =>
        v is num ? v.toDouble() : (double.tryParse('$v') ?? 0);
    final meal = MealType.values.firstWhere(
      (m) => m.name == (json['meal_type'] as String? ?? '').toLowerCase(),
      orElse: () => MealType.snack,
    );
    return AiFoodEstimate(
      name: (json['name'] as String?)?.trim().isNotEmpty ?? false
          ? (json['name'] as String).trim()
          : 'meal',
      mealType: meal,
      kcal: toDouble(json['kcal']),
      protein: toDouble(json['protein_g']),
      carbs: toDouble(json['carbs_g']),
      fat: toDouble(json['fat_g']),
      fiber: toDouble(json['fiber_g']),
      sugar: toDouble(json['sugar_g']),
      sodium: toDouble(json['sodium_mg']),
      portion: toDouble(json['portion']) <= 0 ? 1 : toDouble(json['portion']),
      note: (json['note'] as String?) ?? '',
    );
  }
}

/// Result of an estimation attempt: [ok] with [estimate], or a friendly
/// [detail] error.
class AiEstimateResult {
  const AiEstimateResult.ok(this.estimate) : detail = null;
  const AiEstimateResult.error(this.detail) : estimate = null;

  final AiFoodEstimate? estimate;
  final String? detail;

  bool get ok => estimate != null;
}

/// Gemini via the public REST API — no SDK dependency.
class GeminiProvider extends AiProvider {
  GeminiProvider({required this.keyStore, http.Client? client})
      : _client = client ?? http.Client();

  final AiKeyStore keyStore;
  final http.Client _client;

  static const _host = 'generativelanguage.googleapis.com';
  static const _pathBase = '/v1beta/models';

  Future<Uri> _endpoint() async {
    final key = (await keyStore.readKey())?.trim() ?? '';
    return Uri.https(_host, '$_pathBase/$kGeminiModel:generateContent',
        {'key': key});
  }

  /// Asks the model to estimate one food item from a description and/or
  /// a photo. Returns a parsed [AiFoodEstimate] or a friendly error.
  Future<AiEstimateResult> estimateFood({
    String? description,
    Uint8List? image,
    String imageMimeType = 'image/jpeg',
  }) async {
    final key = (await keyStore.readKey())?.trim() ?? '';
    if (key.isEmpty) {
      return const AiEstimateResult.error(
          'No API key saved yet — add one in Settings.');
    }
    if ((description == null || description.trim().isEmpty) && image == null) {
      return const AiEstimateResult.error(
          'Snap a photo or describe the meal first.');
    }

    final now = DateTime.now();
    final prompt = 'You are a nutrition estimator for a food logging app.\n'
        'Estimate ONE food item from the photo and/or description below.\n'
        'Respond with ONLY a JSON object, no markdown fences, no extra '
        'text, exactly this shape:\n'
        '{"name": "<short food name>", '
        '"meal_type": "<breakfast|lunch|dinner|snack>", '
        '"kcal": <number for the whole described/shown serving>, '
        '"protein_g": <number>, "carbs_g": <number>, "fat_g": <number>, '
        '"fiber_g": <number>, "sugar_g": <number>, '
        '"sodium_mg": <number in milligrams>, '
        '"portion": <number, 1.0 = one normal serving>, '
        '"note": "<max 8 words about your uncertainty or empty string>"}\n'
        'Local time is ${now.hour}:${now.minute.toString().padLeft(2, '0')} '
        '(${_weekdayName(now.weekday)}) — pick the meal_type that fits.\n'
        'Description: ${description?.trim().isEmpty ?? true ? '(none)' : description!.trim()}';

    final parts = <Map<String, dynamic>>[
      {'text': prompt},
    ];
    if (image != null) {
      parts.add({
        'inline_data': {'mime_type': imageMimeType, 'data': base64Encode(image)},
      });
    }

    final uri = await _endpoint();
    final body = jsonEncode({
      'contents': [
        {'parts': parts},
      ],
      'generationConfig': {
        'maxOutputTokens': 512,
        'temperature': 0.1,
      },
    });

    http.Response res;
    try {
      res = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 60));
    } on TimeoutException {
      return const AiEstimateResult.error('Timed out — check your internet.');
    } on Object {
      return const AiEstimateResult.error(
          'No connection — check your internet.');
    }

    if (res.statusCode != 200) {
      return AiEstimateResult.error(_errorDetail(res));
    }

    final parsedBody = _safeJson(res);
    final text =
        parsedBody == null ? '' : (_extractText(parsedBody) ?? '');
    final estimate = parseEstimateJson(text);
    if (estimate == null) {
      return const AiEstimateResult.error(
          'Gemini answered, but not in the expected shape — try again.');
    }
    return AiEstimateResult.ok(estimate);
  }

  /// Extracts the first JSON object from model text (handles ```json
  /// fences and prose around the object).
  static AiFoodEstimate? parseEstimateJson(String raw) {
    var text = raw.trim();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    text = text.substring(start, end + 1);
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) return null;
      return AiFoodEstimate.fromJson(decoded);
    } on Object {
      return null;
    }
  }

  Map<String, dynamic>? _safeJson(http.Response res) {
    try {
      final v = jsonDecode(utf8.decode(res.bodyBytes));
      return v is Map<String, dynamic> ? v : null;
    } on Object {
      return null;
    }
  }

  static String _weekdayName(int weekday) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1];

  @override
  Future<AiResult> send(String prompt) async {
    final key = (await keyStore.readKey())?.trim() ?? '';
    if (key.isEmpty) {
      return const AiResult(
          ok: false, detail: 'No API key saved yet — add one in Settings.');
    }

    final Uri uri;
    try {
      uri = await _endpoint();
    } on Object {
      return const AiResult(ok: false, detail: 'Could not build request.');
    }

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {'maxOutputTokens': 512},
    });

    http.Response res;
    try {
      res = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      ).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      return const AiResult(
          ok: false, detail: 'Timed out — check your internet.');
    } on Object {
      return const AiResult(
          ok: false, detail: 'No connection — check your internet.');
    }

    return _interpret(res);
  }

  AiResult _interpret(http.Response res) {
    final parsed = _safeJson(res);

    if (res.statusCode == 200 && parsed != null) {
      final text = _extractText(parsed);
      if (text != null && text.isNotEmpty) {
        final detail = text.length > 2000 ? '${text.substring(0, 2000)}…' : text;
        return AiResult(ok: true, detail: detail);
      }
      // 200 but no text: blocked or empty candidates.
      final reason = (parsed['promptFeedback']?['blockReason'] as String?) ??
          'The model replied with nothing.';
      return AiResult(ok: false, detail: reason);
    }

    return AiResult(ok: false, detail: _errorDetail(res));
  }

  /// Human-readable message from an error payload (shared by chat and
  /// food-estimation paths).
  String _errorDetail(http.Response res) {
    final parsed = _safeJson(res);
    final apiMessage =
        (parsed?['error']?['message'] as String?) ?? 'HTTP ${res.statusCode}';
    if (res.statusCode == 400 || res.statusCode == 401 || res.statusCode == 403) {
      return apiMessage.toLowerCase().contains('api key')
          ? 'API key rejected — double-check the pasted key.'
          : 'Key rejected by Gemini: $apiMessage';
    }
    if (res.statusCode == 404 ||
        apiMessage.toLowerCase().contains('not found')) {
      return 'Model "$kGeminiModel" not found for this key: $apiMessage';
    }
    if (res.statusCode == 429) {
      return 'Rate limit hit — try again in a minute.';
    }
    return 'Gemini error: $apiMessage';
  }

  /// candidates[0].content.parts[*].text, joined.
  String? _extractText(Map<String, dynamic> parsed) {
    final candidates = parsed['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) return null;
    final first = candidates.first as Map<String, dynamic>;
    final content = first['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List?;
    if (parts == null || parts.isEmpty) return null;
    return parts
        .map((p) => (p as Map<String, dynamic>)['text'] as String? ?? '')
        .join();
  }
}
