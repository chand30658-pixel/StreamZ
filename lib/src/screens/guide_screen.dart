import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../services/jio_api.dart';
import '../theme.dart';
import 'player_screen.dart';

class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key, required this.api});
  final JioApi api;
  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  final FocusNode _focus = FocusNode();
  final ScrollController _horizontal = ScrollController();
  final Map<int, List<TvProgram>> _programs = {};
  List<TvChannel> _channels = const [];
  int _selectedChannel = 0;
  int _selectedProgram = 0;
  bool _loading = true;
  String? _error;

  static const double _slotWidth = 150;
  static const double _sidebarWidth = 210;
  static const double _rowHeight = 82;
  static const int _hours = 6;

  DateTime get _gridStart {
    final now = DateTime.now();
    final minute = now.minute < 30 ? 0 : 30;
    return DateTime(now.year, now.month, now.day, now.hour, minute);
  }

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  Future<void> _load() async {
    try {
      final channels = await widget.api.loadChannels();
      if (!mounted) return;
      setState(() {
        _channels = channels.take(30).toList();
        _loading = false;
      });
      await _loadGuide();
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Unable to load TV Guide: ' + e.toString(); });
    }
  }

  Future<void> _loadGuide() async {
    final targets = _channels.take(18).toList();
    final results = await Future.wait(targets.map((channel) async {
      try {
        return MapEntry(channel.id, await widget.api.getEpg(channel.id));
      } catch (_) {
        return MapEntry(channel.id, <TvProgram>[]);
      }
    }));
    if (!mounted) return;
    setState(() {
      for (final entry in results) {
        _programs[entry.key] = entry.value;
      }
    });
  }

  List<TvProgram> _visiblePrograms(TvChannel channel) {
    final start = _gridStart.subtract(const Duration(minutes: 15));
    final end = _gridStart.add(const Duration(hours: _hours));
    return (_programs[channel.id] ?? const <TvProgram>[])
        .where((p) => p.end.isAfter(start) && p.start.isBefore(end))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  TvChannel? get _selected =>
      _channels.isEmpty ? null : _channels[_selectedChannel.clamp(0, _channels.length - 1)];

  void _moveChannel(int delta) {
    if (_channels.isEmpty) return;
    setState(() {
      _selectedChannel = (_selectedChannel + delta).clamp(0, _channels.length - 1);
      _selectedProgram = 0;
    });
  }

  void _moveProgram(int delta) {
    final channel = _selected;
    if (channel == null) return;
    final list = _visiblePrograms(channel);
    if (list.isEmpty) return;
    setState(() => _selectedProgram = (_selectedProgram + delta).clamp(0, list.length - 1));
  }

  void _playSelected() {
    if (_selected == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerScreen(api: widget.api)));
  }

  void _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.channelUp) {
      _moveChannel(-1);
    } else if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.channelDown) {
      _moveChannel(1);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _moveProgram(-1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _moveProgram(1);
    } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.select || key == LogicalKeyboardKey.numpadEnter) {
      _playSelected();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08090E),
      body: KeyboardListener(
        focusNode: _focus,
        onKeyEvent: _onKey,
        child: _loading ? const Center(child: _GuideLoader()) : _error != null ? _buildError() : _buildGuide(),
      ),
    );
  }

  Widget _buildGuide() {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: Row(
            children: [
              _buildSidebar(),
              Expanded(
                child: SingleChildScrollView(
                  controller: _horizontal,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: _hours * 2 * _slotWidth,
                    child: Column(
                      children: [
                        _buildTimeline(),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _channels.length,
                            itemExtent: _rowHeight,
                            itemBuilder: (_, index) => _buildProgramRow(index),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        _buildFooter(),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 92,
      decoration: const BoxDecoration(color: Color(0xFF0C0D13), border: Border(bottom: BorderSide(color: Colors.white12))),
      child: Row(
        children: [
          SizedBox(
            width: _sidebarWidth,
            child: Row(
              children: [
                Container(
                  width: 66,
                  height: double.infinity,
                  color: const Color(0xFF15161E),
                  alignment: Alignment.center,
                  child: const Text('STREAMZ', style: TextStyle(color: TvColors.blue, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('TV Guide', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                        Text(DateFormat('EEE, dd MMM').format(DateTime.now()), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                for (final item in ['Yesterday', 'Today', 'Tomorrow'])
                  Expanded(
                    child: Center(
                      child: Text(item, style: TextStyle(
                        color: item == 'Today' ? Colors.white : Colors.white38,
                        fontWeight: item == 'Today' ? FontWeight.w800 : FontWeight.w500,
                        fontSize: 13,
                      )),
                    ),
                  ),
                const SizedBox(width: 22),
                Padding(
                  padding: const EdgeInsets.only(right: 18),
                  child: Text(DateFormat('HH:mm').format(DateTime.now()), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return SizedBox(
      width: _sidebarWidth,
      child: Column(
        children: [
          Container(
            height: 54,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            color: const Color(0xFF11131A),
            child: const Text('CHANNELS', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _channels.length,
              itemExtent: _rowHeight,
              itemBuilder: (_, index) {
                final channel = _channels[index];
                final selected = index == _selectedChannel;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFF252936) : const Color(0xFF101219),
                    border: Border(right: BorderSide(color: selected ? TvColors.blue : Colors.transparent, width: 4), bottom: const BorderSide(color: Colors.white10)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(width: 34, child: Center(child: Text((index + 1).toString(), style: TextStyle(color: selected ? Colors.white : Colors.white54, fontSize: 12, fontWeight: FontWeight.w800)))),
                      Container(
                        width: 48,
                        height: 48,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5)),
                        child: channel.logoUrl == null
                            ? const Icon(Icons.tv, color: Colors.black54)
                            : Image.network(channel.logoUrl!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.tv, color: Colors.black54)),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: selected ? Colors.white : Colors.white70, fontSize: 13, fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
                            Text(channel.isHd ? 'HD' : (channel.languageName ?? 'Live TV'), style: const TextStyle(color: Colors.white38, fontSize: 10)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    final start = _gridStart;
    return SizedBox(
      height: 54,
      child: Row(
        children: List.generate(_hours * 2, (i) {
          final time = start.add(Duration(minutes: i * 30));
          return Container(
            width: _slotWidth,
            decoration: const BoxDecoration(color: Color(0xFF11131A), border: Border(right: BorderSide(color: Colors.white12))),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 14),
            child: Text(DateFormat('HH:mm').format(time), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white70)),
          );
        }),
      ),
    );
  }

  Widget _buildProgramRow(int channelIndex) {
    final channel = _channels[channelIndex];
    final programs = _visiblePrograms(channel);
    return Container(
      height: _rowHeight,
      color: channelIndex.isEven ? const Color(0xFF0E1016) : const Color(0xFF11131A),
      child: Stack(
        children: [
          Row(children: List.generate(_hours * 2, (_) => Container(width: _slotWidth, decoration: const BoxDecoration(border: Border(right: BorderSide(color: Colors.white10)))))),
          for (var i = 0; i < programs.length; i++) _programCard(channelIndex, i, programs[i]),
        ],
      ),
    );
  }

  Widget _programCard(int channelIndex, int programIndex, TvProgram program) {
    final gridStart = _gridStart;
    final startMinutes = program.start.difference(gridStart).inMinutes;
    final endMinutes = program.end.difference(gridStart).inMinutes;
    final left = (startMinutes / 30 * _slotWidth).clamp(2.0, _hours * 2 * _slotWidth - 4);
    final width = ((endMinutes - startMinutes) / 30 * _slotWidth).clamp(82.0, _hours * 2 * _slotWidth - left - 4);
    final selected = channelIndex == _selectedChannel && programIndex == _selectedProgram;
    final image = program.thumbnailUrl ?? program.posterUrl;

    return Positioned(
      left: left,
      top: 7,
      width: width,
      height: _rowHeight - 14,
      child: GestureDetector(
        onTap: () => setState(() { _selectedChannel = channelIndex; _selectedProgram = programIndex; }),
        onDoubleTap: _playSelected,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF343846) : const Color(0xFF1A1C25),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: selected ? TvColors.blue : Colors.white10, width: selected ? 2 : 1),
            boxShadow: selected ? const [BoxShadow(color: Color(0x550099FF), blurRadius: 10)] : null,
          ),
          child: Row(
            children: [
              if (image != null && width > 190)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(width: 72, height: double.infinity, child: Image.network(image, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox())),
                ),
              if (image != null && width > 190) const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(DateFormat('HH:mm').format(program.start), style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(program.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: width > 190 ? 14 : 12, fontWeight: FontWeight.w800)),
                    if (program.isLive) const Text('LIVE NOW', style: TextStyle(color: Color(0xFF4ADE80), fontSize: 9, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      height: 52,
      decoration: const BoxDecoration(color: Color(0xFF0B0C12), border: Border(top: BorderSide(color: Colors.white12))),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          _action('OK', 'Watch', TvColors.blue),
          _action('↑↓', 'Channel', Colors.white70),
          _action('←→', 'Program', Colors.white70),
          _action('0-9', 'Tune', Colors.white70),
          _action('GUIDE', 'TV Guide', Colors.white70),
          const Spacer(),
          Text(_channels.length.toString() + ' channels', style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _action(String key, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 22),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: .12), border: Border.all(color: color.withValues(alpha: .45)), borderRadius: BorderRadius.circular(4)),
            child: Text(key, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(color: TvColors.panelStrong, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.live_tv, size: 48, color: TvColors.cyan),
            const SizedBox(height: 12),
            const Text('TV Guide unavailable', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white60)),
            const SizedBox(height: 18),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _focus.dispose();
    _horizontal.dispose();
    super.dispose();
  }
}

class _GuideLoader extends StatelessWidget {
  const _GuideLoader();
  @override
  Widget build(BuildContext context) => const Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      CircularProgressIndicator(color: TvColors.blue),
      SizedBox(height: 14),
      Text('Loading TV Guide…', style: TextStyle(fontWeight: FontWeight.w700)),
      SizedBox(height: 5),
      Text('Loading channels and programme schedule', style: TextStyle(color: Colors.white54, fontSize: 12)),
    ],
  );
}
