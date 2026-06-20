import 'dart:async' show StreamController;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pica_comic/foundation/image_loader/base_image_provider.dart';
import 'package:pica_comic/tools/zip_reader.dart';

/// 用于读取 ZIP 压缩包内单张图片的 [ImageProvider]。
///
/// 继承 [BaseImageProvider] 以复用其缓存与重试逻辑。
/// 仅在加载时通过 [ZipReader.readImage] 读取指定页的字节。
class ZipImageProvider extends BaseImageProvider<ZipImageProvider> {
  const ZipImageProvider(this.filePath, this.pageIndex);

  final String filePath;
  final int pageIndex;

  @override
  String get key => "local_zip://$filePath#$pageIndex";

  @override
  Future<Uint8List> load(StreamController<ImageChunkEvent> chunkEvents) async {
    chunkEvents.add(const ImageChunkEvent(
      cumulativeBytesLoaded: 0,
      expectedTotalBytes: 100,
    ));
    final data = await ZipReader.readImage(filePath, pageIndex);
    chunkEvents.add(ImageChunkEvent(
      cumulativeBytesLoaded: data.length,
      expectedTotalBytes: data.length,
    ));
    return data;
  }

  @override
  Future<ZipImageProvider> obtainKey(ImageConfiguration configuration) {
    return Future.value(this);
  }

  @override
  bool operator ==(Object other) =>
      other is ZipImageProvider &&
      other.filePath == filePath &&
      other.pageIndex == pageIndex;

  @override
  int get hashCode => Object.hash(filePath, pageIndex);

  @override
  String toString() => 'ZipImageProvider($filePath, $pageIndex)';
}
