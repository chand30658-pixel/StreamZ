class TvChannel {
  const TvChannel({
    required this.id,
    required this.name,
    this.logoUrl,
    this.categoryId,
    this.category,
    this.languageId,
    this.languageName,
    this.isHd = false,
    this.channelOrder = 0,
    this.catchup = false,
    this.playbackUrl,
    this.playbackHeaders = const {},
    this.clearKeyJson,
  });

  final int id;
  final String name;
  final String? logoUrl;
  final int? categoryId;
  final String? category;
  final int? languageId;
  final String? languageName;
  final bool isHd;
  final int channelOrder;
  final bool catchup;
  final String? playbackUrl;
  final Map<String, String> playbackHeaders;
  final String? clearKeyJson;

  TvChannel copyWith({
    String? logoUrl,
    int? categoryId,
    String? category,
    int? languageId,
    String? languageName,
    String? playbackUrl,
    Map<String, String>? playbackHeaders,
    String? clearKeyJson,
  }) =>
      TvChannel(
        id: id,
        name: name,
        logoUrl: logoUrl ?? this.logoUrl,
        categoryId: categoryId ?? this.categoryId,
        category: category ?? this.category,
        languageId: languageId ?? this.languageId,
        languageName: languageName ?? this.languageName,
        isHd: isHd,
        channelOrder: channelOrder,
        catchup: catchup,
        playbackUrl: playbackUrl ?? this.playbackUrl,
        playbackHeaders: playbackHeaders ?? this.playbackHeaders,
        clearKeyJson: clearKeyJson ?? this.clearKeyJson,
      );
}

class TvProgram {
  const TvProgram({
    required this.title,
    required this.start,
    required this.end,
    this.description,
    this.thumbnailUrl,
    this.posterUrl,
    this.genre,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final String? description;
  final String? thumbnailUrl;
  final String? posterUrl;
  final String? genre;

  bool get isLive {
    final now = DateTime.now();
    return !now.isBefore(start) && now.isBefore(end);
  }
}

class PlaybackSource {
  const PlaybackSource({
    required this.url,
    this.headers = const {},
    this.clearKeyJson,
  });

  final String url;
  final Map<String, String> headers;
  final String? clearKeyJson;

  bool get isDash => url.toLowerCase().contains('.mpd');
}
