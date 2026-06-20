import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// 本地漫画（ZIP 压缩包）的元数据。
class LocalComic {
  /// ZIP 文件的绝对路径，同时作为唯一 ID。
  final String path;

  /// 显示标题（默认取文件名，去掉扩展名）。
  final String title;

  /// 压缩包内图片文件数量。
  final int pageCount;

  /// 排序后的图片文件名列表（压缩包内的相对路径）。
  final List<String> imageFiles;

  /// 封面缓存文件路径（缩略图），为空表示尚未缓存。
  String? coverPath;

  LocalComic({
    required this.path,
    required this.title,
    required this.pageCount,
    required this.imageFiles,
    this.coverPath,
  });

  String get id => path;

  Map<String, dynamic> toMap() => {
        'path': path,
        'title': title,
        'pageCount': pageCount,
        'imageFiles': imageFiles,
        if (coverPath != null) 'coverPath': coverPath,
      };

  factory LocalComic.fromMap(Map<String, dynamic> map) => LocalComic(
        path: map['path'] as String,
        title: map['title'] as String,
        pageCount: map['pageCount'] as int,
        imageFiles: (map['imageFiles'] as List).cast<String>(),
        coverPath: map['coverPath'] as String?,
      );
}

String _basenameWithoutExtension(String path) {
  final slash = path.lastIndexOf(RegExp(r'[/\\]'));
  final name = slash >= 0 ? path.substring(slash + 1) : path;
  final dot = name.lastIndexOf('.');
  return dot >= 0 ? name.substring(0, dot) : name;
}

const _imageExtensions = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'];

String _extension(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return '';
  return path.substring(dot);
}

bool _isImage(String name) {
  final ext = _extension(name).toLowerCase();
  return _imageExtensions.contains(ext);
}

/// ZIP 读取器。
///
/// 使用 [archive] 包的 [ZipDecoder.decodeBytes] 解析中央目录。
/// 注意：解析时会一次性加载 ZIP 索引到内存，但实际图片数据仅在调用
/// [readImage] 时按需读取，每张图独立加载。
class ZipReader {
  /// 解析 ZIP 文件，返回 [LocalComic] 元数据。
  /// 若文件不是有效的 ZIP 或没有图片，返回 null。
  static Future<LocalComic?> readComic(String filePath) async {
    try {
      final bytes = await File(filePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      final images = <String>[];
      for (final file in archive) {
        if (!file.isFile) continue;
        if (_isImage(file.name)) {
          images.add(file.name);
        }
      }

      images.sort(_naturalCompare);

      if (images.isEmpty) return null;

      final title = _basenameWithoutExtension(filePath);

      // 缓存 archive 供后续按页读取
      _cache[filePath] = archive;

      return LocalComic(
        path: filePath,
        title: title,
        pageCount: images.length,
        imageFiles: images,
      );
    } catch (e) {
      return null;
    }
  }

  /// 读取 ZIP 中指定索引的图片字节。
  static Future<Uint8List> readImage(String filePath, int index) async {
    var archive = _cache[filePath];
    if (archive == null) {
      final bytes = await File(filePath).readAsBytes();
      archive = ZipDecoder().decodeBytes(bytes);
      _cache[filePath] = archive;
    }
    // 取第 index 个图片文件
    var found = 0;
    for (final f in archive) {
      if (!f.isFile) continue;
      if (_isImage(f.name)) {
        if (found == index) {
          return Uint8List.fromList(f.content as List<int>);
        }
        found++;
      }
    }
    // 没找到指定索引的文件，返回第一个文件
    return Uint8List.fromList(archive.first.content as List<int>);
  }

  /// 关闭某个 ZIP 的缓存，释放内存。
  static void close(String filePath) {
    _cache.remove(filePath);
  }

  /// 关闭所有打开的 ZIP 缓存。
  static void closeAll() {
    _cache.clear();
  }

  static final Map<String, Archive> _cache = {};
}

/// 简单的自然排序：按数字大小比较，而非字符串字典序。
int _naturalCompare(String a, String b) {
  var i = 0, j = 0;
  while (i < a.length && j < b.length) {
    final ai = a.codeUnitAt(i);
    final bj = b.codeUnitAt(j);
    if (_isDigit(ai) && _isDigit(bj)) {
      // 提取数字
      var ni = i;
      while (ni < a.length && _isDigit(a.codeUnitAt(ni))) {
        ni++;
      }
      var nj = j;
      while (nj < b.length && _isDigit(b.codeUnitAt(nj))) {
        nj++;
      }
      final numA = int.parse(a.substring(i, ni));
      final numB = int.parse(b.substring(j, nj));
      if (numA != numB) return numA.compareTo(numB);
      i = ni;
      j = nj;
    } else {
      if (ai != bj) return ai.compareTo(bj);
      i++;
      j++;
    }
  }
  return a.length.compareTo(b.length);
}

bool _isDigit(int c) => c >= 48 && c <= 57;
