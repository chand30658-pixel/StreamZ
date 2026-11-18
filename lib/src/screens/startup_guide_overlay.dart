import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../theme.dart';

class StartupGuideOverlay extends StatefulWidget {
  const StartupGuideOverlay({
    super.key,
    required this.channels,
    required this.programs,
    required this.onSelect,
    required this.onClose,
  });

  final List<TvChannel> channels;
  final Map<int, List<TvProgram>> programs;
  final ValueChanged<TvChannel> onSelect;
  final VoidCallback onClose;

  @override
  State<StartupGuideOverlay> createState() => _StartupGuideOverlayState();
}

class _StartupGuideOverlayState extends State<StartupGuideOverlay> {
  String _category = 'All';
  String _language = 'All';
  int _selected = 0;

  List<String> get _categories {
    final values = widget.channels.map((c) => c.category).whereType<String>().where((v) => v.trim().isNotEmpty).toSet().toList()..sort();
    return ['All', ...values];
  }

  List<String> get _languages {
    final values = widget.channels.map((c) => c.languageName).whereType<String>().where((v) => v.trim().isNotEmpty).toSet().toList()..sort();
    return ['All', ...values];
  }

  List<TvChannel> get _filtered => widget.channels.where((c) {
    final catOk = _category == 'All' || c.category == _category;
    final langOk = _language == 'All' || c.languageName == _language;
    return catOk && langOk;
  }).toList();

  @override
  Widget build(BuildContext context) {
    final channels = _filtered;
    if (channels.isEmpty) {
      return _shell(const Center(child: Text('No channels found for this filter.')));
    }
    final selectedIndex = _selected.clamp(0, channels.length - 1);
    final selectedChannel = channels[selectedIndex];
    final programs = widget.programs[selectedChannel.id] ?? const <TvProgram>[];

    return _shell(
      Column(
        children: [
          _header(),
          Expanded(
            child: Row(
              children: [
                _sideFilters(),
                Expanded(child: _programGrid(channels, programs, selectedIndex)),
              ],
            ),
          ),
          _footer(),
        ],
      ),
    );
  }

  Widget _shell(Widget child) => Positioned.fill(
    child: Material(
      color: Colors.black.withValues(alpha: .82),
      child: SafeArea(child: child),
    ),
  );

  Widget _header() => Container(
    height: 74,
    padding: const EdgeInsets.symmetric(horizontal: 22),
    decoration: const BoxDecoration(
      color: Color(0xF20B0D13),
      border: Border(bottom: BorderSide(color: Colors.white12)),
    ),
    child: Row(
      children: [
        const Icon(Icons.live_tv, color: TvColors.blue, size: 28),
        const SizedBox(width: 10),
        const Text('TV GUIDE', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        const SizedBox(width: 28),
        _date('Yesterday'),
        _date('Today', active: true),
        _date('Tomorrow'),
        const Spacer(),
        Text(DateFormat('EEE, dd MMM • hh:mm a').format(DateTime.now()), style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(width: 18),
        IconButton(onPressed: widget.onClose, icon: const Icon(Icons.close), tooltip: 'Back to TV'),
      ],
    ),
  );

  Widget _date(String text, {bool active = false}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Text(text, style: TextStyle(color: active ? Colors.white : Colors.white38, fontWeight: active ? FontWeight.w800 : FontWeight.w500)),
  );

  Widget _sideFilters() => Container(
    width: 210,
    decoration: const BoxDecoration(color: Color(0xEE0C0F16), border: Border(right: BorderSide(color: Colors.white10))),
    child: ListView(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
      children: [
        const Text('CATEGORY', style: TextStyle(color: Colors.white45, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.3)),
        const SizedBox(height: 7),
        for (final item in _categories) _filterButton(item, _category == item, () => setState(() { _category = item; _selected = 0; })),
        const SizedBox(height: 18),
        const Text('LANGUAGE', style: TextStyle(color: Colors.white45, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.3)),
        const SizedBox(height: 7),
        for (final item in _languages) _filterButton(item, _language == item, () => setState(() { _language = item; _selected = 0; })),
      ],
    ),
  );

  Widget _filterButton(String text, bool active, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: InkWell(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: active ? TvColors.blue : const Color(0xFF171B25),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? TvColors.blue : Colors.white10),
        ),
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: active ? Colors.black : Colors.white70, fontSize: 12, fontWeight: active ? FontWeight.w900 : FontWeight.w600)),
      ),
    ),
  );

  Widget _programGrid(List<TvChannel> channels, List<TvProgram> selectedPrograms, int selectedIndex) {
    return Column(
      children: [
        Container(
          height: 48,
          color: const Color(0xFF11141C),
          child: Row(
            children: [
              const SizedBox(width: 12),
              const Text('CHANNELS', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
              const Spacer(),
              const Text('NOW', style: TextStyle(color: Colors.white38, fontSize: 10)),
              const SizedBox(width: 105),
              const Text('NEXT', style: TextStyle(color: Colors.white38, fontSize: 10)),
              const SizedBox(width: 30),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: channels.length,
            itemExtent: 78,
            itemBuilder: (_, i) {
              final channel = channels[i];
              final selected = i == selectedIndex;
              final epg = widget.programs[channel.id] ?? const <TvProgram>[];
              TvProgram? live;
              TvProgram? next;
              final now = DateTime.now();
              for (final p in epg) {
                if (!now.isBefore(p.start) && now.isBefore(p.end)) live = p;
                if (next == null && p.start.isAfter(now)) next = p;
              }
              return InkWell(
                onTap: () {
                  setState(() => _selected = i);
                  widget.onSelect(channel);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFF292F3E) : const Color(0xFF12151D),
                    border: Border(bottom: const BorderSide(color: Colors.white10), left: BorderSide(color: selected ? TvColors.blue : Colors.transparent, width: 4)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(width: 42, child: Center(child: Text((i + 1).toString(), style: TextStyle(color: selected ? Colors.white : Colors.white45, fontWeight: FontWeight.w800)))),
                      Container(width: 46, height: 46, padding: const EdgeInsets.all(5), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5)), child: channel.logoUrl == null ? const Icon(Icons.tv, color: Colors.black45) : Image.network(channel.logoUrl!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.tv, color: Colors.black45))),
                      const SizedBox(width: 10),
                      SizedBox(width: 150, child: Text(channel.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w900 : FontWeight.w600))),
                      Expanded(child: _showCell(live, selected, true)),
                      Expanded(child: _showCell(next, false, false)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _showCell(TvProgram? program, bool selected, bool live) {
    if (program == null) return const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('—', style: TextStyle(color: Colors.white24)));
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: live && selected ? TvColors.blue : const Color(0xFF1B1F29),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: live && selected ? TvColors.blue : Colors.white10),
      ),
      child: Row(
        children: [
          if ((program.thumbnailUrl ?? program.posterUrl) != null)
            ClipRRect(borderRadius: BorderRadius.circular(3), child: SizedBox(width: 48, height: 46, child: Image.network(program.thumbnailUrl ?? program.posterUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()))),
          const SizedBox(width: 7),
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(program.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: live && selected ? Colors.black : Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(DateFormat('HH:mm').format(program.start), style: TextStyle(color: live && selected ? Colors.black87 : Colors.white45, fontSize: 10)),
          ])),
        ],
      ),
    );
  }

  Widget _footer() => Container(
    height: 52,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    decoration: const BoxDecoration(color: Color(0xF20B0D13), border: Border(top: BorderSide(color: Colors.white12))),
    child: Row(children: [
      _key('OK', 'Select / Play', TvColors.blue),
      _key('↑↓', 'Channels', Colors.white70),
      _key('←→', 'Browse', Colors.white70),
      _key('GUIDE', 'Guide', Colors.white70),
      const Spacer(),
      const Text('Select Category / Language • Choose Channel • OK to watch', style: TextStyle(color: Colors.white38, fontSize: 11)),
    ]),
  );

  Widget _key(String key, String label, Color color) => Padding(
    padding: const EdgeInsets.only(right: 24),
    child: Row(children: [
      Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4), decoration: BoxDecoration(color: color.withValues(alpha: .12), border: Border.all(color: color.withValues(alpha: .45)), borderRadius: BorderRadius.circular(4)), child: Text(key, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900))),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
    ]),
  );
}
