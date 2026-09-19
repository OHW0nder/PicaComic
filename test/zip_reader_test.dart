import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pica_comic/tools/zip_reader.dart';

/// 构建一个最小的 ZIP（store 模式），用于测试 readComic 的分话逻辑。
/// 仅包含本地文件头 + 数据 + central directory + EOCD。
Future<File> buildTestZip(String path, Map<String, List<int>> entries) async {
  final localParts = <int>[];
  final centralParts = <int>[];
  var offset = 0;

  for (final name in entries.keys) {
    final data = entries[name]!;
    final nameBytes = utf8.encode(name);

    final localHeader = BytesBuilder();
    final lh = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 0, Endian.little)
      ..setUint16(8, 0, Endian.little) // stored
      ..setUint16(10, 0, Endian.little)
      ..setUint16(12, 0, Endian.little)
      ..setUint32(14, 0, Endian.little) // crc
      ..setUint32(18, data.length, Endian.little)
      ..setUint32(22, data.length, Endian.little)
      ..setUint16(26, nameBytes.length, Endian.little)
      ..setUint16(28, 0, Endian.little);
    localHeader.add(lh.buffer.asUint8List());
    localHeader.add(nameBytes);
    localHeader.add(data);
    localParts.addAll(localHeader.toBytes());

    final centralHeader = BytesBuilder();
    final ch = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, 0, Endian.little)
      ..setUint16(10, 0, Endian.little) // stored
      ..setUint16(12, 0, Endian.little)
      ..setUint16(14, 0, Endian.little)
      ..setUint32(16, 0, Endian.little) // crc
      ..setUint32(20, data.length, Endian.little)
      ..setUint32(24, data.length, Endian.little)
      ..setUint16(28, nameBytes.length, Endian.little)
      ..setUint16(30, 0, Endian.little)
      ..setUint16(32, 0, Endian.little)
      ..setUint16(34, 0, Endian.little)
      ..setUint16(36, 0, Endian.little)
      ..setUint32(38, 0, Endian.little)
      ..setUint32(42, offset, Endian.little);
    centralHeader.add(ch.buffer.asUint8List());
    centralHeader.add(nameBytes);
    centralParts.addAll(centralHeader.toBytes());

    offset += 30 + nameBytes.length + data.length;
  }

  final centralSize = centralParts.length;
  final eocd = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(4, 0, Endian.little)
    ..setUint16(6, 0, Endian.little)
    ..setUint16(8, entries.length, Endian.little)
    ..setUint16(10, entries.length, Endian.little)
    ..setUint32(12, centralSize, Endian.little)
    ..setUint32(16, offset, Endian.little)
    ..setUint16(20, 0, Endian.little);

  final file = File(path);
  await file.writeAsBytes([...localParts, ...centralParts, ...eocd.buffer.asUint8List()]);
  return file;
}

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('zip_reader_test');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  test('读取指定页图片字节（store 模式）', () async {
    final zip = await buildTestZip('${tmpDir.path}/read.zip', {
      'Chapter 001/001.jpg': [7],
      'Chapter 001/002.jpg': [8],
    });

    final comic = await ZipReader.readComic(zip.path);
    expect(comic, isNotNull);
    final data = await ZipReader.readImage(zip.path, 1);
    expect(data, [8]);
  });

  test('多子文件夹 ZIP 拆分为多话，并正确换算全局页下标', () async {
    final zip = await buildTestZip('${tmpDir.path}/multi.zip', {
      'Chapter 020/001.jpg': [1],
      'Chapter 020/002.jpg': [2],
      'Chapter 021/001.jpg': [3],
      'Chapter 022/001.jpg': [4],
      'Chapter 022/002.jpg': [5],
      'ComicInfo.xml': [9], // 非图片，应被忽略
    });

    final comic = await ZipReader.readComic(zip.path);
    expect(comic, isNotNull);
    expect(comic!.hasMultipleEps, isTrue);
    expect(comic.pageCount, 5);
    expect(comic.epTitles, ['Chapter 020', 'Chapter 021', 'Chapter 022']);
    expect(comic.epStarts, [0, 2, 3]);
    expect(comic.epPageCount(1), 2);
    expect(comic.epPageCount(2), 1);
    expect(comic.epPageCount(3), 2);
    expect(comic.globalPageIndex(2, 0), 2);
    expect(comic.globalPageIndex(3, 1), 4);

    // 验证按页读取：跨话的页应取到正确的全局图片
    final p0 = await ZipReader.readImage(zip.path, comic.globalPageIndex(1, 0));
    final p2 = await ZipReader.readImage(zip.path, comic.globalPageIndex(2, 0));
    final p4 = await ZipReader.readImage(zip.path, comic.globalPageIndex(3, 1));
    expect(p0, [1]);
    expect(p2, [3]);
    expect(p4, [5]);
  });

  test('全部图片在根目录时视为单话', () async {
    final zip = await buildTestZip('${tmpDir.path}/flat.zip', {
      '001.jpg': [1],
      '002.jpg': [2],
    });

    final comic = await ZipReader.readComic(zip.path);
    expect(comic, isNotNull);
    expect(comic!.hasMultipleEps, isFalse);
    expect(comic.epTitles, isNull);
  });
}
