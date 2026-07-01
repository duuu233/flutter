// 服务器图片转换 + BLE 图传投屏服务 —— 由微信小程序版 `subpackages/projection/result/result.js` 移植。
//
// 链路（画质相关计算放到服务器，避免受端上解码/缩放差异影响，见
// docs `server-image-processing-ble-transfer.md`）：
//   连接设备 → 读设备信息(0x01) → 逐张：
//     原图传后端转换(setUserProductUpload，按设备宽高转成六色 4bpp 帧 .bin，得下载地址 + taskId + upirId)
//     → 下载 .bin 帧数据 → 校验长度==宽×高÷2 → 选空闲槽位 → BLE 图传(0x20/0x21/0x22)
//     → 设备成功才编辑投屏记录(editUserProductImgRecord 置 deviceUploadState=1) → 刷新显示。
//
// 与 App 已有的「本地六色量化 + 图传」(BleController.uploadRgba) 并列：那条是端上处理；
// 本条是「后端转换」，两者最终都复用同一 BLE 图传协议(FrameBleClient.uploadImage)。

import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../device/ble/device_ble.dart';
import '../../device/ble/frame_protocol.dart';
import '../../device/ble_controller.dart';
import '../../network/boltfox_api.dart';

/// 投屏进度回调载荷。
class CastProgress {
  const CastProgress({
    required this.percent,
    required this.current,
    required this.total,
    required this.message,
  });

  final double percent; // 0~1，整单总进度
  final int current; // 已成功张数
  final int total; // 总张数
  final String message;
}

/// 投屏结果。
class ProjectionResult {
  const ProjectionResult({
    required this.success,
    required this.uploaded,
    required this.total,
    required this.message,
  });

  final bool success;
  final int uploaded;
  final int total;
  final String message;
}

/// 用户主动中断（切后台 / 离开页面）。
class ProjectionAbortedException implements Exception {
  @override
  String toString() => 'UPLOAD_ABORTED';
}

/// 服务器转换 + BLE 图传投屏服务。复用 [BleController] 持有的已连接设备。
class ServerImageProjectionService {
  ServerImageProjectionService({BleController? ble})
      : _ble = ble ?? BleController.instance;

  final BleController _ble;

  /// 逐张把 [filePaths] 里的原图经后端转换成设备帧并图传到设备。
  ///
  /// [userProductId] 为后端设备 id（写投屏记录用）。任一张失败即整单失败并返回失败原因；
  /// 已成功传到设备的张数保留在设备上（本张成功即物理写入）。
  Future<ProjectionResult> castImages({
    required Object userProductId,
    required List<String> filePaths,
    void Function(CastProgress)? onProgress,
    bool Function()? shouldAbort,
  }) async {
    final client = _ble.client;
    final images = filePaths.where((p) => p.isNotEmpty).toList();

    if (!client.connected) {
      return const ProjectionResult(
        success: false,
        uploaded: 0,
        total: 0,
        message: '设备未连接，请先连接设备后再投屏',
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

    void emit(double percent, String message) {
      onProgress?.call(CastProgress(
        percent: percent.clamp(0.0, 1.0).toDouble(),
        current: uploaded,
        total: total,
        message: message,
      ));
    }

    try {
      // 1) 读取真实设备信息（屏幕尺寸/类型/容量/已存掩码）。
      emit(0, '正在读取设备信息…');
      final info = await client.readDeviceInfo();
      if (info.screenType == 0x03 || info.width == 0 || info.height == 0) {
        throw FrameBleException('该型号暂不支持图传');
      }
      final expected4bpp = (info.width * info.height + 1) ~/ 2; // 六色 4bpp = 宽×高÷2（向上取整）

      // 设备空间校验：剩余可存张数 = 容量 - 已存张数（掩码置位数）。
      var usedIndexes = FrameProtocol.maskToIndexes(info.imgMask);
      final free = info.capacity - usedIndexes.length;
      if (free < total) {
        throw FrameBleException('设备空间不足：剩余 ${free < 0 ? 0 : free} 张，待投 $total 张');
      }

      // 2) 逐张：原图传后端转换得 .bin → 下载 → 选空闲槽位 → 图传 → 设备成功才写记录 → 刷新显示。
      for (int i = 0; i < total; i++) {
        if (shouldAbort?.call() ?? false) throw ProjectionAbortedException();

        emit(i / total, '正在转换第 ${i + 1}/$total 张照片…');
        final converted = await _convertOnServer(
          filePath: images[i],
          userProductId: userProductId,
          width: info.width,
          height: info.height,
        );
        final frameData = await _downloadFrameBin(converted.url);
        if (frameData.length != expected4bpp) {
          final head = FrameProtocol.bytesToHex(
              frameData.sublist(0, frameData.length < 16 ? frameData.length : 16));
          throw FrameBleException(
            '后端返回的不是设备要的六色4bpp帧：收到 ${frameData.length} 字节(头16=$head)，'
            '设备 ${info.width}×${info.height} 需要 $expected4bpp 字节',
          );
        }

        final index = FrameProtocol.firstFreeIndex(
            FrameProtocol.indexesToMask(usedIndexes), info.capacity);
        if (index < 0) throw FrameBleException('设备已存满');

        emit(i / total, '正在投第 ${i + 1}/$total 张…');

        // 本张设备事务：只有 BLE 图传失败才回滚删掉刚传到设备的图，再向外抛出让整单判失败。
        try {
          await client.uploadImage(
            screenType: info.screenType,
            index: index,
            width: info.width,
            height: info.height,
            data: frameData,
            shouldAbort: shouldAbort,
            onProgress: (done, totalPackets, phase, {stuckAt, retries}) {
              final frac = totalPackets == 0 ? 0.0 : done / totalPackets;
              emit((i + frac) / total, '正在投第 ${i + 1}/$total 张…');
            },
          );
        } catch (error) {
          await _rollbackDeviceImage(client, index);
          rethrow;
        }

        // 设备图传成功 → 编辑投屏记录置成功(deviceUploadState=1)。尽力而为：记账失败只忽略，
        // 不回滚设备、不把整单判失败（避免设备已传成功却被误判失败）。
        try {
          await BoltFoxApi.editUserProductImgRecord(
            upirId: converted.upirId ?? '',
            taskId: converted.taskId,
            deviceUploadState: 1,
          );
        } catch (_) {}

        // 传完顺手刷新到这张（失败不影响整体）；并把该槽位记为已用，供下一张选槽位。
        try {
          await client.refreshScreen(index);
        } catch (_) {}
        usedIndexes = [...usedIndexes, index];
        uploaded++;
        emit(uploaded / total, '已投 $uploaded/$total 张');
      }

      return ProjectionResult(
        success: true,
        uploaded: uploaded,
        total: total,
        message: '投屏成功',
      );
    } on ProjectionAbortedException {
      return ProjectionResult(
        success: false,
        uploaded: uploaded,
        total: total,
        message: '投屏已中断：上传时手机息屏/切到后台，蓝牙会被挂起。请保持亮屏后重新投屏。',
      );
    } catch (error) {
      final raw = error is FrameBleException ? error.message : error.toString();
      // 图传内部中止（uploadImage 抛 'UPLOAD_ABORTED'）与外层一致，给友好文案。
      final aborted = (shouldAbort?.call() ?? false) || raw.contains('UPLOAD_ABORTED');
      return ProjectionResult(
        success: false,
        uploaded: uploaded,
        total: total,
        message: aborted
            ? '投屏已中断：上传时手机息屏/切到后台，蓝牙会被挂起。请保持亮屏后重新投屏。'
            : raw,
      );
    }
  }

  /// 本张照片传后端转换：上传原图 → 后端按设备宽高转换成设备帧并存 OSS，返回 url/taskId/upirId。
  Future<_ConvertResult> _convertOnServer({
    required String filePath,
    required Object userProductId,
    required int width,
    required int height,
  }) async {
    final res = await BoltFoxApi.setUserProductUpload(
      filePaths: [filePath],
      userProductId: userProductId,
      targetWidth: width,
      targetHeight: height,
      deviceUploadState: 0,
    );
    // 单文件上传返回该对象；兼容数组返回。
    final item = res is List ? (res.isNotEmpty ? res.first : null) : res;
    final map = item is Map ? item : const {};
    final url = (map['url'] ?? map['fileUrl'] ?? map['path'])?.toString() ?? '';
    if (url.isEmpty) {
      throw FrameBleException('服务器未返回转换结果');
    }
    return _ConvertResult(url: url, taskId: map['taskId'], upirId: map['upirId']);
  }

  /// 下载后端转换好的六色 4bpp 帧(.bin)，读成字节直接喂给 BLE 图传（弱网重试几次）。
  Future<Uint8List> _downloadFrameBin(String url, {int attempts = 3}) async {
    Object? lastError;
    for (int i = 0; i < attempts; i++) {
      try {
        final resp = await http.get(Uri.parse(url));
        if (resp.statusCode == 200) {
          return resp.bodyBytes;
        }
        // HTTP 状态码错误属确定性失败，不重试。
        throw FrameBleException('转换结果下载失败(${resp.statusCode})');
      } on FrameBleException {
        rethrow;
      } catch (error) {
        lastError = error;
        if (i < attempts - 1) {
          await Future<void>.delayed(const Duration(milliseconds: 800));
        }
      }
    }
    throw FrameBleException('转换结果下载失败：${lastError ?? '网络异常'}');
  }

  /// 单张投屏失败时的设备侧回滚：删掉本次刚传到设备的这张图（CMD 0x12）。回滚失败不覆盖原始失败原因。
  Future<void> _rollbackDeviceImage(FrameBleClient client, int index) async {
    if (index < 0) return;
    try {
      await client.deleteImage([index]);
    } catch (_) {}
  }
}

class _ConvertResult {
  _ConvertResult({required this.url, this.taskId, this.upirId});
  final String url;
  final Object? taskId;
  final Object? upirId;
}
