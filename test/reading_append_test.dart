import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/image_manager.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';

/// 假的 [ReadingData]，用于直接驱动 [ComicReadingPageLogic] 的续接逻辑。
class _FakeReadingData extends ReadingData {
  _FakeReadingData(this.epContents);

  /// 章节序号 -> 该话图片链接
  final Map<int, List<String>> epContents;

  /// [loadEp] 被调用的次数
  int loadEpCount = 0;

  /// 单次 [loadEp] 的耗时，用于模拟网络加载
  Duration delay = const Duration(milliseconds: 100);

  /// 为 true 时 [loadEp] 抛出异常
  bool throwOnLoad = false;

  /// 为 true 时 [loadEp] 返回定长列表（本地 ZIP / 已下载漫画的真实行为）
  bool fixedLengthLists = false;

  @override
  String get title => "test";

  @override
  String get id => "test";

  @override
  String get downloadId => "test";

  @override
  String get sourceKey => "test";

  @override
  ComicType get type => ComicType.picacg;

  @override
  FavoriteType get favoriteType => FavoriteType.picacg;

  @override
  bool get hasEp => true;

  @override
  Map<String, String> get eps =>
      {for (final ep in epContents.keys) "$ep": "$ep"};

  @override
  Future<Res<List<String>>> loadEp(int ep) async {
    loadEpCount++;
    await Future.delayed(delay);
    if (throwOnLoad) {
      throw Exception("load failed");
    }
    final content = epContents[ep];
    if (content == null) {
      return const Res.error("no such episode");
    }
    if (fixedLengthLists) {
      return Res(List.filled(content.length, "", growable: false));
    }
    return Res(content);
  }

  @override
  Future<Res<List<String>>> loadEpNetwork(int ep) => loadEp(ep);

  @override
  Stream<DownloadProgress> loadImageNetwork(int ep, int page, String url) =>
      const Stream.empty();
}

void main() {
  group('自动续接下一话', () {
    late _FakeReadingData data;
    late ComicReadingPageLogic logic;

    setUp(() {
      data = _FakeReadingData({
        1: List.generate(20, (i) => "ep1:$i"),
        2: List.generate(15, (i) => "ep2:$i"),
        3: List.generate(10, (i) => "ep3:$i"),
      });
      logic = ComicReadingPageLogic(1, data, 1, () {});
      logic.setContent(1, data.epContents[1]!);
    });

    test('续接请求在途时再次调用应等待其完成，而不是返回 false', () async {
      // 阅读到倒数第二页时预触发续接，此时请求仍在途
      final preTrigger = logic.appendNextEp();
      // 自动翻页到达末尾，再次请求续接
      final appendedByAutoTurn = await logic.appendNextEp();

      expect(appendedByAutoTurn, isTrue,
          reason: "自动翻页不能把「正在续接」当成「没有下一话」，否则会停在当前话末尾");
      expect(await preTrigger, isTrue);
      expect(data.loadEpCount, 1, reason: "同一话只应加载一次");
      expect(logic.urls.length, 35);
      expect(logic.hasEpToAppend, isTrue);
    });

    test('没有下一话时返回 false', () async {
      logic.setContent(3, data.epContents[3]!);
      expect(await logic.appendNextEp(), isFalse);
    });

    test('章节切换后在途的续接结果被丢弃，且新章节仍可续接', () async {
      final stale = logic.appendNextEp();
      logic.setContent(2, data.epContents[2]!);

      expect(await stale, isFalse);
      expect(logic.urls.length, 15, reason: "旧章节的续接结果不应污染新章节");
      expect(await logic.appendNextEp(), isTrue);
      expect(logic.urls.length, 25);
    });

    test('数据源返回定长列表时也能续接（本地 ZIP / 已下载漫画）', () async {
      data.fixedLengthLists = true;
      // 真实场景：初次加载的内容也是 List.filled 生成的定长列表
      logic.setContent(1, List.filled(20, "", growable: false));

      expect(await logic.appendNextEp(), isTrue,
          reason: "List.filled 默认是定长列表，续接不能因此失败");
      expect(logic.urls.length, 35);
      expect(logic.hasEpToAppend, isTrue);
    });

    test('续接抛异常时不向调用方抛出，且可重新尝试', () async {
      data.throwOnLoad = true;
      expect(await logic.appendNextEp(), isFalse,
          reason: "加载异常应被吞掉并记录, 不能中断自动翻页");

      data.throwOnLoad = false;
      expect(await logic.appendNextEp(), isTrue);
      expect(logic.urls.length, 35);
    });
  });
}
