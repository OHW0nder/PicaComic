import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/foundation/history.dart';

void main() {
  group('HistoryType', () {
    test('内置来源名称映射正确', () {
      expect(HistoryType.picacg.name, "picacg");
      expect(HistoryType.ehentai.name, "ehentai");
      expect(HistoryType.jmComic.name, "jm");
      expect(HistoryType.hitomi.name, "hitomi");
      expect(HistoryType.htmanga.name, "htmanga");
      expect(HistoryType.nhentai.name, "nhentai");
    });

    test('local 类型返回 "local" 而非 "Unknown"', () {
      expect(HistoryType.local.value, 10);
      expect(HistoryType.local.name, "local");
    });

    test('local 与内置类型不冲突', () {
      final values = [
        HistoryType.picacg,
        HistoryType.ehentai,
        HistoryType.jmComic,
        HistoryType.hitomi,
        HistoryType.htmanga,
        HistoryType.nhentai,
        HistoryType.local,
      ];
      final set = values.toSet();
      expect(set.length, values.length);
    });

    test('相等性与 hashCode 基于value', () {
      expect(HistoryType.local, const HistoryType(10));
      expect(HistoryType.local.hashCode, const HistoryType(10).hashCode);
    });
  });
}
