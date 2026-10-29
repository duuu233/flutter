import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../network/iot/iot_api.dart';
import '../../network/iot/iot_client.dart';
import '../../shared/l10n/app_l10n.dart';
import 'wifi_l10n.dart';
import 'wifi_status.dart';

/// 一张图投屏的结果。[status]：SENT（已下发刷屏）/ UPLOADED（只上传不刷屏）/ FAILED / CANCELLED。
/// [message]：给用户看的文案（失败时为原因）；[binUrl]：服务端转好的 bin，结果页拿它写老服务相册记录（imgBle）。
/// [carouselUpdated]：带了 addToCarousel 时服务端是否已加入轮播（true / false），没给为 null。
class WifiCastResult {
  const WifiCastResult(
    this.status, {
    this.message = '',
    this.msgid = '',
    this.binUrl = '',
    this.carouselUpdated,
  });

  final String status;
  final String message;
  final String msgid;
  final String binUrl;
  final bool? carouselUpdated;

  /// SENT 与 UPLOADED 都算这一张成功。
  bool get sent => status == 'SENT' || status == 'UPLOADED';
}

/// WiFi 版投屏，同步小程序 `utils/wifi-projection.js`（V1.4 更新说明第二节起「不等 ack」）。
///
/// 一张图的完整过程（[projectOne]）：
///   ① 上传 POST /api/device/play（multipart：deviceNo、type、file、refresh、addToCarousel、renderMode），「图片上传中」；
///   ② 上传完但接口未返回：「图片处理中」（服务端转 bin + 上传 OSS + 下发，最长约 8 秒）；
///      进度条（2026-10-29 同小程序）：上传与处理合占 0~99%——真实上传进度折算到 0~[uploadShare]，处理阶段按时间
///      渐近爬向 99；100% 只在接口返回 SENT / UPLOADED 时给出，失败停在当时的位置；
///   ③ 接口返回即结束，不再轮询 /api/device/play/status、也不等 WS play.result：
///      · status=SENT（旧版 DOWNLOADING）→ 指令已下发，提示「已发送，屏幕即将刷新」；
///      · status=UPLOADED（refresh=false）→ 只上传了 bin、不刷屏，msgid 为 null；
///      · status=FAILED → MQTT 下发失败；
///      · 设备真正刷屏成功 / 失败由服务端写消息通知（PLAY_SUCCESS / PLAY_DOWNLOAD_FAILED / PLAY_STORAGE_ERROR / PLAY_FAILED）。
///   ④ 批量：接口仍是一次一张，前 N-1 张 refresh=false、最后一张 refresh=true，只刷一次屏（由结果页决定）。
///   ⑤ addToCarousel=true（实现报告反馈追加内容第二节，预览页「同时加入轮播」）：每张都带，carouselUpdated 原样交回，
///      false = 没加进轮播（投屏本身照常成功），由结果页提示。
///   ⑥ renderMode（2026-10-28）：后台产品配置的渲染模式，调用方用 PhotoFrameState.resolveRenderMode 取好传进来，有值才带。
/// 投屏日志（[onLog]，同时打控制台 [WiFi投屏]）：每个接口记「名称 + 参数 + 返回 / 失败」，阶段只在变化时记一行，
/// 上传进度只记 25% 档位；不记 userToken。
abstract final class WifiProjection {
  /// 上传阶段只进不退（迟到的进度回调不把「处理中」拉回「上传中」）。
  static const Map<String, int> _rank = {'UPLOADING': 0, 'PROCESSING': 1};

  /// 进度条分段（2026-10-29 同小程序）：真实上传进度 0~100 折算到 0~[uploadShare]；处理阶段没有真实进度，
  /// 从 [uploadShare] 按 1 - e^(-t/τ) 渐近爬向 [processingCap]（τ=3 秒：1 秒约 64%、3 秒约 81%、8 秒约 95%），永不到 100。
  static const int uploadShare = 50;
  static const int processingCap = 99;
  static const int processingTauMs = 3000;
  static const Duration processingTick = Duration(milliseconds: 200);

  /// 处理阶段第 [elapsedMs] 毫秒的进度（从 [base] 起）。
  static int processingProgress(int base, int elapsedMs) =>
      (base + (processingCap - base) * (1 - math.exp(-elapsedMs / processingTauMs))).floor();

  /// 接口返回的 status → 本次结果：SENT / UPLOADED / FAILED。旧版初始状态 DOWNLOADING 等同 SENT；
  /// 没给 status 时按本次是否刷屏推断（刷屏 = SENT，只上传 = UPLOADED）。
  static String resultStatus(Map<String, dynamic> response, bool refresh) {
    final status = '${response['status'] ?? ''}'.toUpperCase();
    if (status == 'FAILED' || status == 'UPLOADED') {
      return status;
    }
    if (status == 'SENT' || status == 'DOWNLOADING') {
      return 'SENT';
    }
    return refresh ? 'SENT' : 'UPLOADED';
  }

  static String _json(Object? value) {
    try {
      return jsonEncode(value);
    } catch (_) {
      return '$value';
    }
  }

  static String _text(Object? value) => value == null ? '' : '$value';

  /// 投一张图。[onStage](stage, progress)：stage 为 UPLOADING / PROCESSING / SENT / UPLOADED，progress 为进度条显示值
  /// （上传折算 + 处理阶段估算，见 [uploadShare]），不是上传百分比。[renderMode] 空 = 不传。不抛错。
  static Future<WifiCastResult> projectOne({
    required AppL10n l10n,
    required String deviceNo,
    required String filePath,
    required String type,
    bool refresh = true,
    bool addToCarousel = false,
    String renderMode = '',
    required void Function(String stage, int progress) onStage,
    required bool Function() isCancelled,
    void Function(String text)? onLog,
  }) async {
    final plain = IotApi.plainDeviceNo(deviceNo);
    void log(String text) {
      debugPrint('[WiFi投屏] $text');
      try {
        onLog?.call(text);
      } catch (_) {
        // 页面日志回调出错不影响投屏
      }
    }

    var stage = 'UPLOADING';
    var progress = 0;
    var loggedStage = '';
    void report(String next) {
      final nextRank = _rank[next];
      final currentRank = _rank[stage];
      if (nextRank == null || currentRank == null || nextRank >= currentRank) {
        stage = next;
      }
      if (stage != loggedStage) {
        loggedStage = stage;
        log('阶段 → $stage（${l10n.wifiCastStage(stage)}）');
      }
      onStage(stage, progress);
    }

    // 处理阶段的进度爬升：上传完开表，接口返回 / 报错即停
    Timer? processingTimer;
    void startProcessing() {
      if (processingTimer != null) {
        return;
      }
      final startedAt = DateTime.now();
      final base = math.max(progress, uploadShare);
      processingTimer = Timer.periodic(processingTick, (_) {
        final next = processingProgress(base, DateTime.now().difference(startedAt).inMilliseconds);
        if (next > progress) {
          progress = next;
          report('PROCESSING');
        }
      });
    }

    void stopProcessing() {
      processingTimer?.cancel();
      processingTimer = null;
    }

    WifiCastResult finish(WifiCastResult result) {
      log(
        '结束：${result.status}${result.message.isNotEmpty ? '（${result.message}）' : ''}，'
        'msgid=${result.msgid.isNotEmpty ? result.msgid : '-'}，binUrl=${result.binUrl.isNotEmpty ? result.binUrl : '-'}'
        '${addToCarousel ? '，carouselUpdated=${result.carouselUpdated}' : ''}',
      );
      return result;
    }

    log(
      '开始投屏：设备 ${plain.isNotEmpty ? plain : '-'}，type=$type${renderMode.isNotEmpty ? '，renderMode=$renderMode' : ''}，refresh=$refresh'
      '${addToCarousel ? '，addToCarousel=true' : ''}，文件 $filePath',
    );
    if (isCancelled()) {
      return finish(WifiCastResult('CANCELLED', message: l10n.wifiCastStage('CANCELLED')));
    }
    report('UPLOADING');
    log('接口【投屏】POST /api/device/play（IoT，multipart 上传）');
    log(
      '参数 ${_json({'deviceNo': plain, 'type': type, if (renderMode.isNotEmpty) 'renderMode': renderMode, 'refresh': refresh, if (addToCarousel) 'addToCarousel': true, 'file': filePath})}',
    );
    final startedAt = DateTime.now();
    var loggedPercent = -1;
    Map<String, dynamic> response;
    try {
      response = await IotApi.play(
        plain,
        filePath,
        type,
        refresh: refresh,
        addToCarousel: addToCarousel,
        renderMode: renderMode,
        onProgress: (percent) {
          final uploaded = math.min(100, math.max(0, percent.round()));
          final bucket = uploaded ~/ 25 * 25;
          if (bucket > loggedPercent) {
            loggedPercent = bucket;
            log('上传进度 $bucket%');
          }
          progress = math.max(progress, uploaded * uploadShare ~/ 100);
          // 传完还没返回：图片处理中，进度接着往 99 爬
          report(uploaded >= 100 ? 'PROCESSING' : 'UPLOADING');
          if (uploaded >= 100) {
            startProcessing();
          }
        },
      );
    } on IotException catch (error) {
      stopProcessing();
      log(
        '失败 HTTP ${error.statusCode} code ${error.code}'
        '${error.serverMessage.isNotEmpty ? ' 服务端：${error.serverMessage}' : ''}，${error.message}'
        '（耗时 ${DateTime.now().difference(startedAt).inMilliseconds}ms）',
      );
      // 4041（设备已离线）时补查一次：休眠中 / 已关机的设备也回 4041，改成对应提示
      final message = error.numericCode == 4041 ? await wifiOfflineTipFor(l10n, plain) : error.message;
      return finish(WifiCastResult('FAILED', message: message));
    } catch (error) {
      stopProcessing();
      log('失败 $error');
      return finish(WifiCastResult('FAILED', message: l10n.wifiCastFailedGeneric));
    }
    stopProcessing();
    log('返回 ${_json(response)}（耗时 ${DateTime.now().difference(startedAt).inMilliseconds}ms）');
    final status = resultStatus(response, refresh);
    // 100% 只给成功（SENT / UPLOADED）；FAILED 停在当时的位置
    if (status != 'FAILED') {
      progress = 100;
    }
    report(status);
    final carousel = response['carouselUpdated'];
    return finish(
      WifiCastResult(
        status,
        message: l10n.wifiCastStage(status),
        msgid: _text(response['msgid']),
        binUrl: _text(response['binUrl']),
        carouselUpdated: carousel is bool ? carousel : null,
      ),
    );
  }
}
