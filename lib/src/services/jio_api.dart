import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

class JioApi {
  static const _channelV31 =
      'https://jiotv.data.cdn.jio.com/apis/v3.1/getMobileChannelList/get/';
  static const _channelV30 =
      'https://jiotv.data.cdn.jio.com/apis/v3.0/getMobileChannelList/get/';
  static const _epgUrl =
      'https://jiotv.data.cdn.jio.com/apis/v1.3/getepg/get';
  static const _extraFeed =
      'https://api.npoint.io/9db02feba76eb297fc65?v=1794981838621';
  static const _workerResolver =
      'https://eliteapiyash.streamxlive.workers.dev';
  static const _mobileChromeUa =
      'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

  final http.Client _client = http.Client();

  String get _apiKey =>
      const String.fromEnvironment('JIO_API_KEY', defaultValue: '');
  String get _appKey =>
      const String.fromEnvironment('JIO_APP_KEY', defaultValue: '');

  Map<String, String> get _headers => {
        'User-Agent': 'JioTV',
        'Accept': 'application/json',
        'Origin': 'https://www.jiotv.com',
        'Referer': 'https://www.jiotv.com/tv-guide',
        if (_apiKey.isNotEmpty) 'x-api-key': _apiKey,
        if (_appKey.isNotEmpty) 'appkey': _appKey,
      };

  Future<List<TvChannel>> loadChannels() async {
    List<dynamic> jio = const [];
    try {
      jio = await _getChannelList(_channelV31);
    } catch (_) {
      jio = await _getChannelList(_channelV30);
    }

    List<dynamic> extra = const [];
    try {
      final response = await _client.get(
        Uri.parse(const String.fromEnvironment(
          'EXTRA_FEED_URL',
          defaultValue: _extraFeed,
        )),
        headers: const {'Accept': 'application/json'},
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = jsonDecode(response.body);
        extra = body is List ? body : (body is Map ? [body] : const []);
      }
    } catch (_) {}

    final merged = <int, TvChannel>{};
    for (final raw in jio) {
      final c = _fromJio(raw);
      if (c != null) merged[c.id] = c;
    }
    for (final raw in extra) {
      final c = _fromExtra(raw);
      if (c == null) continue;
      final old = merged[c.id];
      merged[c.id] = old == null
          ? c
          : old.copyWith(
              logoUrl: old.logoUrl ?? c.logoUrl,
              category: old.category ?? c.category,
              categoryId: old.categoryId ?? c.categoryId,
              languageId: old.languageId ?? c.languageId,
              languageName: old.languageName ?? c.languageName,
              playbackUrl: c.playbackUrl ?? old.playbackUrl,
              playbackHeaders: c.playbackHeaders.isEmpty
                  ? old.playbackHeaders
                  : c.playbackHeaders,
              clearKeyJson: c.clearKeyJson ?? old.clearKeyJson,
            );
    }

    final list = merged.values.toList()
      ..sort((a, b) {
        final order = a.channelOrder.compareTo(b.channelOrder);
        return order == 0 ? a.name.compareTo(b.name) : order;
      });
    return list;
  }

  Future<List<dynamic>> _getChannelList(String url) async {
    final uri = Uri.parse(url).replace(queryParameters: const {
      'os': 'android',
      'devicetype': 'phone',
      'usertype': 'tvYR7NSNn7rymo3F',
    });
    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Channel list HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is Map && decoded['result'] is List) {
      return decoded['result'] as List;
    }
    if (decoded is List) return decoded;
    throw const FormatException('Unexpected channel list response');
  }

  TvChannel? _fromJio(dynamic value) {
    if (value is! Map) return null;
    final id = _int(value['channel_id'] ?? value['stb_channel_id']);
    final name = '${value['channel_name'] ?? ''}'.trim();
    if (id == null || id <= 0 || name.isEmpty) return null;
    return TvChannel(
      id: id,
      name: name,
      logoUrl: _logo(value['logoUrl']),
      categoryId: _int(value['channelCategoryId']),
      languageId: _int(value['channelLanguageId']),
      isHd: value['isHD'] == true,
      channelOrder: _int(value['channel_order']) ?? 0,
      catchup: value['isCatchupAvailable'] == true,
    );
  }

  TvChannel? _fromExtra(dynamic value) {
    if (value is! Map) return null;
    final id = _int(value['channel_id'] ??
        value['channelId'] ??
        value['id'] ??
        value['chid'] ??
        value['ChannelID'] ??
        value['channelNo']);
    final synthetic = id ?? _syntheticId(value);
    final name = _firstString(value, [
      'channel_name',
      'channelName',
      'name',
      'title',
      'tvg_name',
    ]);
    if (name == null || name.isEmpty) return null;

    final parsed = _extractPlayback(value);
    final category = _firstString(value, [
      'channel_genre',
      'cat',
      'categoryName',
      'category',
      'genre',
      'group_title',
      'group',
    ]);
    final language = _firstString(value, ['languageName', 'language', 'lang']);

    return TvChannel(
      id: synthetic,
      name: name,
      logoUrl: _logo(_firstString(value, [
        'channel_logo',
        'logoUrl',
        'logo',
        'tvg_logo',
        'icon',
        'image',
        'img',
        'thumbnail',
      ])),
      category: _cleanCategory(category),
      languageName: _cleanLanguage(language),
      channelOrder: _int(value['channelOrder'] ?? value['channel_order']) ?? 0,
      playbackUrl: parsed?.url,
      playbackHeaders: parsed?.headers ?? const {},
      clearKeyJson: parsed?.clearKeyJson,
    );
  }

  int _syntheticId(Map value) {
    var hash = 0;
    for (final code in jsonEncode(value).codeUnits) {
      hash = (hash * 31 + code) & 0x7fffffff;
    }
    return 1000000 + (hash % 899999);
  }

  PlaybackSource? _extractPlayback(Map value) {
    dynamic source;
    for (final key in [
      'channel_url',
      'stream_url',
      'streamUrl',
      'play_url',
      'mpd_url',
      'm3u8_url',
      'hls_url',
      'url',
      'link',
      'ready_to_use_link',
    ]) {
      if (value[key] is String && '${value[key]}'.trim().isNotEmpty) {
        source = value[key];
        break;
      }
    }

    if (source == null) {
      for (final key in [
        'play_data',
        'playData',
        'playback',
        'stream',
        'source',
        'mpd_data',
      ]) {
        if (value[key] is Map) {
          final nested = _extractPlayback(value[key] as Map);
          if (nested != null) return nested;
        }
      }
      return null;
    }

    final parts = source.toString().split('|');
    final url = parts.first.trim();
    if (url.isEmpty) return null;

    final headers = <String, String>{};
    String? drmScheme;
    String? drmLicense;

    if (parts.length > 1) {
      for (final pair in parts.skip(1).join('|').split('&')) {
        final i = pair.indexOf('=');
        if (i <= 0) continue;
        final key = Uri.decodeComponent(pair.substring(0, i));
        final val = Uri.decodeComponent(pair.substring(i + 1));
        if (key == 'cookie' && val.isNotEmpty) headers['Cookie'] = val;
        if (key == 'userAgent' && val.isNotEmpty) headers['User-Agent'] = val;
        if (key == 'drmScheme') drmScheme = val;
        if (key == 'drmLicense') drmLicense = val;
      }
    }

    if (value['cookie'] is String && '${value['cookie']}'.isNotEmpty) {
      headers['Cookie'] = value['cookie'].toString();
    }
    if (value['userAgent'] is String && '${value['userAgent']}'.isNotEmpty) {
      headers['User-Agent'] = value['userAgent'].toString();
    }

    final clearKey = drmScheme == 'clearkey' && drmLicense != null
        ? _clearKeyJson(drmLicense)
        : null;

    return PlaybackSource(url: url, headers: headers, clearKeyJson: clearKey);
  }

  String? _clearKeyJson(String license) {
    final keys = <Map<String, String>>[];
    for (final token in license.split(',')) {
      final pair = token.split(':');
      if (pair.length < 2) continue;
      final kid = _keyBytes(pair[0].trim());
      final key = _keyBytes(pair.sublist(1).join(':').trim());
      if (kid != null && key != null) {
        keys.add({'kty': 'oct', 'kid': kid, 'k': key});
      }
    }
    if (keys.isEmpty) return null;
    return jsonEncode({'keys': keys, 'type': 'temporary'});
  }

  String? _keyBytes(String value) {
    if (RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(value)) {
      final bytes = <int>[];
      for (var i = 0; i < value.length; i += 2) {
        bytes.add(int.parse(value.substring(i, i + 2), radix: 16));
      }
      return base64UrlEncode(bytes).replaceAll('=', '');
    }
    if (value.isEmpty) return null;
    return value.replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
  }

  Future<TvChannel> resolvePlayback(TvChannel channel) async {
    if (channel.id >= 1000000) {
      return channel;
    }

    try {
      final uri = Uri.parse(_workerResolver).replace(
        queryParameters: {'id': '${channel.id}'},
      );
      final response = await _client.get(
        uri,
        headers: {
          'User-Agent': _mobileChromeUa,
          'Accept': 'application/json,text/plain,*/*',
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Worker HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      final data = _firstMap(decoded);
      if (data == null) {
        throw const FormatException('Worker returned no playback object');
      }

      final source = _extractWorkerSource(data);
      if (source == null) {
        throw const FormatException('Worker returned no playable URL');
      }

      return channel.copyWith(
        playbackUrl: source.url,
        playbackHeaders: source.headers,
        clearKeyJson: source.clearKeyJson,
      );
    } catch (_) {
      return channel;
    }
  }

  Map<String, dynamic>? _firstMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is List) {
      for (final item in value) {
        if (item is Map) return Map<String, dynamic>.from(item);
      }
    }
    return null;
  }

  PlaybackSource? _extractWorkerSource(Map<String, dynamic> value) {
    String? url = _firstString(value, [
      'ready_to_use_link',
      'mpd_url',
      'm3u8_url',
      'hls_url',
      'stream_url',
      'streamUrl',
      'channel_url',
      'url',
      'link',
    ]);
    Map? nestedSource;
    if (url == null || url.isEmpty) {
      for (final key in ['play_data','playData','playback','stream','source','mpd_data','data']) {
        if (value[key] is Map) {
          final nested = value[key] as Map;
          final nestedUrl = _firstString(nested, [
            'ready_to_use_link','mpd_url','m3u8_url','hls_url',
            'stream_url','streamUrl','channel_url','url','link'
          ]);
          if (nestedUrl != null && nestedUrl.isNotEmpty) {
            url = nestedUrl;
            nestedSource = nested;
            break;
          }
        }
      }
    }
    if (url == null || url.isEmpty) return null;

    final rawParts = url.split('|');
    final manifestUrl = rawParts.first.trim();
    final headers = <String, String>{'User-Agent': _mobileChromeUa, 'Origin': 'https://www.jiotv.com', 'Referer': 'https://www.jiotv.com/tv-guide', 'Accept': '*/*'};
    String? pipeDrmScheme;
    String? pipeDrmLicense;

    final cookie = _firstString(value, ['cookie', 'Cookie']) ?? _firstString(nestedSource ?? <String, dynamic>{}, ['cookie', 'Cookie']);
    if (cookie != null && cookie.isNotEmpty) headers['Cookie'] = cookie;

    if (rawParts.length > 1) {
      for (final pair in rawParts.skip(1).join('|').split('&')) {
        final separator = pair.indexOf('=');
        if (separator <= 0) continue;
        final key = Uri.decodeComponent(pair.substring(0, separator));
        final val = Uri.decodeComponent(pair.substring(separator + 1));
        if (key == 'cookie' && val.isNotEmpty) headers['Cookie'] = val;
        if (key == 'userAgent' && val.isNotEmpty) headers['User-Agent'] = val;
        if (key == 'drmScheme') pipeDrmScheme = val;
        if (key == 'drmLicense') pipeDrmLicense = val;
      }
    }

    final nested = <Map>[
      if (value['play_data'] is Map) value['play_data'] as Map,
      if (value['playData'] is Map) value['playData'] as Map,
      if (value['playback'] is Map) value['playback'] as Map,
      if (value['stream'] is Map) value['stream'] as Map,
      if (value['source'] is Map) value['source'] as Map,
      if (value['mpd_data'] is Map) value['mpd_data'] as Map,
    ];

    String? keyId = _firstString(value, ['keyId', 'kid']);
    String? key = _firstString(value, ['key']);
    String? allKeys = _firstString(value, ['all_keys', 'allKeys']);

    for (final item in nested) {
      keyId ??= _firstString(item, ['keyId', 'kid']);
      key ??= _firstString(item, ['key']);
      allKeys ??= _firstString(item, ['all_keys', 'allKeys']);
      final nestedCookie = _firstString(item, ['cookie', 'Cookie']);
      if (nestedCookie != null && nestedCookie.isNotEmpty) {
        headers['Cookie'] = nestedCookie;
      }
    }

    final pipeClearKey = pipeDrmScheme?.toLowerCase() == 'clearkey' &&
            pipeDrmLicense != null
        ? _clearKeyJson(pipeDrmLicense)
        : null;

    return PlaybackSource(
      url: manifestUrl,
      headers: headers,
      clearKeyJson: pipeClearKey ??
          _workerClearKey(
            keyId: keyId,
            key: key,
            allKeys: allKeys,
          ),
    );
  }

  String? _workerClearKey({
    String? keyId,
    String? key,
    String? allKeys,
  }) {
    final entries = <Map<String, String>>[];

    if (allKeys != null && allKeys.isNotEmpty) {
      for (final token in allKeys.split(RegExp(r'[,;\s]+'))) {
        final pair = token.split(':');
        if (pair.length < 2) continue;
        final kid = _keyBytes(pair[0].trim());
        final value = _keyBytes(pair.sublist(1).join(':').trim());
        if (kid != null && value != null) {
          entries.add({'kty': 'oct', 'kid': kid, 'k': value});
        }
      }
    }

    if (entries.isEmpty && keyId != null && key != null) {
      final kid = _keyBytes(keyId);
      final value = _keyBytes(key);
      if (kid != null && value != null) {
        entries.add({'kty': 'oct', 'kid': kid, 'k': value});
      }
    }

    if (entries.isEmpty) return null;
    return jsonEncode({'keys': entries, 'type': 'temporary'});
  }

  Future<List<TvProgram>> getEpg(int channelId, {int offset = 0}) async {
    final uri = Uri.parse(_epgUrl).replace(queryParameters: {
      'offset': '$offset',
      'channel_id': '$channelId',
      'langId': '6',
    });
    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('EPG HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    final rawList = decoded is Map && decoded['epg'] is List
        ? decoded['epg'] as List
        : (decoded is List ? decoded : const []);

    final result = <TvProgram>[];
    for (final raw in rawList) {
      if (raw is! Map) continue;
      final start = _epochOrTime(raw['startEpoch'], raw['showtime']);
      final end = _epochOrTime(raw['endEpoch'], raw['endtime']);
      if (start == null || end == null || !end.isAfter(start)) continue;
      final title = '${raw['showname'] ?? raw['showtitle'] ?? 'Live Program'}'.trim();
      result.add(TvProgram(
        title: title.isEmpty ? 'Live Program' : title,
        start: start,
        end: end,
        description: raw['description']?.toString(),
        thumbnailUrl: _showImage(raw['episodeThumbnail']),
        posterUrl: _showImage(raw['episodePoster']),
        genre: raw['showGenre'] is List
            ? (raw['showGenre'] as List).join(', ')
            : raw['showGenre']?.toString(),
      ));
    }
    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }

  DateTime? _epoch(dynamic value) {
    final number = value is num ? value.toInt() : int.tryParse('$value');
    if (number == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      number < 10000000000 ? number * 1000 : number,
    );
  }
  DateTime? _epochOrTime(dynamic epoch, dynamic fallback) {
    final parsedEpoch = _epoch(epoch);
    if (parsedEpoch != null) return parsedEpoch;

    final raw = fallback?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    final normalized = raw.replaceAll('Z', '');
    return DateTime.tryParse(normalized) ??
        _parseClockTime(normalized);
  }

  DateTime? _parseClockTime(String raw) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?').firstMatch(raw);
    if (match == null) return null;
    final now = DateTime.now();
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final second = int.tryParse(match.group(3) ?? '0') ?? 0;
    var result = DateTime(now.year, now.month, now.day, hour, minute, second);
    if (result.isBefore(now.subtract(const Duration(hours: 12)))) {
      result = result.add(const Duration(days: 1));
    }
    return result;
  }


  String? _logo(String? path) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http')) return path;
    if (path.startsWith('dare_images/')) {
      return 'https://jiotvimages.cdn.jio.com/$path';
    }
    return 'https://jiotvimages.cdn.jio.com/dare_images/images/$path';
  }

  String? _showImage(dynamic path) {
    if (path == null) return null;
    final raw = path.toString();
    if (raw.isEmpty) return null;
    if (raw.startsWith('http')) return raw;
    if (raw.startsWith('dare_images/')) {
      return 'https://jiotv.catchup.cdn.jio.com/$raw';
    }
    return 'https://jiotv.catchup.cdn.jio.com/dare_images/shows/$raw';
  }

  String? _firstString(Map value, List<String> keys) {
    for (final key in keys) {
      final s = value[key]?.toString().trim();
      if (s != null && s.isNotEmpty) return s;
    }
    return null;
  }

  String? _cleanCategory(String? value) {
    if (value == null || value.toLowerCase() == 'unknown') return null;
    return value;
  }

  String? _cleanLanguage(String? value) =>
      value?.replaceAll('Malyalam', 'Malayalam');

  int? _int(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value');
}
