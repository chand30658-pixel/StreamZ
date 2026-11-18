import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../services/jio_api.dart';
import '../theme.dart';

class ChannelPlayerScreen extends StatefulWidget {
  const ChannelPlayerScreen({super.key, required this.api, required this.channel});
  final JioApi api;
  final TvChannel channel;
  @override State<ChannelPlayerScreen> createState() => _ChannelPlayerScreenState();
}
class _ChannelPlayerScreenState extends State<ChannelPlayerScreen> {
  TvChannel? _resolved;
  bool _loading = true;
  String? _error;
  final FocusNode _focus = FocusNode();

  @override void initState() { super.initState(); _resolve(); }
  Future<void> _resolve() async {
    try {
      final c = await widget.api.resolvePlayback(widget.channel);
      if (!mounted) return;
      if (c.playbackUrl == null || c.playbackUrl!.isEmpty) {
        setState(() { _loading = false; _error = 'No playable stream is available.'; });
        return;
      }
      setState(() { _resolved = c; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override Widget build(BuildContext context) {
    final c = _resolved;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus, autofocus: true,
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              (event.logicalKey == LogicalKeyboardKey.escape ||
               event.logicalKey == LogicalKeyboardKey.goBack ||
               event.logicalKey == LogicalKeyboardKey.browserBack)) {
            Navigator.maybePop(context);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(fit: StackFit.expand, children: [
          if (c?.playbackUrl != null)
            AndroidView(
              viewType: 'streamz-exoplayer',
              creationParams: {'url': c!.playbackUrl!, 'headers': c.playbackHeaders, 'clearKeyJson': c.clearKeyJson},
              creationParamsCodec: const StandardMessageCodec(),
            )
          else if (_loading)
            const Center(child: CircularProgressIndicator(color: TvColors.blue))
          else _errorView(),
          if (c != null) _badge(c),
        ]),
      ),
    );
  }

  Widget _badge(TvChannel c) => SafeArea(
    child: Align(alignment: Alignment.topLeft, child: Container(
      margin: const EdgeInsets.all(12), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: .65), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (c.logoUrl != null) SizedBox(width: 32, height: 32, child: Image.network(c.logoUrl!, fit: BoxFit.contain)),
        const SizedBox(width: 8), Text(c.name, style: const TextStyle(fontWeight: FontWeight.w900)),
      ]),
    )),
  );

  Widget _errorView() => Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
      const SizedBox(height: 12), Text(_error ?? 'Playback failed', textAlign: TextAlign.center),
      const SizedBox(height: 18),
      Row(mainAxisSize: MainAxisSize.min, children: [
        FilledButton(onPressed: _resolve, child: const Text('Retry')),
        const SizedBox(width: 10),
        OutlinedButton(onPressed: () => Navigator.maybePop(context), child: const Text('Back')),
      ]),
    ]),
  ));
  @override void dispose() { _focus.dispose(); super.dispose(); }
}
