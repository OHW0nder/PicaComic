part of pica_reader;

/// 本地漫画的 [ReadingData] 实现。
class LocalReadingData extends ReadingData {
  LocalReadingData(this.comic);

  final LocalComic comic;

  @override
  String get title => comic.title;

  @override
  String get id => comic.id;

  @override
  String get downloadId => comic.id;

  @override
  ComicType get type => ComicType.local;

  @override
  String get sourceKey => "local";

  @override
  bool get hasEp => false;

  @override
  Map<String, String>? get eps => null;

  @override
  bool get downloaded => false;

  @override
  FavoriteType get favoriteType => FavoriteType.picacg;

  @override
  String buildImageKey(int ep, int page, String url) =>
      "local_zip://${comic.id}#$page";

  @override
  Future<Res<List<String>>> loadEpNetwork(int ep) async {
    return Res(List.filled(comic.pageCount, ""));
  }

  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) {
    throw UnimplementedError("Local comic does not load images from network");
  }

  @override
  ImageProvider createImageProvider(int ep, int page, String url) {
    return ZipImageProvider(comic.path, page);
  }
}
