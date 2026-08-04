import 'dart:io';

import '../../network/api_client.dart';

/// 「再次投屏」用的服务器图片下载。
///
/// 小程序的投屏预览页可以直接吃远程 URL（`pendingProjection.images[].url`），Flutter 的
/// [CastPreviewPage] 只接受**本地路径**（要 decode 成 ui.Image 做取景/烘焙），所以再次投屏
/// 必须先把后端图片落到临时文件。
///
/// 「我的相册」（批量再次投屏）与「投屏管理」（单条再次投屏）共用这一份实现，避免两处各写一遍
/// 超时/文件名规则后各自漂移。
class RecastDownload {
  RecastDownload._();

  /// 下载 [url] 到系统临时目录并返回本地路径；失败返回 null（调用方给用户提示，不抛异常）。
  ///
  /// - 共用 [ApiClient] 的连接池；
  /// - 必须带超时：弱网下没有超时会永久挂起，页面看起来就是「点了没反应」；
  /// - 文件名带微秒时间戳 + [seq]，批量下载时不会互相覆盖。
  static Future<String?> toTempFile(String url, {int seq = 0}) async {
    if (url.isEmpty) {
      return null;
    }
    try {
      final resp = await ApiClient.instance.httpClient
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        return null;
      }
      final file = File(
        '${Directory.systemTemp.path}/recast_'
        '${DateTime.now().microsecondsSinceEpoch}_$seq.jpg',
      );
      await file.writeAsBytes(resp.bodyBytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }
}
