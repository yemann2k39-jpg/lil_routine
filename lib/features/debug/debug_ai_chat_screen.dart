import 'package:flutter/material.dart';

import '../../core/ai/ai_key_store.dart';
import '../../core/ai/gemini_provider.dart';
import '../../core/theme/palette.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/pixel_widgets.dart';

/// DEBUG ONLY, TEMPORARY — Niko's manual playground for testing the
/// Gemini configuration end to end (key validity, model id, raw replies).
/// Will be deleted before release; the release user never sees this
/// because the debug room itself is kDebugMode-gated.
class DebugAiChatScreen extends StatefulWidget {
  const DebugAiChatScreen({super.key});

  @override
  State<DebugAiChatScreen> createState() => _DebugAiChatScreenState();
}

class _DebugAiChatScreenState extends State<DebugAiChatScreen> {
  late final GeminiProvider _provider =
      GeminiProvider(keyStore: FlutterSecureAiKeyStore());
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<_ChatLine> _lines = [];
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final prompt = _controller.text.trim();
    if (prompt.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _lines.add(_ChatLine(prompt, fromUser: true));
    });
    _controller.clear();
    _bump();

    final result = await _provider.send(prompt);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _lines.add(_ChatLine(
        result.ok ? result.detail : '✗ ${result.detail}',
        fromUser: false,
        failed: !result.ok,
      ));
    });
    _bump();
  }

  void _bump() {
    // Let the new line lay out, then follow it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ai chat'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                'temp debug playground · $kGeminiModel',
                style: AppTypography.cozy(11, color: Palette.cocoaSoft),
              ),
            ),
            Expanded(
              child: _lines.isEmpty
                  ? Center(
                      child: Text(
                        'say something to Gemini —\nsave a key in Settings first',
                        textAlign: TextAlign.center,
                        style:
                            AppTypography.cozy(13, color: Palette.cocoaSoft),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(20),
                      itemCount: _lines.length,
                      itemBuilder: (context, i) {
                        final line = _lines[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Align(
                            alignment: line.fromUser
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 300),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: line.failed
                                      ? Palette.blushDeep
                                      : (line.fromUser
                                          ? Palette.skyDeep
                                          : Palette.peach),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: Palette.outline, width: 2),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                child: Text(
                                  line.text,
                                  style: AppTypography.cozy(
                                    13,
                                    color: line.fromUser || line.failed
                                        ? Palette.paper
                                        : Palette.cocoa,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            // Busy indicator + composer
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                            hintText: 'prompt to Gemini…'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PixelButton(
                      label: 'send',
                      onTap: _busy ? null : _send,
                      color: Palette.peachDeep,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatLine {
  const _ChatLine(this.text, {required this.fromUser, this.failed = false});

  final String text;
  final bool fromUser;
  final bool failed;
}
