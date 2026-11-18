import 'package:flutter/material.dart';
import '../models.dart';
import '../services/jio_api.dart';
import '../theme.dart';
import 'channel_player_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api});
  final JioApi api;
  @override State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  List<TvChannel> _channels = const [];
  String _language = 'All', _genre = 'All', _query = '';
  bool _loading = true;
  String? _error;

  List<String> _values(Iterable<String?> values) {
    final list = values.whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList()..sort();
    return ['All', ...list];
  }
  List<String> get _languages => _values(_channels.map((c) => c.languageName));
  List<String> get _genres => _values(_channels.map((c) => c.category));
  List<TvChannel> get _filtered => _channels.where((c) {
    final q = _query.trim().toLowerCase();
    return (_language == 'All' || c.languageName == _language) &&
        (_genre == 'All' || c.category == _genre) &&
        (q.isEmpty || c.name.toLowerCase().contains(q) || c.id.toString() == q);
  }).toList();

  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await widget.api.loadChannels();
      if (!mounted) return;
      setState(() { _channels = data; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }
  Future<void> _open(TvChannel c) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChannelPlayerScreen(api: widget.api, channel: c)));

  @override Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 700;
    return Scaffold(
      backgroundColor: const Color(0xFF080A0F),
      appBar: _header(mobile),
      body: _loading ? const Center(child: CircularProgressIndicator(color: TvColors.blue))
          : _error != null ? _errorView()
          : RefreshIndicator(
              onRefresh: _load, color: TvColors.blue,
              child: CustomScrollView(slivers: [
                SliverToBoxAdapter(child: _tabs(mobile)),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(mobile ? 10 : 24, 12, mobile ? 10 : 24, 28),
                  sliver: _grid(mobile),
                ),
              ]),
            ),
    );
  }

  PreferredSizeWidget _header(bool mobile) => AppBar(
    backgroundColor: const Color(0xFF0D1017), elevation: 0, titleSpacing: mobile ? 14 : 24,
    title: const Text('StreamZ', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
    actions: [
      IconButton(onPressed: _search, tooltip: 'Search', icon: const Icon(Icons.search)),
      IconButton(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings coming soon'))), tooltip: 'Settings', icon: const Icon(Icons.settings_outlined)),
      SizedBox(width: mobile ? 4 : 16),
    ],
  );

  Widget _tabs(bool mobile) => Container(
    color: const Color(0xFF0D1017),
    child: Column(children: [
      _tabRow('Language', _languages, _language, (v) => setState(() => _language = v), mobile),
      _tabRow('Genre & Category', _genres, _genre, (v) => setState(() => _genre = v), mobile),
    ]),
  );

  Widget _tabRow(String label, List<String> items, String selected, ValueChanged<String> onChanged, bool mobile) => SizedBox(
    height: mobile ? 52 : 58,
    child: Row(children: [
      SizedBox(width: mobile ? 105 : 155, child: Padding(
        padding: EdgeInsets.only(left: mobile ? 14 : 24),
        child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w800)),
      )),
      Expanded(child: ListView.separated(
        scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        itemCount: items.length, separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (_, i) {
          final active = items[i] == selected;
          return ChoiceChip(
            label: Text(items[i]), selected: active, onSelected: (_) => onChanged(items[i]),
            selectedColor: TvColors.blue, backgroundColor: const Color(0xFF1A1F2A),
            side: BorderSide(color: active ? TvColors.blue : Colors.white12),
            labelStyle: TextStyle(color: active ? Colors.black : Colors.white70, fontWeight: FontWeight.w700, fontSize: 12),
          );
        },
      )),
    ]),
  );

  Widget _grid(bool mobile) {
    final list = _filtered;
    if (list.isEmpty) return const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(50), child: Center(child: Text('No channels found', style: TextStyle(color: Colors.white54)))));
    return SliverGrid(
      delegate: SliverChildBuilderDelegate((_, i) => _card(list[i], mobile), childCount: list.length),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: mobile ? 160 : 190, mainAxisSpacing: mobile ? 10 : 14,
        crossAxisSpacing: mobile ? 10 : 14, childAspectRatio: 1,
      ),
    );
  }

  Widget _card(TvChannel c, bool mobile) => InkWell(
    borderRadius: BorderRadius.circular(12), onTap: () => _open(c),
    child: Ink(
      decoration: BoxDecoration(color: const Color(0xFF131720), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
      padding: EdgeInsets.all(mobile ? 9 : 13),
      child: Column(children: [
        Expanded(child: Container(
          width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(9)),
          padding: const EdgeInsets.all(10),
          child: c.logoUrl == null ? const Icon(Icons.live_tv, color: Colors.black45, size: 42)
              : Image.network(c.logoUrl!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.live_tv, color: Colors.black45, size: 42)),
        )),
        const SizedBox(height: 8),
        Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        const SizedBox(height: 3),
        Text(c.isHd ? 'HD' : (c.languageName ?? 'Live TV'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ]),
    ),
  );

  Widget _errorView() => Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.cloud_off, size: 46, color: Colors.white38),
      const SizedBox(height: 12), const Text('Unable to load channels'),
      const SizedBox(height: 8), Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
      const SizedBox(height: 18), FilledButton(onPressed: _load, child: const Text('Retry')),
    ]),
  ));

  Future<void> _search() async {
    _searchController.text = _query;
    final value = await showDialog<String>(context: context, builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF151A24), title: const Text('Search channels'),
      content: TextField(controller: _searchController, autofocus: true, decoration: const InputDecoration(hintText: 'Channel name or number')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _searchController.text), child: const Text('Search')),
      ],
    ));
    if (value != null && mounted) setState(() => _query = value);
  }
  @override void dispose() { _searchController.dispose(); super.dispose(); }
}
