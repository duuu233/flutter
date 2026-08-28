import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

/// 麦克风授权的三态结果。见 [AiVoiceRecorder.requestPermission]。
enum AiMicPermission {
  granted,

  /// 用户明确拒绝（或系统不给弹了）。页面据此弹「去设置」引导。
  denied,

  /// 上一个授权框还开着，这一轮作废、什么都别提示——用户正对着弹窗做选择。
  busy,
}

/// 一段录好的音频（安卓「按住说话」录音上传方案的中间产物）。
class AiVoiceClip {
  const AiVoiceClip({
    required this.path,
    required this.durationMs,
    required this.byteLength,
  });

  /// 应用缓存目录下的 WAV 文件绝对路径。**上传完必须删**（由 `ai_voice_input.dart` 负责）。
  final String path;

  /// 录音时长（毫秒），由 PCM 净长度算得，不是墙上时钟——按住到松手之间的
  /// 通道往返、被系统打断丢掉的那几帧都不算在内，正好是「真的录到了多少」。
  final int durationMs;

  /// WAV 文件字节数（含 44 字节头）。只用于日志。
  final int byteLength;
}

/// 安卓原生录音通道（`VoiceRecorder.kt`）的 Dart 侧封装。
///
/// 只在安卓有实现：iOS 与桌面端调用会抛 [MissingPluginException]，这里一律吞成
/// 「起不来」（false / null），由 [AiVoiceInput] 在平台分支处保证根本不会走到这儿。
///
/// 录的是 **16 kHz 单声道 16 bit WAV**，理由与格式细节见 `VoiceRecorder.kt` 文件头。
class AiVoiceRecorder {
  AiVoiceRecorder._();

  static const MethodChannel _channel = MethodChannel(
    'com.boltfox.boltstar/voice_asr',
  );

  /// 麦克风权限是否已授予（不弹窗）。
  static Future<bool> hasPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } catch (error) {
      debugPrint('[AiVoice] hasPermission 异常: $error');
      return false;
    }
  }

  /// 申请麦克风权限（未授予时弹系统授权框）。
  ///
  /// ⚠️ 这个 Future 要等用户对着弹窗做完选择才会完成，可能停留好几秒。
  /// 调用方在 await 期间必须重新确认手指还按着（见 `_beginVoice` 的 `_voiceHolding`）。
  ///
  /// 返回值特意分了三态而不是 bool：[AiMicPermission.busy]（上一个授权框还开着）
  /// 与真正的「用户拒绝」必须分开，否则用户连按两下就会莫名其妙弹出「去设置」引导。
  static Future<AiMicPermission> requestPermission() async {
    try {
      final granted =
          await _channel.invokeMethod<bool>('requestPermission') ?? false;
      return granted ? AiMicPermission.granted : AiMicPermission.denied;
    } on PlatformException catch (error) {
      if (error.code == 'busy') {
        return AiMicPermission.busy;
      }
      debugPrint('[AiVoice] requestPermission 异常: $error');
      return AiMicPermission.denied;
    } catch (error) {
      debugPrint('[AiVoice] requestPermission 异常: $error');
      return AiMicPermission.denied;
    }
  }

  /// 开始录音。返回是否真的起来了（无权限 / 麦克风被别的应用占着 / 初始化失败都是 false）。
  static Future<bool> start() async {
    try {
      return await _channel.invokeMethod<bool>('start') ?? false;
    } catch (error) {
      debugPrint('[AiVoice] start 异常: $error');
      return false;
    }
  }

  /// 停止录音并取回文件。一个字节都没录到（按下即松手）返回 null，原生侧同时已删掉空文件。
  static Future<AiVoiceClip?> stop() async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('stop');
      final path = (map?['path'] ?? '').toString();
      if (path.isEmpty) {
        return null;
      }
      return AiVoiceClip(
        path: path,
        durationMs: (map?['durationMs'] as num?)?.toInt() ?? 0,
        byteLength: (map?['byteLength'] as num?)?.toInt() ?? 0,
      );
    } catch (error) {
      debugPrint('[AiVoice] stop 异常: $error');
      return null;
    }
  }

  /// 取消录音：停录并删掉文件，不产生任何可上传的音频。
  static Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } catch (error) {
      debugPrint('[AiVoice] cancel 异常: $error');
    }
  }
}
