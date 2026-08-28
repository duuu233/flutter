import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../network/boltstar_ai_api.dart';
import '../../state.dart' show AppLanguage;
import 'ai_voice_recorder.dart';

/// AI 聊天「按住说话」。有两套底层实现，由 [AiVoiceInput] 挑一套用：
///
/// | 端 | 首选 | 备胎 |
/// |---|---|---|
/// | 安卓 | `speech_to_text` → 系统 `SpeechRecognizer`（端上，音频不出手机） | 录音上传后端 ASR |
/// | iOS | `speech_to_text` → `SFSpeechRecognizer`（端上） | 无（系统识别一直可用） |
/// | 小程序 | 微信「同声传译」插件（端上） | 无 |
///
/// ## 安卓为什么需要备胎（2026-08-29）
///
/// 端上识别在**安卓国行机（华为、以及不少小米/OV 的国内版）上用不了** —— 这不是权限问题：
/// `SpeechRecognizer.isRecognitionAvailable()` 直接为 false。2026-08-28 真机实测确认：
/// 授权弹窗照弹（麦克风权限是系统给的），点完同意仍然报「不支持」，因为缺的是**识别服务**
/// 不是权限；清单里那两条 `<queries>` 只能解决「有服务但看不见」，服务本身不存在时无解。
/// 当时只能降级成一句「本机未提供系统语音识别」的提示。
///
/// 后端 2026-08-29 补上了 `POST /speech/recognize`（文档 `assets/BoltStar-语音识别接口文档.md`），
/// 于是安卓多了一条备胎：录音（`VoiceRecorder.kt`）→ 上传 → 豆包 ASR 转文字。
///
/// **顺序是先探系统、探不到才落备胎**（见 [ensureReady]），不是无条件走上传：
/// 端上识别音频不出手机、没有网络往返、也不花服务端的钱，有就该用。
/// 只有这台机器压根没有识别服务时，才值得付上传那一趟的代价：
///   · 录音参数压到 16 kHz 单声道（ASR 的标准输入，见 `VoiceRecorder.kt`），1 分钟约 1.9 MB；
///   · 松手到出文字之间页面要显示「识别中…」（[remote] 就是给页面判断这个的）。
///
/// iOS 不落备胎：系统识别在那边一直可用，没有理由多绕一趟网络。
///
/// ## 单例
/// 底层两条路都是「同一时刻只能有一路」（插件是全局单例式会话；麦克风也只有一个）。
/// 聊天页可能同时躺着好几个（从会话列表点开一条就新开一页），所以这里做成单例，
/// 由页面在 dispose 时 [cancel]，避免隐藏页还占着麦克风。
class AiVoiceInput {
  AiVoiceInput._();

  static final AiVoiceInput instance = AiVoiceInput._();

  /// 最近一次探测选中的那一套。[_settled] 为 true 时才是**定案**。
  _VoiceBackend? _backend;

  /// 链路定案了没有。
  ///
  /// 定了就不再回头探（一台手机有没有装识别服务不是运行时状态，每次按下都探一遍
  /// 只是白搭一次 `initialize()` 往返）。**但「授权被拒」不算定案**：用户完全可能
  /// 去设置里打开麦克风再回来按，那时必须能重新探一次，不能逼他杀进程重进。
  bool _settled = false;

  /// 这条链路是不是「录音上传」。
  ///
  /// 页面据此决定松手后要不要显示「识别中…」：端上识别是瞬时的，多晃一个状态反而闪；
  /// 上传识别要等一次网络往返，不给反馈就像卡住了。
  bool get remote => _backend?.remote ?? false;

  bool get isListening => _backend?.isListening ?? false;

  bool get permissionDenied => _backend?.permissionDenied ?? false;

  /// 惰性探测并汇报「这台机器能不能用语音输入」。
  ///
  /// 定链路的顺序：**先试系统识别**，可用就用它；安卓上不可用才换录音上传。
  /// 这里会拉起系统授权弹窗，所以必须在用户**真的按下**「按住说话」之后调，
  /// 不能在进页面时偷偷弹权限。
  ///
  /// 返回 false 时调用方要先看 [permissionDenied]：为 true 是「授权被拒」（引导去设置），
  /// 否则才是「这台机器起不来」（安卓备胎 = 录音起不来，iOS = 没有识别服务）。
  Future<bool> ensureReady() async {
    if (_settled) {
      return _backend!.ensureReady();
    }
    final system = _SystemSpeechBackend();
    _backend = system;
    if (await system.ensureReady()) {
      _settled = true;
      return true;
    }
    if (!Platform.isAndroid) {
      return false; // iOS 没有备胎：没有识别服务就是没有，如实上报
    }
    // 安卓：系统识别起不来。**先分清是不是麦克风被拒** —— 备胎要的是同一个
    // RECORD_AUDIO，刚被拒就换条路，只会紧接着再弹一次一模一样的授权框。
    // （`speech_to_text` 在安卓是先要权限、后查识别服务，所以被拒时它自己那个
    // permissionDenied 反而是 false —— 不能只信它，得直接问系统要不要得到权限。）
    if (system.permissionDenied || !await AiVoiceRecorder.hasPermission()) {
      system.markPermissionDenied();
      return false;
    }
    // 走到这里 = 麦克风有权限、但系统压根没有识别服务（国行无 GMS 的机型）：落录音上传。
    debugPrint('[AiVoice] 无系统识别服务，改走录音上传后端 ASR');
    final remote = _RemoteAsrBackend();
    _backend = remote;
    _settled = true;
    return remote.ensureReady();
  }

  /// 开始录音 / 监听。[language] 只对系统识别有意义（决定识别语种）；
  /// 后端 ASR 自己判语种，接口没有语种参数。
  ///
  /// [maxDuration] 与小程序 `VOICE_MAX_MS` 同口径（60s）：说太久既不好识别，
  /// 也容易把一整段话糊成一条消息；走备胎时原生侧还有一道同样时长的硬上限兜底。
  Future<bool> start({
    required AppLanguage language,
    Duration maxDuration = const Duration(seconds: 60),
  }) async {
    if (!_settled) {
      return false; // 链路还没定案（上一次探测没过），这一轮不该录
    }
    return _backend!.start(language: language, maxDuration: maxDuration);
  }

  /// 松手：停止录音并把识别到的文字交出来。
  Future<AiVoiceResult> stop() async {
    final backend = _backend;
    if (backend == null) {
      return const AiVoiceResult();
    }
    return backend.stop();
  }

  /// 上滑取消 / 页面销毁：丢弃这一轮，不产生任何文字，也不发起任何上传。
  Future<void> cancel() async {
    await _backend?.cancel();
  }
}

/// 一轮「按住说话」的结果。
///
/// 特意把「没识别到文字」和「这一轮失败了」分开：前者该提示「没听清，请再说一次」，
/// 后者（网络/服务异常）要走 `AiI18n.handleError` 的错误码文案，两者混成一个空串
/// 会让用户对着一句「没听清」反复重录一个根本发不出去的请求。
class AiVoiceResult {
  const AiVoiceResult({this.text = '', this.error});

  /// 识别出的文字。空串 = 没听清（说太轻 / 环境太吵 / 一开口就松手）。
  final String text;

  /// 非空表示这一轮**失败**（[text] 无意义）。安卓侧通常是 [AiApiException]。
  final Object? error;

  bool get failed => error != null;
}

// ── 后端抽象 ────────────────────────────────────────────────

abstract class _VoiceBackend {
  bool get remote;
  bool get isListening;
  bool get permissionDenied;
  Future<bool> ensureReady();
  Future<bool> start({
    required AppLanguage language,
    required Duration maxDuration,
  });
  Future<AiVoiceResult> stop();
  Future<void> cancel();
}

// ── 安卓备胎：录音 → 上传 → 转文字 ──────────────────────────

/// 录音上传做 ASR。**只在安卓、且这台机器没有系统识别服务时**才会被选中
/// （见 [AiVoiceInput.ensureReady]）。录音在 `VoiceRecorder.kt`，转写在
/// [BoltStarAiApi.recognizeSpeech]，本类只负责把两段串起来并保证**文件用完就删**。
class _RemoteAsrBackend implements _VoiceBackend {
  /// 短于这个时长的一段不上传：按下即松手（误触）录到的是几十毫秒的杂音，
  /// 传上去只会换回一个空结果，白等一次网络往返。
  static const int _minClipMs = 400;

  bool _recording = false;
  bool _permissionDenied = false;

  @override
  bool get remote => true;

  @override
  bool get isListening => _recording;

  @override
  bool get permissionDenied => _permissionDenied;

  @override
  Future<bool> ensureReady() async {
    if (await AiVoiceRecorder.hasPermission()) {
      _permissionDenied = false;
      return true;
    }
    switch (await AiVoiceRecorder.requestPermission()) {
      case AiMicPermission.granted:
        _permissionDenied = false;
        return true;
      case AiMicPermission.denied:
        _permissionDenied = true;
        return false;
      case AiMicPermission.busy:
        // 授权框还开着，这一轮安静作废：不是「被拒」，别弹「去设置」。
        _permissionDenied = false;
        return false;
    }
  }

  @override
  Future<bool> start({
    required AppLanguage language,
    required Duration maxDuration,
  }) async {
    if (_recording) {
      return false;
    }
    _recording = await AiVoiceRecorder.start();
    return _recording;
  }

  @override
  Future<AiVoiceResult> stop() async {
    if (!_recording) {
      return const AiVoiceResult();
    }
    _recording = false;
    final clip = await AiVoiceRecorder.stop();
    if (clip == null) {
      return const AiVoiceResult();
    }
    if (clip.durationMs < _minClipMs) {
      await _discard(clip);
      return const AiVoiceResult();
    }
    try {
      final bytes = await File(clip.path).readAsBytes();
      debugPrint(
        '[AiVoice] 上传 ${clip.durationMs}ms / ${bytes.length}B WAV 转文字',
      );
      final text = await BoltStarAiApi.recognizeSpeech(
        audioBase64: base64Encode(bytes),
      );
      return AiVoiceResult(text: text);
    } catch (error) {
      // 网络/服务/读文件失败都归到这里，交给页面按错误码提示。**不能吞成空串**：
      // 那会显示成「没听清，请再说一次」，用户重录多少次都一样。
      debugPrint('[AiVoice] 转文字失败: $error');
      return AiVoiceResult(error: error);
    } finally {
      await _discard(clip);
    }
  }

  @override
  Future<void> cancel() async {
    _recording = false;
    await AiVoiceRecorder.cancel();
  }

  /// 录音文件只是上传前的中转，落在 cacheDir 里也应当立即清掉：
  /// 一分钟就是 1.9 MB，攒几十条就是几十兆的「用户看不见也删不掉」的占用。
  Future<void> _discard(AiVoiceClip clip) async {
    try {
      final file = File(clip.path);
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (error) {
      debugPrint('[AiVoice] 删除录音文件失败: $error');
    }
  }
}

// ── 首选：系统语音识别（端上，音频不出手机）────────────────────

/// `speech_to_text` → iOS `SFSpeechRecognizer` / 安卓 `SpeechRecognizer`。
/// 两端都先试这条；安卓上它报「不可用」时才换备胎（见文件头）。
///
/// ⚠️ 插件把「识别」封装成一个**全局单例**式的会话：同一时刻只能有一路。
class _SystemSpeechBackend implements _VoiceBackend {
  final stt.SpeechToText _speech = stt.SpeechToText();

  /// `initialize()` **成功过**就不再调（重复调在部分平台会重置回调）。
  /// 失败则允许下次按下时重试：最常见的失败原因是用户刚拒了授权，而他完全可能
  /// 去设置里打开后再回来按 —— 一次失败就锁死的话，那次按下永远好不了。
  bool _ready = false;

  /// 上一次 `initialize()` 的结论：false = 这台机器没有可用的识别服务。
  bool _available = false;

  /// 用户是否拒绝过麦克风/语音识别授权。页面据此弹「去设置」而不是笼统报错。
  bool _permissionDenied = false;

  /// 本轮已识别到的文字。`onResult` 每来一次就覆盖一次（**不上屏**，见 [start]）。
  String _words = '';

  /// 本轮的终局结果；`stop()` 之后等它，等不到就退回 [_words]。
  Completer<String>? _finalResult;

  @override
  bool get remote => false;

  @override
  bool get isListening => _speech.isListening;

  @override
  bool get permissionDenied => _permissionDenied;

  /// 由 [AiVoiceInput.ensureReady] 在「安卓上直接问系统，发现麦克风其实没授权」时补标。
  /// 插件在安卓是先要权限、后查识别服务，被拒时它自己报的 [permissionDenied] 是 false。
  void markPermissionDenied() {
    _permissionDenied = true;
  }

  @override
  Future<bool> ensureReady() async {
    if (_ready) {
      return true;
    }
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
    _ready = _available;
    return _available;
  }

  @override
  Future<bool> start({
    required AppLanguage language,
    required Duration maxDuration,
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
          // 开着 partialResults 而不是只要终局：部分 ROM 在 `partialResults: false` 时
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

  /// 先等一小会儿终局结果：`stop()` 返回不等于识别引擎已经出结果，直接读 [_words]
  /// 会丢掉最后半句。等不到就用手上这份，绝不无限等。
  @override
  Future<AiVoiceResult> stop() async {
    final pending = _finalResult;
    try {
      await _speech.stop();
    } catch (error) {
      debugPrint('[AiVoice] stop 异常: $error');
    }
    if (pending == null) {
      return AiVoiceResult(text: _words.trim());
    }
    try {
      final text =
          await pending.future.timeout(const Duration(milliseconds: 1500));
      return AiVoiceResult(text: text.trim());
    } on TimeoutException {
      return AiVoiceResult(text: _words.trim());
    } finally {
      _finalResult = null;
    }
  }

  @override
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
  /// 各家系统给的写法不统一（`zh_CN` / `zh-CN` / `cmn_Hans_CN` 都见过），所以不写死，
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
