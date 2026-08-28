import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../state.dart' show AppLanguage;

/// AI 聊天的「按住说话」——**端上识别**，接口不参与。
///
/// 方案取自接口文档 v1.0.3 §5.1.3（Flutter 侧口径）：
///   按住 → `speech_to_text` 开始监听 → 松手 `stop()` → 拿 `recognizedWords` →
///   **直接走 `POST /chat`**，不经过输入框。
/// 底层是系统自带的语音识别（iOS `SFSpeechRecognizer` / Android `SpeechRecognizer`），
/// 音频不出手机、不上传，**后端零改动**。小程序那边同理（微信「同声传译」插件在端上转文字）。
///
/// ⚠️ **安卓国行机（华为、以及不少小米/OV 的国内版）没有系统识别服务** —— 这不是权限问题：
/// `SpeechRecognizer.isRecognitionAvailable()` 直接为 false，[ensureReady] 随之返回 false。
/// 2026-08-28 真机实测确认：授权弹窗照弹（麦克风权限是系统给的），点完同意仍然报「不支持」，
/// 因为缺的是**识别服务**不是权限。清单里那两条 `<queries>` 只能解决「有服务但看不见」，
/// 服务本身不存在时无解。
///
/// 页面据此降级成一句可操作的提示（引导用输入法自带的语音输入），而不是让人按住了没反应。
/// 要在这些机器上做出「按住说话」，只有一条路：**录音上传做 ASR**——
/// 端上用录音插件采集，音频交给后端转文字（第三方 ASR 的 AppKey 不能进客户端，
/// 所以绕不开后端）。见本轮文档的待办。
///
/// ⚠️ 插件把「识别」封装成一个**全局单例**式的会话：同一时刻只能有一路。
/// 聊天页可能同时躺着好几个（从会话列表点开一条就新开一页），所以这里也做成单例，
/// 由页面在 dispose 时 [cancel]，避免隐藏页还占着麦克风。
class AiVoiceInput {
  AiVoiceInput._();

  static final AiVoiceInput instance = AiVoiceInput._();

  final stt.SpeechToText _speech = stt.SpeechToText();

  /// `initialize()` 只该调一次（重复调在部分平台会重置回调）。
  bool _initialized = false;

  /// 上一次 `initialize()` 的结论：false = 这台机器没有可用的识别服务。
  bool _available = false;

  /// 用户是否拒绝过麦克风/语音识别授权。页面据此弹「去设置」而不是笼统报错。
  bool _permissionDenied = false;

  /// 本轮已识别到的文字。`onResult` 每来一次就覆盖一次（**不上屏**，见 [start]）。
  String _words = '';

  /// 本轮的终局结果；`stop()` 之后等它，等不到就退回 [_words]。
  Completer<String>? _finalResult;

  bool get isListening => _speech.isListening;

  bool get permissionDenied => _permissionDenied;

  /// 惰性初始化并汇报「这台机器能不能用语音输入」。
  ///
  /// `initialize()` 自己会拉起系统的麦克风 / 语音识别授权弹窗，所以第一次调用要在
  /// 用户**真的按下**「按住说话」之后，不能在进页面时偷偷弹权限。
  Future<bool> ensureReady() async {
    if (_initialized) {
      return _available;
    }
    _initialized = true;
    try {
      _available = await _speech.initialize(
        onError: (error) {
          debugPrint('[AiVoice] error ${error.errorMsg} permanent=${error.permanent}');
          // 授权被拒在两端的 errorMsg 不统一（iOS 常见 error_speech_recognizer_denied，
          // 安卓是 error_client / error_insufficient_permissions），一律按关键字兜。
          final message = error.errorMsg.toLowerCase();
          if (message.contains('permission') ||
              message.contains('denied') ||
              message.contains('not_authorized')) {
            _permissionDenied = true;
          }
          // 出错也要让 stop() 的等待收网，否则松手后会干等满超时。
          _completeFinal(_words);
        },
        onStatus: (status) {
          debugPrint('[AiVoice] status $status');
          // done / notListening 表示这一轮结束；此时 onResult 的终局多半已经来过。
          if (status == 'done' || status == 'notListening') {
            _completeFinal(_words);
          }
        },
      );
      if (!_available) {
        debugPrint('[AiVoice] 本机没有可用的语音识别服务');
      }
      // ⚠️ `hasPermission` 是 **Future<bool>**（不是同步 getter），要 await。
      _permissionDenied = _available && !(await _speech.hasPermission);
    } catch (error) {
      // 插件未注册（如桌面端跑 widget 测试）等异常一律按「不支持」处理，绝不冒泡到 UI。
      debugPrint('[AiVoice] initialize 异常: $error');
      _available = false;
    }
    return _available;
  }

  /// 开始监听。[language] 决定识别语种，取不到对应 locale 时交给系统默认。
  ///
  /// [maxDuration] 与小程序 `VOICE_MAX_MS` 同口径（60s）：说太久既不好识别，
  /// 也容易把一整段话糊成一条消息。
  Future<bool> start({
    required AppLanguage language,
    Duration maxDuration = const Duration(seconds: 60),
  }) async {
    if (!await ensureReady() || _speech.isListening) {
      return false;
    }
    _words = '';
    _finalResult = Completer<String>();
    try {
      await _speech.listen(
        onResult: (result) {
          // ⚠️ **中间结果不上屏**（2026-07-27 需求 4.3，两端同口径）：录音过程中一个字都不显示，
          // 松手后识别结果直接变成一条发出去的用户消息（参考 DeepSeek）。这里只是攒着。
          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) {
            _words = words;
          }
          if (result.finalResult) {
            _completeFinal(_words);
          }
        },
        // ⚠️ `localeId` / `listenFor` **必须写在 SpeechListenOptions 里**：
        // 6.6 起 `listen()` 上的同名具名参数已废弃（analyzer 会报 deprecated_member_use），
        // 7.0 直接移除。写进 options 在 6.6+ 与 7.x 上都成立。
        listenOptions: stt.SpeechListenOptions(
          localeId: await _resolveLocaleId(language),
          listenFor: maxDuration,
          // 开着 partialResults 而不是只要终局：部分安卓 ROM 在 `partialResults: false` 时
          // 会把结果一并吞掉，攒中间结果反而是更稳的拿法（反正不上屏）。
          partialResults: true,
          cancelOnError: true,
        ),
      );
      return true;
    } catch (error) {
      debugPrint('[AiVoice] listen 异常: $error');
      _completeFinal('');
      return false;
    }
  }

  /// 松手：停止监听并把识别到的文字交出来（没识别到返回空串）。
  ///
  /// 先等一小会儿终局结果：`stop()` 返回不等于识别引擎已经出结果，直接读 [_words]
  /// 会丢掉最后半句。等不到就用手上这份，绝不无限等。
  Future<String> stop() async {
    final pending = _finalResult;
    try {
      await _speech.stop();
    } catch (error) {
      debugPrint('[AiVoice] stop 异常: $error');
    }
    if (pending == null) {
      return _words.trim();
    }
    try {
      return (await pending.future.timeout(const Duration(milliseconds: 1500)))
          .trim();
    } on TimeoutException {
      return _words.trim();
    } finally {
      _finalResult = null;
    }
  }

  /// 上滑取消 / 页面销毁：丢弃这一轮，不产生任何文字。
  Future<void> cancel() async {
    _completeFinal('');
    _finalResult = null;
    _words = '';
    try {
      await _speech.cancel();
    } catch (error) {
      debugPrint('[AiVoice] cancel 异常: $error');
    }
  }

  void _completeFinal(String value) {
    final pending = _finalResult;
    if (pending != null && !pending.isCompleted) {
      pending.complete(value);
    }
  }

  /// 应用语种 → 系统识别用的 localeId。
  ///
  /// 各家 ROM 给的写法不统一（`zh_CN` / `zh-CN` / `cmn_Hans_CN` 都见过），所以不写死，
  /// 而是从 `locales()` 里按前缀挑一个；一个都不匹配就返回 null（交给系统默认语种）。
  /// 与小程序的差别：微信「同声传译」插件**没有日语**，系统识别有 —— 这条 App 反而更全。
  Future<String?> _resolveLocaleId(AppLanguage language) async {
    const candidates = <AppLanguage, List<String>>{
      AppLanguage.zh: ['zh_cn', 'zh_hans', 'cmn_hans', 'zh'],
      AppLanguage.zhHant: ['zh_tw', 'zh_hk', 'zh_hant', 'cmn_hant', 'zh'],
      AppLanguage.en: ['en_us', 'en_gb', 'en'],
      AppLanguage.ja: ['ja_jp', 'ja'],
    };
    try {
      final locales = await _speech.locales();
      final ids = <String>[
        for (final locale in locales) locale.localeId.toLowerCase().replaceAll('-', '_'),
      ];
      for (final prefix in candidates[language] ?? const <String>[]) {
        final index = ids.indexWhere((id) => id.startsWith(prefix));
        if (index >= 0) {
          return locales[index].localeId;
        }
      }
    } catch (error) {
      debugPrint('[AiVoice] locales 异常: $error');
    }
    return null;
  }
}
