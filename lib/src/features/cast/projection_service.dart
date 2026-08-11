// 投屏服务（seekink 抖动出帧 + BLE 图传）—— 由微信小程序版 `subpackages/projection/result/result.js` 移植。
//
// 链路（2026-07-23 对齐小程序 07-22 切换，见 photo-album docs `server-image-processing-ble-transfer.md`）：
//   连接设备 → 读设备信息(0x01) → 逐张（两路网络并行，见 _acquireFrame）：
//     ① 设备帧：预览处理后的设备分辨率图 → 统一压缩 → seekink 抖动接口出六色 4bpp 帧(DitheringApi，
//        不再下载后端转码的 .bin)
//     ② 投屏记录：原图（进预览页前未操作过的图）→ 同一套统一压缩 → setUserProductUpload 按
//        「未成功(0)」建记录拿 taskId（⚠️ 响应 DTO BaseUploadApiOut 没有 upirId，后端靠 taskId 定位记录）
//   → 校验帧长度==宽×高÷2 → 选空闲槽位 → BLE 图传(0x20/0x21/0x22)
//   → 设备成功才编辑投屏记录(editUserProductImgRecord 置 deviceUploadState=1) → 刷新显示。
//
// 再次/重新投屏（2026-07-23 起与正常投屏同链路）：投屏管理页只带记录图片地址进预览页，与手选图片
// 流程无差别；旧「imgBle .bin 直传 + addUserProductImgRecord 补记」(recastRecord) 已删除——
// 后端不再生成/返回 .bin。App 端不做六色量化：出帧在 seekink 接口侧，App 拿帧字节直传设备。

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:image/image.dart' as img;

import '../../device/ble/device_ble.dart';
import '../../device/ble/frame_protocol.dart';
import '../../device/ble_controller.dart';
import '../../device/device_interaction_trace.dart';
import '../../network/boltfox_api.dart';
import '../../network/dithering_api.dart';
import '../../shared/l10n/app_l10n.dart';

/// 投屏进度回调载荷。语义完全对齐小程序 `result.js`（进度页三段式：转码→处理→传输）。
class CastProgress {
  const CastProgress({
    required this.percent,
    required this.current,
    required this.total,
    required this.title,
    required this.message,
  });

  /// **当前这一张**的传输进度（0~1），不是整单进度——对齐小程序 `progressPercent`：
  /// 每张开始时归 0，随 BLE 分包 ACK 涨到 1。整单进度由 [current]/[total] 体现。
  final double percent;

  /// 当前正在处理第几张（1-based；尚未开始为 0）——对齐小程序 `progressCurrent`。
  final int current;

  /// 本次总张数——对齐小程序 `progressTotal`。
  final int total;

  /// 阶段标题：`图片转码中` → `图片处理中` → `图片传输中`（对齐小程序 STATUS_TEXT + 各阶段 setData）。
  final String title;

  /// 阶段描述，如「正在连接设备…」「正在投第 2/5 张…」。
  final String message;
}

/// 投屏进度页的阶段标题（对齐小程序 result.js）。
class CastStage {
  CastStage._();

  /// 初始 / 连接 / 读设备信息 / 后端转码阶段。
  static const transcoding = '图片转码中';

  /// 取到设备帧、准备本张（选槽位等）。
  static const processing = '图片处理中';

  /// BLE 分包图传中（进度条真正在动的阶段）。
  static const transferring = '图片传输中';
}

/// 投屏结果。
class ProjectionResult {
  const ProjectionResult({
    required this.success,
    required this.uploaded,
    required this.total,
    required this.message,
    this.failureKind,
  });

  final bool success;
  final int uploaded;
  final int total;
  final String message;

  /// 失败原因的机器可读分类（来自 [FrameBleException.kind]）。
  /// 失败页优先按它归类展示话术，[message] 只兜底——错误语义不再依赖
  /// 对 message 的中文子串匹配，翻译服务层文案不会破坏归类。
  final FrameBleErrorKind? failureKind;
}

/// 用户主动中断（切后台 / 离开页面）。
class ProjectionAbortedException implements Exception {
  @override
  String toString() => 'UPLOAD_ABORTED';
}

/// 服务器转换 + BLE 图传投屏服务。复用 [BleController] 持有的已连接设备。
class ServerImageProjectionService {
  ServerImageProjectionService({BleController? ble, AppL10n? l10n})
    : _ble = ble ?? BleController.instance,
      _l10n = l10n;

  final BleController _ble;
  final AppL10n? _l10n;

  /// 逐张把 [filePaths] 里的图（预览处理后的设备分辨率图）经 seekink 抖动接口出帧并图传到设备；
  /// [recordFilePaths] 为逐张对应的原图（建投屏记录用，缺省回退 [filePaths]）。
  ///
  /// [userProductId] 为后端设备 id（写投屏记录用）。任一张失败即整单失败并返回失败原因；
  /// 已成功传到设备的张数保留在设备上（本张成功即物理写入）。
  Future<ProjectionResult> castImages({
    required Object userProductId,
    required String expectedSerial,
    required int expectedScreenCode,
    required List<String> filePaths,
    List<String>? recordFilePaths,
    void Function(CastProgress)? onProgress,
    bool Function()? shouldAbort,
  }) async {
    final client = _ble.client;
    // [filePaths]=预览处理后的设备分辨率图（喂抖动接口出帧）；[recordFilePaths]=对应的原图
    //（建投屏记录/后端存图，小程序 _origSrc 语义），缺省/缺项时回退用处理后的图。逐项配对，
    // 空路径成对跳过，保证两列表下标始终对齐。
    final images = <String>[];
    final originals = <String>[];
    for (var i = 0; i < filePaths.length; i++) {
      final path = filePaths[i];
      if (path.isEmpty) continue;
      images.add(path);
      final original = (recordFilePaths != null && i < recordFilePaths.length)
          ? recordFilePaths[i]
          : '';
      originals.add(original.isNotEmpty ? original : path);
    }

    // `client.connected` 只说明 App 连着某台设备。投屏前必须确认当前会话
    // 就是页面携带的目标完整 ID，不能把同尺寸、同广播短 ID 的另一台当成目标。
    if (expectedSerial.trim().isEmpty ||
        !_ble.sessionMatchesSerial(
          expectedSerial,
          screenCode: expectedScreenCode,
        )) {
      return const ProjectionResult(
        success: false,
        uploaded: 0,
        total: 0,
        message: '电子纸设备未连接，请先连接电子纸设备后再投屏',
        failureKind: FrameBleErrorKind.disconnected,
      );
    }
    if (images.isEmpty) {
      return const ProjectionResult(
        success: false,
        uploaded: 0,
        total: 0,
        message: '没有可投屏的照片',
      );
    }

    final total = images.length;
    int uploaded = 0;
    final trace = DeviceInteractionTrace('cast-images');
    trace.mark(
      'params-conn-${FrameBleClient.transferConnIntervalMs}ms-'
      'pace-${FrameBleClient.transferPacketPaceMs}ms-'
      'window-${FrameBleClient.transferWindowPackets}',
    );

    // 阶段标题与「第几张」是跨 emit 保持的（小程序里就是 data 上的 title / progressCurrent），
    // 只有明确切阶段/切张时才更新，传输过程中的高频 emit 只带百分比。
    var stageTitle = _l10n?.castStageTranscoding ?? CastStage.transcoding;
    var currentIndex = 0;

    void emit(double percent, String message, {String? title, int? current}) {
      if (title != null) stageTitle = title;
      if (current != null) currentIndex = current;
      onProgress?.call(
        CastProgress(
          percent: percent.clamp(0.0, 1.0).toDouble(),
          current: currentIndex,
          total: total,
          title: stageTitle,
          message: message,
        ),
      );
    }

    // 整批只开一次图传会话：下发 0x13 把连接间隔切到 7.5ms(安卓)/15ms(iOS) + 请求高优先级。
    // 这是 App 图传比小程序慢的主因——之前每张图各自设一次、传完又掉回省电长间隔，
    // 批量投屏时每张的前半段都在慢间隔上重新协商（详见 device_ble.beginTransferSession）。
    // 失败不阻断（旧固件可能不支持 0x13），只是跑得慢一点。
    var sessionOpened = false;
    // 最后一张的异步刷屏(0x24)Future：收尾把连接间隔回落到空闲档(100ms)时要等它跑完再发——
    // 刷屏期间设备对新指令回忙(0x0B)，两者挤在一起会让回落白白失败。失败/中断路径无刷屏则保持 null。
    Future<int>? lastRefresh;
    // 多图全部写入后仍**只刷一次**，但最终展示的是本批**第一张**成功写入的照片
    // （2026-08-04 产品口径，对齐小程序 result.js `firstSuccessfulIndex`）。
    // ⚠️ 用 null 表示「还没有成功过」：槽位 0 是相框第一个位置，是合法值，不能用 -1/0 当哨兵判假。
    int? firstSuccessfulIndex;
    try {
      // 1) 读取真实设备信息（屏幕尺寸/类型/容量/已存掩码）。B2：走精简读取，不带 0x03 固件版本。
      emit(0, _l10n?.castReadingDeviceInfo ?? '正在读取设备信息…');
      final info = await trace.measure(
        'read-core-info-0x01',
        () => _readTransferInfoAwaitingIdle(
          client,
          onWaiting: () =>
              emit(0, _l10n?.castDeviceRefreshing ?? '设备正在刷新，请稍候…'),
        ),
      );
      // 机型/尺寸分开判（对齐小程序 result.js:367-375）：只有 0x03 才是「该型号暂不支持图传」；
      // 读到 0 尺寸多半是刷屏后短暂断连，应提示「重新连接」而非误报机型不支持。
      if (info.screenType == 0x03) {
        throw FrameBleException('该型号暂不支持图传', kind: FrameBleErrorKind.unsupported);
      }
      if (info.width == 0 || info.height == 0) {
        throw FrameBleException('电子纸设备未连接或信息读取异常，请重新连接电子纸设备后再投屏', kind: FrameBleErrorKind.disconnected);
      }
      final expected4bpp =
          (info.width * info.height + 1) ~/ 2; // 六色 4bpp = 宽×高÷2（向上取整）

      // 设备空间：不做整单预检（对齐小程序 result.js —— 逐张选空闲槽位，放满为止）。
      // 只差 N 张空间时也把能放下的都投进去(部分成功)，而不是一张不投直接整单失败。
      // 每张选槽位时若已无空位(firstFreeIndex<0)才抛「设备已存满」，配合下方「uploaded>=1 即成功页」。
      var usedIndexes = FrameProtocol.maskToIndexes(info.imgMask);

      // A3 预取流水线：设备帧的「后端转码 + 下载 + D1/D2 预处理」是纯网络/纯计算，与 BLE 图传互不占用
      // 资源。投第 i 张(走蓝牙)的同时并行预取第 i+1 张的设备帧；只预取下一张(最多 1 张在后台)，中断浪费
      // 最小。预取失败不在此处抛，留到主循环 await 时再抛，走原有失败处理。
      // （F1 首张与连接并行：App 在进入本方法前 BLE 连接已建立，无冷连接可重叠，故只做批量内的下一张预取。）
      final prefetch = List<Future<_AcquiredFrame>?>.filled(total, null);
      void startPrefetch(int idx) {
        if (idx < 0 || idx >= total || prefetch[idx] != null) return;
        prefetch[idx] = trace.measure(
          'prepare-image-${idx + 1}',
          () => _acquireFrame(
            client: client,
            filePath: images[idx],
            originalPath: originals[idx],
            userProductId: userProductId,
            width: info.width,
            height: info.height,
          ),
        );
        // 预取失败的错误仍留到主循环 await 时按原流程抛出（ignore 只是挂一个丢弃
        // 监听器，不吞后续 await 拿到的错误）。不挂的话：主循环要等上一张 BLE 图传完
        // （数十秒）才 await 到它，期间「完成出错但无监听者」的 Future 会被
        // PlatformDispatcher.onError 当成未处理异步错误写入 last_crash.txt，
        // 一次普通弱网下载失败就会在下次启动误弹「崩溃报告」。
        prefetch[idx]!.ignore();
      }

      startPrefetch(0);

      // 连接间隔优化放在首张预取**之后**：0x13 之后要等 300ms 才能回读到真实生效值，
      // 这段等待正好被首张的「上传+后端转码+下载」网络耗时吸收，不额外拖慢链路
      // （对齐小程序 result.js：先 startPrefetch(0)，再并行 optimizeConnectionIntervalForTransfer）。
      // 必须在第一次 uploadImage 之前完成，否则整批就白设了。
      await trace.measure(
        'set-fast-connection-interval',
        client.beginTransferSession,
      );
      sessionOpened = true;

      // 2) 逐张：预取的 .bin 帧 → 选空闲槽位 → 图传 → 设备成功才写记录 → 刷新显示。
      for (int i = 0; i < total; i++) {
        if (shouldAbort?.call() ?? false) throw ProjectionAbortedException();

        // 新的一张：百分比归 0，张数计到 i+1，标题切「图片处理中」（对齐小程序 result.js:452-456）。
        emit(
          0,
          _l10n?.castPreparingImage(i + 1, total) ?? '正在准备第 ${i + 1}/$total 张…',
          title: _l10n?.castStageProcessing ?? CastStage.processing,
          current: i + 1,
        );
        final acquired = await prefetch[i]!;
        // 本张帧一到手，立刻启动下一张的预取，让它与本张 BLE 图传并行。
        startPrefetch(i + 1);

        final frameData = acquired.frameData;
        if (frameData.length != expected4bpp) {
          final head = FrameProtocol.bytesToHex(
            frameData.sublist(0, frameData.length < 16 ? frameData.length : 16),
          );
          throw FrameBleException(
            '后端返回的不是设备要的六色4bpp帧：收到 ${frameData.length} 字节(头16=$head)，'
            '设备 ${info.width}×${info.height} 需要 $expected4bpp 字节',
          );
        }

        final index = FrameProtocol.firstFreeIndex(
          FrameProtocol.indexesToMask(usedIndexes),
          info.capacity,
        );
        if (index < 0) throw FrameBleException('电子纸设备已存满', kind: FrameBleErrorKind.storageFull);

        // 开始图传本张：标题切「图片传输中」，百分比从 0 起（对齐小程序 result.js:483）。
        emit(
          0,
          _l10n?.castTransferringImage(i + 1, total) ??
              '正在投第 ${i + 1}/$total 张…',
          title: _l10n?.castStageTransferring ?? CastStage.transferring,
        );

        // 进度上报节流：BLE 每收到一个 ACK 就会回调一次，一张图上千个包 → 上千次 setState。
        // 高频重建会反过来抢占主 isolate、拖慢图传本身。这里限制页面最多约 8 次/秒更新：
        // 百分比没变、或距上次上报不足 120ms 就跳过；100% 必发（保证进度条能走到头）。
        // 对齐小程序 result.js:517-533 的同款节流。UI 侧有 250ms 补间动画，跳帧也不会显得卡。
        var lastPercent = -1;
        var lastEmitMs = 0;
        final stopwatch = Stopwatch()..start();

        // 本张设备事务：只有 BLE 图传失败才回滚删掉刚传到设备的图，再向外抛出让整单判失败。
        try {
          await trace.measure(
            'ble-transfer-image-${i + 1}',
            () => client.uploadImage(
              screenType: info.screenType,
              index: index,
              width: info.width,
              height: info.height,
              data: frameData,
              pace: FrameBleClient.transferPacketPaceMs,
              window: FrameBleClient.transferWindowPackets,
              prepared: acquired.prepared, // D1/D2：预取阶段算好的 CRC32 + 预组帧
              // 连接参数由整批的 beginTransferSession 统一管，别每张来回切。
              manageConnection: false,
              shouldAbort: shouldAbort,
              onProgress: (done, totalPackets, phase, {stuckAt, retries}) {
                // 百分比 = 本张的分包进度（不是整单进度），对齐小程序 result.js:517。
                final frac = totalPackets == 0 ? 0.0 : done / totalPackets;
                final percent = (frac * 100).floor().clamp(0, 100);
                final nowMs = stopwatch.elapsedMilliseconds;
                if (percent != 100 &&
                    (percent == lastPercent || nowMs - lastEmitMs < 120)) {
                  return;
                }
                lastPercent = percent;
                lastEmitMs = nowMs;
                emit(
                  frac,
                  _l10n?.castTransferringImage(i + 1, total) ??
                      '正在投第 ${i + 1}/$total 张…',
                );
              },
            ),
          );
        } catch (error) {
          await _rollbackDeviceImage(client, index);
          rethrow;
        }

        // 设备图传成功 → 编辑投屏记录置成功(deviceUploadState=1)。
        //
        // **不 await**（同下面的 0x24 刷屏）：这是纯记账，失败本来就只忽略——既不回滚设备、
        // 也不把整单判失败。await 它等于在「本张传完」和「下一张开传」之间硬插一次完整的网络往返，
        // 批量投屏时这笔开销要乘以张数。改成后台发出，图传立刻接着下一张。
        // 用户走到投屏记录页时这几个请求早已落地（页面自己还会重新拉一次列表）。
        // imgIndex=本张实际写入设备的物理槽位 index：图库删除/刷新屏幕靠它定位这张图。
        // ⚠️ index 可能为 0（相框第一个位置），是合法值，勿按假值过滤。
        //
        // ⚠️ upirId 直接透传（可能为 null，由 API 层的 `?` 丢掉这个键），**不要 `?? ''` 兜底**：
        // setUserProductUpload 的响应里根本没有 upirId，恒为 null；空串喂给后端的 integer 字段
        // 会 400，记录就永远停在 deviceUploadState=0，图库（只显示成功上传的照片）没有这张。
        // 后端是按 taskId 定位记录的。详见 BoltFoxApi.editUserProductImgRecord 的注释。
        unawaited(
          BoltFoxApi.editUserProductImgRecord(
            upirId: acquired.upirId,
            taskId: acquired.taskId,
            deviceUploadState: 1,
            imgIndex: index,
          ).catchError((Object error) {
            // 不能再静默吞：这条挂了就是「投屏成功但图库没有这张」，而用户侧毫无线索
            // ——2026-07-19 这个 bug 正是因为无日志才只能靠翻 swagger 反推出来的。
            debugPrint(
              '[投屏] ⚠️ 投屏记录置成功失败（图库将缺这张）：'
              'taskId=${acquired.taskId} imgIndex=$index $error',
            );
            return null;
          }),
        );

        // 把该槽位记为已用，供下一张选槽位。
        firstSuccessfulIndex ??= index; // 本批第一张成功写入的真实槽位，收尾刷屏用它
        usedIndexes = [...usedIndexes, index];
        uploaded++;
        // 本张完成：百分比打满、张数计到已投成功数（对齐小程序 result.js:583）。
        emit(
          1,
          _l10n?.castTransferredImages(uploaded, total) ??
              '已投 $uploaded/$total 张',
          current: uploaded,
        );

        // 只有最后一张传完后才刷新屏幕(0x24)：部分固件收到 0x24 会断开蓝牙，批量传输中途刷屏会导致
        // 后续图片传输失败。故中间张一律不刷屏，等全部传完只执行一次 0x24。
        // ⚠️ 刷的是**第一张**成功写入的槽位（2026-08-04 产品口径），不是刚传完的这一张：
        //    多图投屏结束后相框应停在本批的首图上。张数与刷屏次数一字未改，只换了索引。
        // 追加3：0x24 改 fire-and-forget，不 await——图片已全部写入设备，立即返回成功页，刷屏在后台继续
        //（真机墨水屏刷完要 ~4s，成功页因此提前）。刷屏成败本就不影响投屏结果。
        if (i == total - 1) {
          // 存下刷屏 Future：finally 里把连接间隔回落到空闲档要等它跑完再发（避免撞 0x0B）。
          lastRefresh = client
              .refreshScreen(firstSuccessfulIndex ?? index)
              .catchError((_) => 0xFF);
        }
      }

      trace.finish(success: true);
      return ProjectionResult(
        success: true,
        uploaded: uploaded,
        total: total,
        message: _l10n?.castTransferredSingle ?? '投屏成功',
      );
    } on ProjectionAbortedException {
      // 部分成功也判成功页（对齐小程序 finishProjection：uploaded>=1 → success）：已物理写入设备的
      // 照片不该被显示成「投屏失败」，否则用户会重投造成重复上传（占用新槽位）。
      trace.finish(success: uploaded >= 1, stage: 'aborted');
      return ProjectionResult(
        success: uploaded >= 1,
        uploaded: uploaded,
        total: total,
        message: uploaded >= 1
            ? '已投 $uploaded/$total 张，其余已中断'
            : '投屏已中断：上传时手机息屏/切到后台，蓝牙会被挂起。请保持亮屏后重新投屏。',
        failureKind: FrameBleErrorKind.aborted,
      );
    } catch (error) {
      final raw = error is FrameBleException ? error.message : error.toString();
      // 图传内部中止（uploadImage 抛 'UPLOAD_ABORTED'）与外层一致，给友好文案。
      final aborted =
          (shouldAbort?.call() ?? false) || raw.contains('UPLOAD_ABORTED');
      // 任一张失败即中断本单（对齐小程序「任意一张失败即中断」）；但只要已成功过至少 1 张就判成功页
      //（部分成功），uploaded>=1 → success，与小程序 finishProjection 一致。
      trace.finish(success: uploaded >= 1, stage: 'failed');
      return ProjectionResult(
        success: uploaded >= 1,
        uploaded: uploaded,
        total: total,
        message: uploaded >= 1
            ? '已投 $uploaded/$total 张（有 ${total - uploaded} 张未成功）'
            : (aborted ? '投屏已中断：上传时手机息屏/切到后台，蓝牙会被挂起。请保持亮屏后重新投屏。' : raw),
        failureKind: aborted
            ? FrameBleErrorKind.aborted
            : (error is FrameBleException ? error.kind : null),
      );
    } finally {
      // 整批结束（成功/失败/中断都算）恢复省电：系统侧 LOW_POWER + 下发 0x13 回落到空闲连接间隔(100ms)。
      // 只在真的开过会话时才恢复。不 await——避免拖慢结果页返回；且若最后一张刚触发异步刷屏(0x24)，
      // 要等它跑完再发（刷屏期间设备回忙 0x0B，挤在一起会白白失败），失败/中断路径无刷屏则立即回落。
      if (sessionOpened) {
        final refresh = lastRefresh;
        if (refresh != null) {
          unawaited(refresh.whenComplete(() => client.endTransferSession()));
        } else {
          unawaited(client.endTransferSession());
        }
      }
    }
  }

  /// 读设备信息(0x01)，遇「设备忙(0x0B)」自动等待重试，直到设备空闲或超时。
  ///
  /// 🔑 治「投屏成功后立刻点『继续投屏』，跳到失败页却没有失败记录」（2026-07-19）。
  /// 成功投屏收尾会异步下发刷屏指令(0x24)，墨水屏实测要刷数秒；刷屏期间设备对
  /// **任何**指令都回 0x0B。用户此时选完图进来，0x01 一撞就抛，整单在第一步就失败。
  ///
  /// 而失败记录是 `setUserProductUpload(deviceUploadState: 0)` 的副作用——它在
  /// 本方法之后才会被调用，所以这条路径下后端一条记录都不会有。这正是用户看到的
  /// 「同样的操作，有时有记录有时没有」：能不能赶在刷屏结束后进来，纯看手速。
  ///
  /// 修法是**别让它失败**，而不是去补记一条没有原图、也没有 imgBle（点「重新投屏」
  /// 必然报「缺少设备帧」）的空记录——刷屏只是几秒的瞬态，等过去就好。等到超时
  /// 仍忙才按原路径抛出，由结果页弹「设备繁忙中，请稍后再试」（见 casting_progress_page）。
  Future<FrameDeviceInfo> _readTransferInfoAwaitingIdle(
    FrameBleClient client, {
    void Function()? onWaiting,
    Duration timeout = const Duration(seconds: 12),
    Duration interval = const Duration(milliseconds: 800),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var notified = false;
    while (true) {
      try {
        return await client.readTransferInfo();
      } on FrameBleException catch (error) {
        final retryable =
            error.kind == FrameBleErrorKind.busy ||
            error.kind == FrameBleErrorKind.commandPending;
        if (!retryable || !DateTime.now().isBefore(deadline)) {
          rethrow;
        }
        if (!notified) {
          notified = true;
          onWaiting?.call();
        }
        await Future<void>.delayed(interval);
      }
    }
  }

  /// 取本张要发给设备的六色 4bpp 帧 + 后端记录 id（2026-07-23 对齐小程序 07-22 链路切换）。
  /// 两路网络并行，任一失败本张失败——
  ///   · 设备帧：预览处理后的设备分辨率图([filePath]) → 统一压缩 → seekink 抖动接口出帧；
  ///   · 投屏记录：原图([originalPath]) → 同一套统一压缩 → setUserProductUpload 建记录拿 taskId。
  /// 帧失败时记录可能已按「未成功(0)」建好，与旧链路「转码成功后图传失败」同态，无需回滚。
  /// 纯网络 + 纯计算、无 UI 副作用：可被主循环「预取下一张」提前并行调用（见 castImages 的预取流水线）。
  Future<_AcquiredFrame> _acquireFrame({
    required FrameBleClient client,
    required String filePath,
    required String originalPath,
    required Object userProductId,
    required int width,
    required int height,
  }) async {
    final recordFuture = _uploadOriginalForRecord(
      filePath: originalPath,
      userProductId: userProductId,
      width: width,
      height: height,
    );
    final frameFuture = _fetchDitheringFrame(
      filePath: filePath,
      width: width,
      height: height,
    );
    // 并行等待：任一失败都抛给调用方；另一路的错误挂 ignore 丢弃监听，
    // 避免「完成出错但无监听者」被 PlatformDispatcher.onError 记成未处理异步错误。
    recordFuture.ignore();
    frameFuture.ignore();
    final record = await recordFuture;
    final frameData = await frameFuture;
    // D1/D2 图传预处理（整图 CRC32 + 按会话分包预组 0x21 帧），与上一张 BLE 传输/本张网络重叠。
    // 失败回退不阻断本张（uploadImage 拿不到 prepared 会现算现组）。
    PreparedTransfer? prepared;
    try {
      prepared = await client.prepareImageTransfer(frameData);
    } catch (_) {
      prepared = null;
    }
    return _AcquiredFrame(
      frameData: frameData,
      taskId: record.taskId,
      upirId: record.upirId,
      prepared: prepared,
    );
  }

  /// 设备帧：预览处理后的设备分辨率图 → 统一压缩（已是设备尺寸则原样通过，见 _prepareUploadSource
  /// 的 400KB 触发门）→ seekink 抖动接口出六色 4bpp 帧（[DitheringApi.requestFrameBin]）。
  Future<Uint8List> _fetchDitheringFrame({
    required String filePath,
    required int width,
    required int height,
  }) async {
    final uploadPath = await _prepareUploadSource(
      filePath: filePath,
      targetWidth: width,
      targetHeight: height,
    );
    try {
      return await DitheringApi.requestFrameBin(
        filePath: uploadPath,
        type: DitheringApi.typeForDevice(width, height),
      );
    } finally {
      if (uploadPath != filePath) {
        try {
          await File(uploadPath).delete();
        } catch (_) {}
      }
    }
  }

  /// 投屏记录上传（2026-07-22 起改传原图，只为建记录）：上传原图 → 后端按「未成功(0)」建
  /// 投屏记录并存图（图库/记录页展示的就是这张原图），返回 taskId/upirId；设备图传成功后再
  /// editUserProductImgRecord（按 taskId）置 1，逻辑不变。接口仍会转码并返回 .bin url，
  /// 但已不再下载使用——设备帧改由抖动接口生成（见 _fetchDitheringFrame）。
  /// 失败抛出，让本张投屏判为失败（记录建不起来，设备成功了也没法记账）。
  ///
  /// ⚠️ `upirId` 实际取不到（响应 DTO `BaseUploadApiOut` 只有 base64Img/formatColors/name/taskId/url），
  /// 这里仍然解析是为了后端哪天补上就能直接用；调用方必须把它当**可能为 null** 处理。
  Future<_RecordResult> _uploadOriginalForRecord({
    required String filePath,
    required Object userProductId,
    required int width,
    required int height,
  }) async {
    final uploadPath = await _prepareUploadSource(
      filePath: filePath,
      targetWidth: width,
      targetHeight: height,
    );
    Object? res;
    try {
      res = await BoltFoxApi.setUserProductUpload(
        filePaths: [uploadPath],
        userProductId: userProductId,
        targetWidth: width,
        targetHeight: height,
        deviceUploadState: 0,
      );
    } finally {
      if (uploadPath != filePath) {
        try {
          await File(uploadPath).delete();
        } catch (_) {}
      }
    }
    // 单文件上传返回该对象；兼容数组返回。
    final item = res is List ? (res.isNotEmpty ? res.first : null) : res;
    final map = item is Map ? item : const {};
    if (map['taskId'] == null) {
      // 没有 taskId 就无法在图传成功后 editUserProductImgRecord 记账，按建记录失败处理。
      throw FrameBleException('服务器未返回投屏记录ID');
    }
    return _RecordResult(taskId: map['taskId'], upirId: map['upirId']);
  }

  /// 上传前兜底压缩，对齐小程序 2026-07-16 的 `compressForUpload`：
  /// 源文件大于 400KB 才处理，长边压到**当前设备长边（1 倍 = 设备分辨率）**、JPEG 质量 90；
  /// 后端反正会把图缩到设备分辨率再做六色抖动，上传超过设备长边的像素纯属浪费流量与后端转码时间
  /// （原来传设备长边的 2 倍 ≈ 4 倍字节，正是「上传/后端转码慢」的主因，2026-07-17 对齐小程序修正）。
  /// 压缩失败或结果反而更大时继续用原文件，绝不阻断投屏。
  Future<String> _prepareUploadSource({
    required String filePath,
    required int targetWidth,
    required int targetHeight,
  }) async {
    try {
      final source = File(filePath);
      final sourceBytes = await source.length();
      if (sourceBytes <= _uploadCompressTriggerBytes) {
        return filePath;
      }
      // 传**文件路径**给 isolate、在 isolate 内读文件：原来主 isolate 先 readAsBytes
      // 整张原图（相机原片 8~15MB），再作为 compute 消息跨 isolate **拷贝**一份——
      // 瞬时 2× 原图内存 + 主 isolate 一次大 IO；低端机连投多张大图时是明显的内存尖峰。
      final encoded = await compute(
        _compressUploadSource,
        _UploadCompressRequest(
          filePath: filePath,
          maxLongEdge:
              (targetWidth > targetHeight ? targetWidth : targetHeight) *
              _uploadLongEdgeScale,
        ),
      );
      if (encoded == null || encoded.length >= sourceBytes) {
        return filePath;
      }
      final output = File(
        '${Directory.systemTemp.path}/cast_upload_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      await output.writeAsBytes(encoded, flush: true);
      return output.path;
    } catch (_) {
      return filePath;
    }
  }


  /// 单张投屏失败时的设备侧回滚：删掉本次刚传到设备的这张图（CMD 0x12）。回滚失败不覆盖原始失败原因。
  Future<void> _rollbackDeviceImage(FrameBleClient client, int index) async {
    if (index < 0) return;
    try {
      await client.deleteImage([index]);
    } catch (_) {}
  }
}

class _RecordResult {
  _RecordResult({this.taskId, this.upirId});
  final Object? taskId;
  final Object? upirId;
}

const int _uploadCompressTriggerBytes = 400 * 1024;
// 上传图片的目标长边 = 当前设备长边 × 此系数。对齐小程序 compressForUpload（2026-07-16）：取 1
//（= 设备分辨率）。后端只吐设备分辨率的六色帧，传更大的原图纯属浪费上传流量与后端转码时间。
const int _uploadLongEdgeScale = 1;
// JPEG 重编码质量，对齐小程序 UPLOAD_COMPRESS_QUALITY = 90。
const int _uploadCompressQuality = 90;

class _UploadCompressRequest {
  const _UploadCompressRequest({
    required this.filePath,
    required this.maxLongEdge,
  });

  final String filePath;
  final int maxLongEdge;
}

/// 顶层函数，在 compute isolate 内执行：读文件 + 解码 + 缩放 + JPEG 编码全在
/// 子 isolate，主 isolate 不碰原图字节。任何失败返回 null（调用方回退原文件）。
Uint8List? _compressUploadSource(_UploadCompressRequest request) {
  final Uint8List bytes;
  try {
    bytes = File(request.filePath).readAsBytesSync();
  } catch (_) {
    return null;
  }
  var image = img.decodeImage(bytes);
  if (image == null) {
    return null;
  }
  final longEdge = image.width > image.height ? image.width : image.height;
  if (longEdge > request.maxLongEdge) {
    final ratio = request.maxLongEdge / longEdge;
    image = img.copyResize(
      image,
      width: (image.width * ratio).round().clamp(1, request.maxLongEdge),
      height: (image.height * ratio).round().clamp(1, request.maxLongEdge),
    );
  }
  return Uint8List.fromList(
    img.encodeJpg(image, quality: _uploadCompressQuality),
  );
}

/// 预取流水线的一张成品：可直接图传的设备帧 + 记账 id + D1/D2 预处理结果。
class _AcquiredFrame {
  _AcquiredFrame({
    required this.frameData,
    this.taskId,
    this.upirId,
    this.prepared,
  });

  final Uint8List frameData;
  final Object? taskId;
  final Object? upirId;
  final PreparedTransfer? prepared;
}
