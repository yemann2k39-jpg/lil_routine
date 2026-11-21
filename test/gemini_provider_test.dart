import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lil_routine/core/ai/ai_key_store.dart';
import 'package:lil_routine/core/ai/gemini_provider.dart';
import 'package:lil_routine/core/data/models.dart';

void main() {
  test('send returns model text on 200', () async {
    final store = InMemoryAiKeyStore()..writeKey('k-test');
    final requests = <http.Request>[];
    final provider = GeminiProvider(
      keyStore: store,
      client: MockClient((req) async {
        requests.add(req);
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'OK'},
                  ],
                },
              },
            ],
          }),
          200,
        );
      }),
    );

    final result = await provider.testConnection();

    expect(result.ok, isTrue);
    expect(result.detail, 'OK');
    expect(requests, hasLength(1));
    expect(requests.single.url.host, 'generativelanguage.googleapis.com');
    expect(requests.single.url.path,
        '/v1beta/models/$kGeminiModel:generateContent');
    expect(requests.single.url.queryParameters['key'], 'k-test');
  });

  test('send joins multi-part responses', () async {
    final provider = GeminiProvider(
      keyStore: InMemoryAiKeyStore()..writeKey('k'),
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'Hello '},
                      {'text': 'world'},
                    ],
                  },
                },
              ],
            }),
            200,
          )),
    );

    final result = await provider.send('hi');
    expect(result.ok, isTrue);
    expect(result.detail, 'Hello world');
  });

  test('bad key (403 with API key message) maps to friendly error', () async {
    final provider = GeminiProvider(
      keyStore: InMemoryAiKeyStore()..writeKey('bad'),
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'error': {
                'code': 403,
                'message': 'API key not valid. Please pass a valid API key.',
              },
            }),
            403,
          )),
    );

    final result = await provider.send('hi');
    expect(result.ok, isFalse);
    expect(result.detail, contains('rejected'));
  });

  test('unknown model (404) names the model', () async {
    final provider = GeminiProvider(
      keyStore: InMemoryAiKeyStore()..writeKey('k'),
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'error': {
                'code': 404,
                'message': 'models/whatever is not found for API version v1beta',
              },
            }),
            404,
          )),
    );

    final result = await provider.send('hi');
    expect(result.ok, isFalse);
    expect(result.detail, contains(kGeminiModel));
  });

  test('rate limit (429) says try again', () async {
    final provider = GeminiProvider(
      keyStore: InMemoryAiKeyStore()..writeKey('k'),
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'error': {'code': 429, 'message': 'quota exceeded'},
            }),
            429,
          )),
    );

    final result = await provider.send('hi');
    expect(result.ok, isFalse);
    expect(result.detail, contains('Rate limit'));
  });

  test('no key stored answers immediately without HTTP', () async {
    http.Request? seen;
    final provider = GeminiProvider(
      keyStore: InMemoryAiKeyStore(),
      client: MockClient((req) async {
        seen = req;
        return http.Response('{}', 200);
      }),
    );

    final result = await provider.send('hi');
    expect(result.ok, isFalse);
    expect(result.detail, contains('No API key'));
    expect(seen, isNull);
  });

  test('200 with empty candidates reports block reason', () async {
    final provider = GeminiProvider(
      keyStore: InMemoryAiKeyStore()..writeKey('k'),
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'promptFeedback': {'blockReason': 'SAFETY'},
              'candidates': [],
            }),
            200,
          )),
    );

    final result = await provider.send('hi');
    expect(result.ok, isFalse);
    expect(result.detail, 'SAFETY');
  });

  test('AiGate reflects key presence', () async {
    final store = InMemoryAiKeyStore();
    final gate = AiGate(store);
    expect(await gate.isConfigured(), isFalse);
    await store.writeKey('k');
    expect(await gate.isConfigured(), isTrue);
  });

  test('estimateFood parses a clean JSON answer', () async {
    final store = InMemoryAiKeyStore()..writeKey('k');
    final bodies = <String>[];
    final provider = GeminiProvider(
      keyStore: store,
      client: MockClient((req) async {
        bodies.add(req.body);
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'text': '{"name":"scrambled eggs","meal_type":'
                          '"breakfast","kcal":320,"protein_g":21,'
                          '"carbs_g":4,"fat_g":24,"portion":1.0,'
                          '"note":"estimate"}',
                    },
                  ],
                },
              },
            ],
          }),
          200,
        );
      }),
    );

    final result = await provider.estimateFood(description: '2 eggs');

    expect(result.ok, isTrue);
    final e = result.estimate!;
    expect(e.name, 'scrambled eggs');
    expect(e.mealType, MealType.breakfast);
    expect(e.kcal, 320);
    expect(e.protein, 21);
    expect(e.portion, 1.0);
    // Vision payload present when an image is attached.
    await provider.estimateFood(
        description: 'eggs', image: Uint8List.fromList([1, 2, 3]));
    final body = jsonDecode(bodies.last) as Map<String, dynamic>;
    final parts =
        (body['contents'][0]['parts'] as List).cast<Map<String, dynamic>>();
    expect(
        parts.any((p) =>
            p.containsKey('inline_data') &&
            p['inline_data']['data'] == base64Encode([1, 2, 3])),
        isTrue);
  });

  test('estimateFood strips markdown fences around JSON', () {
    const raw = 'Sure! Here is the JSON:\n```json\n{"name":"toast",'
        '"meal_type":"snack","kcal":88,"protein_g":2.5,"carbs_g":13,'
        '"fat_g":1,"portion":1,"note":""}\n```';
    final e = GeminiProvider.parseEstimateJson(raw);
    expect(e, isNotNull);
    expect(e!.name, 'toast');
    expect(e.kcal, 88);
  });

  test('estimateFood rejects non-JSON answers', () async {
    final provider = GeminiProvider(
      keyStore: InMemoryAiKeyStore()..writeKey('k'),
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'A bagel has around 250 kcal, enjoy!'},
                    ],
                  },
                },
              ],
            }),
            200,
          )),
    );

    final result = await provider.estimateFood(description: 'bagel');
    expect(result.ok, isFalse);
    expect(result.detail, contains('not in the expected shape'));
  });

  test('estimateFood refuses empty input without HTTP', () async {
    http.Request? seen;
    final provider = GeminiProvider(
      keyStore: InMemoryAiKeyStore()..writeKey('k'),
      client: MockClient((req) async {
        seen = req;
        return http.Response('{}', 200);
      }),
    );
    final result = await provider.estimateFood();
    expect(result.ok, isFalse);
    expect(result.detail, contains('Snap a photo'));
    expect(seen, isNull);
  });

  test('AiFoodEstimate.fromJson tolerates bad meal + zero portion', () {
    final e = AiFoodEstimate.fromJson({
      'name': '  ',
      'meal_type': 'brunch',
      'kcal': '123',
      'protein_g': 0,
      'carbs_g': 0,
      'fat_g': 0,
      'portion': 0,
      'note': 'n',
    });
    expect(e.name, 'meal'); // empty name falls back
    expect(e.mealType, MealType.snack); // unknown meal -> snack
    expect(e.kcal, 123); // numeric strings parsed
    expect(e.portion, 1); // zero portion bumped to 1
  });

  // --- Weekly coach recap (LIL-22) ------------------------------------

  RecapDayStats day(String label, {int kcal = 0, int water = 0}) =>
      RecapDayStats(
        label: label,
        kcal: kcal,
        proteinG: 0,
        carbsG: 0,
        fatG: 0,
        sodiumMg: 0,
        sugarG: 0,
        waterMl: water,
      );

  test('weeklyRecap parses a clean tips answer', () async {
    final bodies = <String>[];
    final provider = GeminiProvider(
      keyStore: InMemoryAiKeyStore()..writeKey('k'),
      client: MockClient((req) async {
        bodies.add(req.body);
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'text': '{"tips": ['
                          '{"title": "salty days", '
                          '"body": "Sodium was high; add a glass of water."},'
                          '{"title": "steady week", '
                          '"body": "You hit your water goal 4 times."}'
                          ']}'
                    },
                  ],
                },
              },
            ],
          }),
          200,
        );
      }),
    );

    final result = await provider.weeklyRecap(
      days: [
        day('Mon Oct 26', kcal: 1500, water: 3100),
        day('Tue Oct 27', kcal: 2400, water: 1200),
        day('Wed Oct 28', kcal: 1800, water: 2800),
      ],
      kcalGoal: 2000,
      waterGoalMl: 3000,
    );

    expect(result.ok, isTrue);
    expect(result.tips, hasLength(2));
    expect(result.tips!.first.title, 'salty days');
    expect(result.tips!.last.body, contains('water goal'));
    // Prompt carries numbers + goals, and stays name-free by design.
    expect(bodies.join(), contains('kcal 1500'));
    expect(bodies.join(), contains('water 1200ml'));
    expect(bodies.join(), contains('2000 kcal/day'));
  });

  test('weeklyRecap strips markdown fences around tips JSON', () {
    const raw = 'Sure!\n```json\n{"tips": [{"title": "t", "body": "b"}]}\n```';
    final tips = GeminiProvider.parseWeeklyRecapJson(raw);
    expect(tips, isNotNull);
    expect(tips!.single.title, 't');
  });

  test('parseWeeklyRecapJson rejects wrong shapes', () {
    expect(GeminiProvider.parseWeeklyRecapJson('no json here'), isNull);
    expect(GeminiProvider.parseWeeklyRecapJson('{"tips": []}'), isNull);
    expect(
        GeminiProvider.parseWeeklyRecapJson(
            '{"tips": [{"title": "", "body": "b"}]}'),
        isNull);
    expect(
        GeminiProvider.parseWeeklyRecapJson(
            '{"tips": [{"title": "t"}]}'),
        isNull);
    expect(
        GeminiProvider.parseWeeklyRecapJson(
            '{"tips": [{"title": "t", "body": "b"}, "nope"]}'),
        isNull);
  });

  test('weeklyRecap refuses to run with fewer than 2 logged days',
      () async {
    http.Request? seen;
    final provider = GeminiProvider(
      keyStore: InMemoryAiKeyStore()..writeKey('k'),
      client: MockClient((req) async {
        seen = req;
        return http.Response('{}', 200);
      }),
    );
    final result = await provider.weeklyRecap(
      days: [
        day('Mon Oct 26', kcal: 1500, water: 1000),
        day('Tue Oct 27'), // empty day
        day('Wed Oct 28'), // empty day
      ],
      kcalGoal: 2000,
      waterGoalMl: 3000,
    );
    expect(result.ok, isFalse);
    expect(result.detail, contains('Not enough logged days'));
    expect(seen, isNull);
  });

  test('weeklyRecap without key answers immediately without HTTP',
      () async {
    http.Request? seen;
    final provider = GeminiProvider(
      keyStore: InMemoryAiKeyStore(),
      client: MockClient((req) async {
        seen = req;
        return http.Response('{}', 200);
      }),
    );
    final result = await provider.weeklyRecap(
      days: [day('Mon Oct 26', kcal: 1500), day('Tue Oct 27', kcal: 1500)],
      kcalGoal: 2000,
      waterGoalMl: 3000,
    );
    expect(result.ok, isFalse);
    expect(result.detail, contains('No API key'));
    expect(seen, isNull);
  });
}
