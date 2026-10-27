import 'dart:async';

import '../../network/iot/iot_api.dart';
import '../../network/iot/iot_client.dart';
import '../../network/iot/iot_ws.dart';

/// 一张图投屏的结果。[status]：SUCCESS / FAILED / TIMEOUT / UNKNOWN / CANCELLED（另有 EXPIRED = 任务过期、结果未知）。
/// [reason]：失败原因码（PLAY_DOWNLOAD_FAILED 等）；[message]：接口错误的文案（上传失败时）。
class WifiCastResult {
  const WifiCastResult(this.status, {this.msgid = '', this.reason = '', this.message = '', this.corrected = false});

  final String status;
  final String msgid;
  final String reason;
  final String message;

  /// TIMEOUT 之后迟到的成功 ack（服务端 corrected=true）。
  final bool corrected;
}

/// WiFi 版投屏，同步小程序 `utils/wifi-projection.js`（契约见小程序 docs 前端对接文档第一节与评审回复 v0.32）。
///
/// 一张图的完整过程（[projectOne]）：
///   ① 上传 POST /api/device/play（multipart：deviceNo、type、file），进度 = 上传进度 0~100；
///   ② 上传到 100% 但接口未返回：「图片处理中」（服务端转 bin + 上传 OSS + 下发，最长约 8 秒）；
///   ③ 接口返回 status=SENT（旧版 DOWNLOADING）→ 指令已下发；status=FAILED → MQTT 下发失败，直接失败；
///   ④ 等终态：WebSocket play.result 为主，GET /api/device/play/status 每 3 秒轮询兜底（WS 断线 / 没订上也能走完）；
///      状态只进不退：SENT → DOWNLOADING → FLASHING → SUCCESS / FAILED / TIMEOUT，迟到的低档位忽略；
///   ⑤ TIMEOUT 不立即定论：再等 3 秒给迟到的成功 ack（corrected=true 的 SUCCESS），再查一次状态；
///   ⑥ 客户端兜底 90 秒（服务端 ack 超时 60 秒）仍无终态，查一次状态，仍不是终态按「结果未知」。
/// WS 事件可能早于 HTTP 响应到达（那时还不知道 msgid）：上传前就开始按 msgid 缓存本设备的 play.result，拿到 msgid 后补认。
abstract final class WifiProjection {
  static const Duration pollInterval = Duration(seconds: 3);
  static const Duration timeoutGrace = Duration(seconds: 3);
  static const Duration overallTimeout = Duration(seconds: 90);

  /// 状态档位：只进不退。
  static const Map<String, int> _rank = {
    'UPLOADING': 0,
    'PROCESSING': 1,
    'SENT': 2,
    'DOWNLOADING': 3,
    'FLASHING': 4,
    'SUCCESS': 9,
    'FAILED': 9,
    'TIMEOUT': 9,
  };

  static String _normalize(Object? status) {
    final value = '${status ?? ''}'.toUpperCase();
    return _rank.containsKey(value) ? value : '';
  }

  static bool _isTerminal(String status) =>
      status == 'SUCCESS' || status == 'FAILED' || status == 'TIMEOUT';

  /// 投一张图。[onStage](stage, progress)：stage 为上面的档位名，progress 为上传进度 0~100。不抛错。
  static Future<WifiCastResult> projectOne({
    required String deviceNo,
    required String filePath,
    required String type,
    required void Function(String stage, int progress) onStage,
    required bool Function() isCancelled,
  }) async {
    final plain = IotApi.plainDeviceNo(deviceNo);
    var stage = 'UPLOADING';
    var progress = 0;
    void report(String next) {
      if ((_rank[next] ?? -1) >= (_rank[stage] ?? 0)) {
        stage = next;
      }
      onStage(stage, progress);
    }

    // WS：先订阅、先缓存，事件可能比 HTTP 响应早到
    final cached = <String, List<Map<String, dynamic>>>{};
    var msgid = '';
    void Function()? wake;
    final ws = IotWs.instance;
    final subs = <StreamSubscription<Object>>[
      ws.on('play.result').listen((event) {
        final key = '${event['msgid'] ?? ''}';
        if (IotApi.plainDeviceNo(event['deviceNo']) != plain || key.isEmpty) {
          return;
        }
        (cached[key] ??= <Map<String, dynamic>>[]).add(event);
        if (key == msgid) {
          wake?.call();
        }
      }),
      // 断线重连后立即补查一次（断线期间的事件会丢）
      ws.states.listen((event) {
        if (event.state == 'open' && event.reconnect) {
          wake?.call();
        }
      }),
    ];
    final alreadySubscribed = ws.subscriptions.contains(plain);
    ws.subscribe(plain);

    WifiCastResult finish(WifiCastResult result) {
      for (final sub in subs) {
        unawaited(sub.cancel());
      }
      if (!alreadySubscribed) {
        ws.unsubscribe(plain);
      }
      return result;
    }

    try {
      report('UPLOADING');
      Map<String, dynamic> response;
      try {
        response = await IotApi.play(
          plain,
          filePath,
          type,
          onProgress: (percent) {
            final next = percent.round();
            progress = next < progress ? progress : (next > 100 ? 100 : next);
            // 传完还没返回：图片处理中
            report(progress >= 100 ? 'PROCESSING' : 'UPLOADING');
          },
        );
      } on IotException catch (error) {
        return finish(WifiCastResult('FAILED', message: error.message));
      }
      progress = 100;
      msgid = '${response['msgid'] ?? ''}';
      final first = _normalize(response['status']);
      if (first == 'FAILED') {
        return finish(WifiCastResult('FAILED', msgid: msgid));
      }
      // 兼容旧版初始状态 DOWNLOADING；SENT 为当前口径
      report(first.isNotEmpty && !_isTerminal(first) ? first : 'SENT');
      if (msgid.isEmpty) {
        // 没有任务号无法跟踪：指令已下发，结果只能看设备
        return finish(const WifiCastResult('UNKNOWN'));
      }

      ({String status, String reason, bool corrected})? latest; // 最新一条终态事件 / 查询结果
      void apply(Map<String, dynamic> record) {
        final status = _normalize(record['status']);
        if (status.isEmpty) {
          return;
        }
        if (_isTerminal(status)) {
          // 终态可被修正：TIMEOUT 之后迟到的 SUCCESS（corrected=true）以成功为准
          final current = latest;
          if (current == null || (current.status == 'TIMEOUT' && status == 'SUCCESS')) {
            latest = (
              status: status,
              reason: '${record['reason'] ?? ''}',
              corrected: record['corrected'] == true,
            );
          }
        }
        report(status);
      }

      void drain() {
        final list = cached[msgid] ?? const <Map<String, dynamic>>[];
        cached[msgid] = <Map<String, dynamic>>[];
        list.forEach(apply);
      }

      Future<IotException?> query() async {
        try {
          apply(await IotApi.getPlayStatus(msgid));
          return null;
        } on IotException catch (error) {
          return error;
        } catch (_) {
          return null;
        }
      }

      // 等一小段：WS 事件到了提前醒
      Future<void> waitAWhile(Duration duration) {
        final completer = Completer<void>();
        late final Timer timer;
        void done() {
          timer.cancel();
          wake = null;
          if (!completer.isCompleted) completer.complete();
        }

        timer = Timer(duration, done);
        wake = done;
        return completer.future;
      }

      drain();
      final deadline = DateTime.now().add(overallTimeout);
      IotException? lastQueryError;
      while (!(latest != null && latest!.status != 'TIMEOUT') && DateTime.now().isBefore(deadline)) {
        if (isCancelled()) {
          return finish(WifiCastResult('CANCELLED', msgid: msgid));
        }
        if (latest?.status == 'TIMEOUT') {
          // 给迟到的成功 ack 留修正窗口，再查一次确认
          await Future<void>.delayed(timeoutGrace);
          drain();
          if (latest?.status == 'TIMEOUT') {
            await query();
          }
          break;
        }
        await waitAWhile(pollInterval);
        drain();
        if (latest == null) {
          lastQueryError = await query();
        }
      }
      if (latest == null) {
        // 客户端兜底到点：最后查一次；任务过期（4044）或仍无终态都按结果未知
        lastQueryError = await query();
        drain();
      }
      final result = latest;
      if (result == null) {
        final expired = lastQueryError?.numericCode == 4044;
        return finish(WifiCastResult(expired ? 'EXPIRED' : 'UNKNOWN', msgid: msgid));
      }
      return finish(
        WifiCastResult(result.status, msgid: msgid, reason: result.reason, corrected: result.corrected),
      );
    } catch (error) {
      return finish(WifiCastResult('FAILED', msgid: msgid, message: '$error'));
    }
  }
}
