import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

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
  TvProgram? _current;
  TvProgram? _next;
  bool _loading = true;
  bool _guideVisible = true;
  String? _error;
  final FocusNode _focus = FocusNode();

  @override void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final c = await widget.api.resolvePlayback(widget.channel);
      if (!mounted) return;
      if (c.playbackUrl == null || c.playbackUrl!.isEmpty) {
        setState(() { _loading = false; _error = 'Stream URL not available for ${c.name}.'; });
        return;
      }
      List<TvProgram> epg = const [];
      try { epg = await widget.api.getEpg(c.id); } catch (_) {}
      final now = DateTime.now();
      TvProgram? current, next;
      for (final p in epg) {
        if (!now.isBefore(p.start) && now.isBefore(p.end)) current = p;
        if (next == null && p.start.isAfter(now)) next = p;
      }
      if (!mounted) return;
      setState(() { _resolved = c; _current = current; _next = next; _loading = false; });
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
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.escape ||
              event.logicalKey == LogicalKeyboardKey.goBack ||
              event.logicalKey == LogicalKeyboardKey.browserBack) {
            Navigator.maybePop(context);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.select) {
            setState(() => _guideVisible = !_guideVisible);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Stack(fit: StackFit.expand, children: [
          if (c?.playbackUrl != null)
            AndroidView(
              viewType: 'streamz-exoplayer',
              creationParams: {
                'url': c!.playbackUrl!,
                'headers': {
                  ...c.playbackHeaders,
                  'User-Agent': c.playbackHeaders['User-Agent'] ??
                      'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 Chrome/131.0.0.0 Mobile Safari/537.36',
                  'Origin': 'https://www.jiotv.com',
                  'Referer': 'https://www.jiotv.com/tv-guide',
                },
                'clearKeyJson': c.clearKeyJson,
              },
              creationParamsCodec: const StandardMessageCodec(),
            )
          else if (_loading)
            const Center(child: CircularProgressIndicator(color: TvColors.blue))
          else
            _errorView(),
          if (c != null) _topInfo(c),
          if (_guideVisible && c != null) _guide(c),
        ]),
      ),
    );
  }

  Widget _topInfo(TvChannel c) => SafeArea(
    child: Align(alignment: Alignment.topLeft, child: Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: .72), borderRadius: BorderRadius.circular(7)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('${c.channelOrder > 0 ? c.channelOrder : c.id}', style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w700)),
        const SizedBox(width: 9),
        if (c.logoUrl != null) SizedBox(width: 34, height: 28, child: Image.network(c.logoUrl!, fit: BoxFit.contain)),
        const SizedBox(width: 8),
        Text(c.name, style: const TextStyle(fontWeight: FontWeight.w900)),
      ]),
    )),
  );

  Widget _guide(TvChannel c) => SafeArea(
    child: Align(alignment: Alignment.bottomCenter, child: Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      decoration: BoxDecoration(color: const Color(0xF20A0C12), borderRadius: BorderRadius.circular(5), border: Border.all(color: Colors.white24), boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 20)]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(height: 38, padding: const EdgeInsets.symmetric(horizontal: 14), color: const Color(0xFF151923), child: Row(children: [
          Text('${c.channelOrder > 0 ? c.channelOrder : c.id}  ${c.name}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
          const Spacer(),
          Text(DateFormat('EEE dd MMM  hh:mm a').format(DateTime.now()), style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ])),
        _programRow(_current, live: true),
        _programRow(_next, live: false),
        Container(height: 34, padding: const EdgeInsets.symmetric(horizontal: 12), color: const Color(0xFF10131A), child: Row(children: [
          _action('OK', 'Guide', TvColors.blue),
          _action('BACK', 'Exit', Colors.white70),
          _action('CH', 'Channel', Colors.greenAccent),
          _action('REC', 'Record', Colors.redAccent),
          _action('●', 'Alerts', Colors.amber),
          _action('A', 'Language', Colors.lightBlueAccent),
        ])),
      ]),
    )),
  );

  Widget _programRow(TvProgram? program, {required bool live}) {
    final active = live && program != null;
    return Container(
      height: 48,
      decoration: BoxDecoration(color: active ? const Color(0xFF0876D1) : const Color(0xFF171B24), border: const Border(top: BorderSide(color: Colors.white10))),
      padding: const EdgeInsets.symmetric(horizontal: 13),
      child: Row(children: [
        SizedBox(width: 58, child: Text(program == null ? '--:--' : DateFormat('HH:mm').format(program.start), style: TextStyle(color: active ? Colors.white : Colors.white70, fontWeight: FontWeight.w800))),
        Expanded(child: Text(program?.title ?? (live ? 'Live program information unavailable' : 'Next program unavailable'), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: active ? FontWeight.w900 : FontWeight.w700, color: Colors.white))),
        if (program != null) Text(DateFormat('HH:mm').format(program.end), style: const TextStyle(color: Colors.white60, fontSize: 11)),
      ]),
    );
  }

  Widget _action(String key, String label, Color color) => Padding(
    padding: const EdgeInsets.only(right: 18),
    child: Row(children: [Text(key, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 10)), const SizedBox(width: 4), Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10))]),
  );

  Widget _errorView() => Center(child: Container(
    constraints: const BoxConstraints(maxWidth: 600),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(color: const Color(0xE610131A), borderRadius: BorderRadius.circular(12)),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
      const SizedBox(height: 12),
      const Text('Unable to start playback', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      const SizedBox(height: 8),
      Text(_error ?? 'No playable stream was returned.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
      const SizedBox(height: 18),
      FilledButton(onPressed: _resolve, child: const Text('Retry')),
      const SizedBox(height: 8),
      OutlinedButton(onPressed: () => Navigator.maybePop(context), child: const Text('Back to channels')),
    ]),
  ));

  @override void dispose() {
    _focus.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }
}
