import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/jio_api.dart';
import '../theme.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.api});
  final JioApi api;
  @override State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final FocusNode _focus = FocusNode();
  final TextEditingController _search = TextEditingController();
  List<TvChannel> _channels = const [];
  List<TvProgram> _epg = const [];
  MethodChannel? _playerChannel;
  String? _playerUrl;
  Map<String, String> _playerHeaders = const {};
  String? _playerClearKey;
  int _index = 0;
  String _dial = '';
  String? _error;
  Timer? _dialTimer, _hideTimer;
  bool _banner = true, _keypad = false, _settings = false, _searchMode = false, _muted = false;
  int _aspect = 0, _settingsTab = 0;
  bool _loading = true;

  TvChannel? get _channel => _channels.isEmpty ? null : _channels[_index.clamp(0, _channels.length - 1)];
  TvProgram? get _liveProgram {
    final now = DateTime.now();
    for (final p in _epg) if (!now.isBefore(p.start) && now.isBefore(p.end)) return p;
    return null;
  }
  TvProgram? get _nextProgram {
    final now = DateTime.now();
    for (final p in _epg) if (p.start.isAfter(now)) return p;
    return null;
  }

  @override void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  Future<void> _load() async {
    try {
      final channels = await widget.api.loadChannels();
      if (!mounted) return;
      setState(() { _channels = channels; _loading = false; });
      if (channels.isNotEmpty) await _tune(0);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Unable to load channels: $e'; });
    }
  }

  Future<void> _tune(int nextIndex) async {
    if (_channels.isEmpty) return;
    final index = nextIndex.clamp(0, _channels.length - 1);
    final channel = _channels[index];
    setState(() { _index = index; _error = null; _epg = const []; _banner = true; });
    _armHide();
    _playerUrl = null; _playerChannel = null; _playerClearKey = null; _playerHeaders = const {};

    try {
      final resolved = await widget.api.resolvePlayback(channel);
      if (resolved.playbackUrl == null) {
        throw StateError('No playable source is available for channel ${channel.id}.');
      }
      _playerUrl = resolved.playbackUrl;
      _playerHeaders = {'Accept': '*/*', ...resolved.playbackHeaders};
      _playerClearKey = resolved.clearKeyJson;
      if (mounted) setState(() {});
      final epg = await widget.api.getEpg(channel.id);
      if (mounted && _channel?.id == channel.id) setState(() => _epg = epg);
    } catch (e) {
      if (mounted && _channel?.id == channel.id) setState(() => _error = _friendlyError(e));
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('451')) return 'HTTP 451 • Stream is geo-restricted.';
    if (s.contains('403')) return 'HTTP 403 • Playback token may have expired.';
    if (s.contains('404')) return 'HTTP 404 • Stream was not found.';
    return s.replaceFirst('Exception: ', '');
  }

  void _armHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 6500), () {
      if (mounted && !_settings && !_searchMode && !_keypad && _dial.isEmpty) setState(() => _banner = false);
    });
  }

  void _touch() {
    setState(() => _banner = !_banner);
    if (_banner) _armHide();
  }

  void _digit(String digit) {
    _hideTimer?.cancel();
    if (_dial.length >= 4) return;
    setState(() { _dial += digit; _banner = true; });
    if (_dial == '0000') { _openSearch(); return; }
    _dialTimer?.cancel();
    _dialTimer = Timer(const Duration(milliseconds: 1300), _commitDial);
  }

  void _backspace() { if (_dial.isNotEmpty) setState(() => _dial = _dial.substring(0, _dial.length - 1)); }

  void _commitDial() {
    if (_dial.isEmpty) return;
    final number = int.tryParse(_dial);
    final found = number == null ? -1 : _channels.indexWhere((c) => c.id == number || c.channelOrder == number);
    if (found < 0) {
      setState(() => _error = 'Channel #$_dial not found');
      Timer(const Duration(milliseconds: 2200), () { if (mounted) setState(() => _error = null); });
    } else { _tune(found); }
    setState(() => _dial = '');
  }

  void _openSearch() {
    setState(() { _searchMode = true; _keypad = false; _search.text = ''; _dial = ''; });
  }

  void _toggleMute() {
    _muted = !_muted;
    _playerChannel?.invokeMethod('setVolume', {'volume': _muted ? 0.0 : 1.0});
    setState(() {});
    _armHide();
  }

  void _cycleAspect() {
    _aspect = (_aspect + 1) % 3;
    final fit = _aspect == 0 ? BoxFit.fill : (_aspect == 1 ? BoxFit.contain : BoxFit.cover);
    _playerChannel?.invokeMethod('setAspect', {'mode': _aspect});
    setState(() {});
    _armHide();
  }

  void _next() { if (_channels.isNotEmpty) _tune((_index + 1) % _channels.length); }
  void _onPlatformViewCreated(int viewId) {
    final channel = MethodChannel('streamz-exoplayer/$viewId');
    _playerChannel = channel;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'playerError' && mounted) {
        setState(() => _error = call.arguments?.toString() ?? 'Playback error');
      }
    });
    channel.invokeMethod('setVolume', {'volume': _muted ? 0.0 : 1.0});
    channel.invokeMethod('setAspect', {'mode': _aspect});
  }

  void _previous() { if (_channels.isNotEmpty) _tune((_index - 1 + _channels.length) % _channels.length); }

  void _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (_settings) setState(() => _settings = false);
      else if (_keypad) setState(() => _keypad = false);
      else if (_searchMode) setState(() => _searchMode = false);
      else if (_dial.isNotEmpty) setState(() => _dial = '');
      else if (!_banner) { setState(() => _banner = true); _armHide(); }
      return;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.channelDown) { _previous(); return; }
    if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.channelUp) { _next(); return; }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.numpadEnter) {
      if (_dial.isNotEmpty) _commitDial(); else _touch();
      return;
    }
    final label = key.keyLabel;
    if (RegExp(r'^[0-9]$').hasMatch(label)) _digit(label);
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      body: KeyboardListener(
        focusNode: _focus, onKeyEvent: _onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque, onTap: _touch,
          child: Stack(fit: StackFit.expand, children: [
            const ColoredBox(color: Colors.black),
            if (_playerUrl != null)
              Positioned.fill(
                child: AndroidView(
                  key: ValueKey('exo-${_channel?.id}-$_playerUrl'),
                  viewType: 'streamz-exoplayer',
                  creationParams: {
                    'url': _playerUrl,
                    'headers': _playerHeaders,
                    if (_playerClearKey != null) 'clearKeyJson': _playerClearKey,
                  },
                  creationParamsCodec: const StandardMessageCodec(),
                  onPlatformViewCreated: _onPlatformViewCreated,
                ),
              ),
            if (_loading) const Center(child: _Loader(label: 'Loading channels…')),
            if (_channel != null && _error == null) _buildTopControls(),
            if (_dial.isNotEmpty) _buildDialOse(),
            if (_keypad) _buildKeypad(),
            if (_banner && _channel != null && _error == null) _buildBanner(),
            if (_error != null) _buildError(),
            if (_settings) _buildSettings(),
            if (_searchMode) _buildSearch(),
          ]),
        ),
      ),
    );
  }

  Widget _buildTopControls() => Positioned(
    top: 10, right: 12,
    child: DecoratedBox(
      decoration: BoxDecoration(color: const Color(0x990D111A), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white30)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _iconButton(Icons.dialpad, _keypad, () { setState(() => _keypad = !_keypad); _armHide(); }),
        _iconButton(_muted ? Icons.volume_off : Icons.volume_up, _muted, _toggleMute),
        _iconButton(Icons.aspect_ratio, false, _cycleAspect),
        _iconButton(Icons.settings, _settings, () { setState(() { _settings = true; _banner = true; }); _hideTimer?.cancel(); }),
      ]),
    ),
  );

  Widget _iconButton(IconData icon, bool active, VoidCallback onTap) => IconButton(
    onPressed: onTap, icon: Icon(icon, color: active ? TvColors.cyan : Colors.white),
    iconSize: 23, padding: const EdgeInsets.all(12),
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
  );

  Widget _buildDialOse() => Positioned(
    top: 14, right: 16,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: const Color(0xD9333842), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white54)),
      child: Text('${_dial}_', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
    ),
  );

  Widget _buildKeypad() {
    final keys = ['1','2','3','4','5','6','7','8','9'];
    return Positioned(
      right: 12, top: MediaQuery.sizeOf(context).height * .25,
      child: Container(
        width: 172, padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xE6141925), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white45)),
        child: Column(children: [
          const Align(alignment: Alignment.centerLeft, child: Text('Channel # / 0000 Search', style: TextStyle(color: TvColors.cyan, fontSize: 10, fontWeight: FontWeight.bold))),
          const SizedBox(height: 8),
          for (var row = 0; row < 3; row++) Row(children: [
            for (var col = 0; col < 3; col++) Expanded(child: _padButton(keys[row * 3 + col], () => _digit(keys[row * 3 + col]))),
          ]),
          Row(children: [
            Expanded(child: _padButton('⌫', _backspace)),
            Expanded(child: _padButton('0', () => _digit('0'))),
            Expanded(child: _padButton('OK', _commitDial, primary: true)),
          ]),
          const SizedBox(height: 5),
          SizedBox(width: double.infinity, child: _padButton('0000 Search', _openSearch, primary: true)),
        ]),
      ),
    );
  }

  Widget _padButton(String label, VoidCallback onTap, {bool primary = false}) => Padding(
    padding: const EdgeInsets.all(2),
    child: SizedBox(height: 34, child: TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        backgroundColor: primary ? TvColors.blue : const Color(0xFF262E3F),
        foregroundColor: primary ? Colors.black : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        padding: EdgeInsets.zero,
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
    )),
  );

  Widget _buildBanner() {
    final channel = _channel!;
    final live = _liveProgram;
    final next = _nextProgram;
    final image = live?.thumbnailUrl ?? live?.posterUrl ?? channel.logoUrl;
    return Positioned(
      left: 12, right: 12, bottom: 10,
      child: Container(
        height: 118,
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xEB222732),Color(0xF0111622),Color(0xF50B0E16)]),
          borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white54),
        ),
        child: Row(children: [
          Padding(padding: const EdgeInsets.all(6), child: SizedBox(
            width: 148, height: 106,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: image == null ? const ColoredBox(color: Color(0xFF161D2B), child: Icon(Icons.tv, size: 44, color: Colors.white54))
                : Image.network(image, fit: BoxFit.fill, errorBuilder: (_,__,___) => const ColoredBox(color: Color(0xFF161D2B), child: Icon(Icons.tv, size: 44, color: Colors.white54))),
          )),
          Expanded(child: Column(children: [
            _headerBar(channel),
            _programRow(live?.title ?? '${channel.name} Live Stream', live == null ? 'LIVE NOW' : '${_time(live.start)} - ${_time(live.end)}', blue: true),
            _programRow(next?.title ?? 'Tap for 15-Day EPG & Catch-Up Schedule', next == null ? '' : '${_time(next.start)} - ${_time(next.end)}'),
            _progressActions(live),
          ])),
        ]),
      ),
    );
  }

  Widget _headerBar(TvChannel channel) => Container(
    height: 31, color: const Color(0xFF1A1F2B), padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(children: [
      IconButton(onPressed: _previous, icon: const Icon(Icons.chevron_left), iconSize: 22, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32)),
      Expanded(child: Text('${channel.id} ${channel.name}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
      Text(DateFormat('EEE dd MMM hh:mm a').format(DateTime.now()), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      IconButton(onPressed: _next, icon: const Icon(Icons.chevron_right), iconSize: 22, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32)),
    ]),
  );

  Widget _programRow(String title, String time, {bool blue = false}) => Container(
    height: 28, color: blue ? TvColors.blue : const Color(0xFF141923),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(children: [
      Expanded(child: Text(title, overflow: TextOverflow.ellipsis, style: TextStyle(color: blue ? Colors.black : Colors.white, fontSize: blue ? 14 : 13, fontWeight: blue ? FontWeight.bold : FontWeight.w600))),
      Text(time, style: TextStyle(color: blue ? Colors.black : Colors.white.withValues(alpha: .9), fontSize: blue ? 13 : 12, fontWeight: FontWeight.bold)),
    ]),
  );

  Widget _progressActions(TvProgram? live) {
    var progress = .05;
    if (live != null && live.end.isAfter(live.start)) {
      progress = DateTime.now().difference(live.start).inMilliseconds / live.end.difference(live.start).inMilliseconds;
      progress = progress.clamp(.05, 1.0);
    }
    final actions = [
      ('E5093A', 'Search', _openSearch),
      ('10B981', 'Genres', _openSearch),
      ('FFC107', 'Catch-Up', _openEpg),
      ('0099FF', _channel?.languageName ?? 'Language', () => setState(() => _keypad = !_keypad)),
    ];
    return Expanded(child: Container(
      color: const Color(0xFF0D1119), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(children: [
        Container(width: 96, height: 9, decoration: BoxDecoration(color: const Color(0xFF283040), borderRadius: BorderRadius.circular(5), border: Border.all(color: Colors.white54)), alignment: Alignment.centerLeft,
          child: FractionallySizedBox(widthFactor: progress, child: DecoratedBox(decoration: BoxDecoration(color: const Color(0xFF39D353), borderRadius: BorderRadius.circular(5))))),
        const SizedBox(width: 10),
        for (final a in actions) Expanded(child: InkWell(onTap: a.$3, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 11, height: 11, decoration: BoxDecoration(color: Color(int.parse('FF${a.$1}', radix: 16)), shape: BoxShape.circle, border: Border.all(color: Colors.white54))),
          const SizedBox(width: 4), Flexible(child: Text(a.$2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
        ]))),
      ]),
    ));
  }

  Future<void> _openEpg() async {
    setState(() => _banner = true); _hideTimer?.cancel();
    if (_channel == null) return;
    try {
      final list = <TvProgram>[];
      for (var offset = -7; offset <= 7; offset++) list.addAll(await widget.api.getEpg(_channel!.id, offset: offset));
      if (!mounted) return;
      await showDialog<void>(context: context, barrierColor: Colors.black.withValues(alpha: .75), builder: (_) => _EpgDialog(channel: _channel!, programs: list));
      _armHide();
    } catch (_) {}
  }

  Widget _buildError() => Center(child: Container(
    constraints: const BoxConstraints(maxWidth: 460), padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: .88), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white35)),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, color: Colors.redAccent, size: 44), const SizedBox(height: 10),
      Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        FilledButton(onPressed: () => _tune(_index), child: const Text('Retry')),
        const SizedBox(width: 10), OutlinedButton(onPressed: _next, child: const Text('Next CH')),
      ]),
    ]),
  ));

  Widget _buildSettings() => Positioned.fill(child: Material(
    color: Colors.black.withValues(alpha: .60),
    child: Center(child: Container(
      width: 440, constraints: const BoxConstraints(maxHeight: 330),
      decoration: BoxDecoration(color: const Color(0xF5111622), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white54, width: 1.5)),
      child: Column(children: [
        Container(height: 56, color: const Color(0xFF1A202E), padding: const EdgeInsets.all(6), child: Row(children: [
          Expanded(child: _tab('Quality', Icons.high_quality, 0)),
          Expanded(child: _tab('Audio', Icons.graphic_eq, 1)),
          IconButton(onPressed: () { setState(() => _settings = false); _armHide(); }, icon: const Icon(Icons.close)),
        ])),
        Expanded(child: _settingsTab == 0 ? _qualityPanel() : _audioPanel()),
      ]),
    )),
  ));

  Widget _tab(String label, IconData icon, int tab) {
    final active = _settingsTab == tab;
    return Padding(padding: const EdgeInsets.all(2), child: TextButton.icon(
      onPressed: () => setState(() => _settingsTab = tab),
      icon: Icon(icon, color: active ? Colors.black : Colors.white), label: Text(label),
      style: TextButton.styleFrom(backgroundColor: active ? TvColors.blue : const Color(0xFF252D3F), foregroundColor: active ? Colors.black : Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
    ));
  }

  Widget _qualityPanel() => ListView(padding: const EdgeInsets.all(10), children: const [
    ListTile(leading: Icon(Icons.hd, color: TvColors.cyan), title: Text('Highest supported quality'), subtitle: Text('Auto-selected when the stream exposes tracks'), trailing: Icon(Icons.radio_button_checked, color: TvColors.cyan)),
    ListTile(leading: Icon(Icons.auto_awesome), title: Text('Auto (Adaptive)'), subtitle: Text('Adjusts quality dynamically based on network speed')),
  ]);

  Widget _audioPanel() => ListView(padding: const EdgeInsets.all(10), children: [
    ListTile(leading: Icon(_muted ? Icons.volume_off : Icons.volume_up), title: const Text('Sound'), subtitle: Text(_muted ? 'MUTED' : 'ON'), trailing: Switch(value: !_muted, onChanged: (_) => _toggleMute())),
    const ListTile(leading: Icon(Icons.audiotrack), title: Text('Auto (Default Audio)'), subtitle: Text('Use the stream default audio track')),
  ]);

  Widget _buildSearch() {
    final query = _search.text.toLowerCase();
    final results = query.isEmpty ? _channels.take(18).toList() : _channels.where((c) => c.name.toLowerCase().contains(query) || '${c.id}'.contains(query) || (c.languageName ?? '').toLowerCase().contains(query)).take(24).toList();
    return Positioned.fill(child: Material(
      color: Colors.black.withValues(alpha: .86),
      child: Center(child: Container(width: 760, height: 430, padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: const Color(0xF5111622), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white38)),
        child: Column(children: [
          Row(children: [
            const Icon(Icons.search, color: TvColors.cyan), const SizedBox(width: 10),
            Expanded(child: TextField(controller: _search, autofocus: true, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'Search live channels…', border: InputBorder.none))),
            IconButton(onPressed: () => setState(() => _searchMode = false), icon: const Icon(Icons.close)),
          ]),
          const Divider(color: Colors.white12),
          Expanded(child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, childAspectRatio: 2.4, mainAxisSpacing: 8, crossAxisSpacing: 8),
            itemCount: results.length,
            itemBuilder: (_, i) {
              final c = results[i];
              return InkWell(onTap: () { final idx = _channels.indexOf(c); setState(() => _searchMode = false); _tune(idx); },
                child: DecoratedBox(decoration: BoxDecoration(color: const Color(0xFF1A202E), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white12)),
                  child: Center(child: Text('${c.id}  ${c.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)))));
            },
          )),
        ]),
      )),
    ));
  }

  String _time(DateTime value) => DateFormat('hh:mm a').format(value);

  @override void dispose() {
    _dialTimer?.cancel(); _hideTimer?.cancel(); _playerChannel = null; _focus.dispose(); _search.dispose(); super.dispose();
  }
}

class _Loader extends StatelessWidget {
  const _Loader({required this.label});
  final String label;
  @override Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    const CircularProgressIndicator(color: Color(0xFF00B4FF)), const SizedBox(height: 12), Text(label),
  ]);
}

class _EpgDialog extends StatelessWidget {
  const _EpgDialog({required this.channel, required this.programs});
  final TvChannel channel; final List<TvProgram> programs;
  @override Widget build(BuildContext context) {
    final sorted = [...programs]..sort((a,b) => a.start.compareTo(b.start));
    return AlertDialog(
      backgroundColor: const Color(0xF5111622),
      title: Text('${channel.name} • 15-Day Guide'),
      content: SizedBox(width: 700, height: 430, child: ListView.separated(
        itemCount: sorted.length, separatorBuilder: (_,__) => const Divider(color: Colors.white12),
        itemBuilder: (_,i) { final p = sorted[i]; return ListTile(
          title: Text(p.title),
          subtitle: Text('${DateFormat('EEE dd MMM, hh:mm a').format(p.start)} - ${DateFormat('hh:mm a').format(p.end)}'),
          trailing: p.isLive ? const Text('LIVE', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)) : null,
        );},
      )),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
