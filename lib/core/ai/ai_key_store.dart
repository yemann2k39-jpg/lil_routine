import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Which AI backend the app talks to. Only Gemini for now; adding another
/// provider later means a new enum entry + a new AiProvider class — the
/// settings schema does not change.
enum AiProviderId { gemini }

/// Model used for all Gemini calls (chat test now, food estimation later).
/// Flash-lite tier: fast + generous free tier + vision-capable, so the
/// scan-food feature (LIL-10) can reuse it as-is.
const String kGeminiModel = 'gemini-3.1-flash-lite';

const String kAiStudioUrl = 'https://aistudio.google.com/apikey';

/// Storage contract for the API key. Tests use [InMemoryAiKeyStore]; the
/// app uses [FlutterSecureAiKeyStore] (Android Keystore-backed encryption).
abstract class AiKeyStore {
  Future<String?> readKey();
  Future<void> writeKey(String key);
  Future<void> deleteKey();
}

/// Real storage: flutter_secure_storage. On Android this is backed by
/// Kotlin-side encrypted preferences tied to the hardware Keystore — the
/// key never touches sqlite, logs, or backups.
class FlutterSecureAiKeyStore implements AiKeyStore {
  FlutterSecureAiKeyStore({FlutterSecureStorage? storage})
      // v11 defaults: Android stores via encrypted preferences tied to
      // the hardware Keystore, excluded from cloud backups.
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _keyName = 'ai_api_key';

  @override
  Future<String?> readKey() => _storage.read(key: _keyName);

  @override
  Future<void> writeKey(String key) =>
      _storage.write(key: _keyName, value: key);

  @override
  Future<void> deleteKey() => _storage.delete(key: _keyName);
}

/// Test double.
class InMemoryAiKeyStore implements AiKeyStore {
  String? _key;

  @override
  Future<String?> readKey() async => _key;

  @override
  Future<void> writeKey(String key) async => _key = key;

  @override
  Future<void> deleteKey() async => _key = null;
}

/// Simple gating helper any AI surface can consult: AI features stay
/// locked until a key exists (validity is checked by the test-connection
/// flow, not here).
class AiGate {
  AiGate(this.keyStore);

  final AiKeyStore keyStore;

  Future<bool> isConfigured() async =>
      (await keyStore.readKey())?.trim().isNotEmpty ?? false;
}
