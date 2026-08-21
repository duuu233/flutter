import 'package:flutter/material.dart';

import '../../network/boltstar_ai_api.dart';
import '../../shared/l10n/app_l10n.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_toast.dart';
import '../../state.dart' show AppLanguage;

/// BoltStar AI 模块的多语种错误文案 + 统一错误分发。对齐小程序 `utils/ai-i18n.js`。
///
/// 文案来源：`photo-album/assets/ai/BoltStar-i18n-Errors.json`——后端只回 code、不回面向用户的
/// 文案，文案由前端按语种管理（文档 §6.7）。**不并进 [AppL10n]**：这是一整套按错误码索引的表
/// （23 条 × 4 语种），塞进主文案目录只会淹没它，且它要跟着接口文档单独演进。
///
/// 语种取当前 App 语言（[AppLanguage]），与后端接口的 language 码同一数据源。
/// 文档 JSON 的 zh-CN / zh-TW 对应这里的 [AppLanguage.zh] / [AppLanguage.zhHant]。
class AiI18n {
  const AiI18n(this.language);

  /// 订阅语言作用域（语言切换会触发调用方重建）。
  factory AiI18n.of(BuildContext context) => AiI18n(AppL10n.of(context).language);

  final AppLanguage language;

  static const Map<String, Map<AppLanguage, String>> _texts = {
    'info.10001': {
      AppLanguage.zh: '对话记录已过期自动清除',
      AppLanguage.zhHant: '對話記錄已過期自動清除',
      AppLanguage.en: 'Chat history has expired and been cleared.',
      AppLanguage.ja: 'チャット履歴の有効期限が切れ、自動的に消去されました。',
    },
    'error.20003': {
      AppLanguage.zh: '缺少用户标识',
      AppLanguage.zhHant: '缺少用戶標識',
      AppLanguage.en: 'Missing user ID',
      AppLanguage.ja: 'ユーザーIDがありません',
    },
    'error.20004': {
      AppLanguage.zh: '缺少会话标识',
      AppLanguage.zhHant: '缺少會話標識',
      AppLanguage.en: 'Missing session ID',
      AppLanguage.ja: 'セッションIDがありません',
    },
    'error.20005': {
      AppLanguage.zh: '请输入内容',
      AppLanguage.zhHant: '請輸入內容',
      AppLanguage.en: 'Please enter a message',
      AppLanguage.ja: 'メッセージを入力してください',
    },
    'error.20006': {
      AppLanguage.zh: '请选择图片方向',
      AppLanguage.zhHant: '請選擇圖片方向',
      AppLanguage.en: 'Please select image orientation',
      AppLanguage.ja: '画像の向きを選択してください',
    },
    'error.20007': {
      AppLanguage.zh: '图片方向无效',
      AppLanguage.zhHant: '圖片方向無效',
      AppLanguage.en: 'Invalid image orientation',
      AppLanguage.ja: '無効な画像の向きです',
    },
    'error.20008': {
      AppLanguage.zh: '风格选项无效',
      AppLanguage.zhHant: '風格選項無效',
      AppLanguage.en: 'Invalid image style',
      AppLanguage.ja: '無効なスタイルです',
    },
    'error.20009': {
      AppLanguage.zh: '参数值超出范围',
      AppLanguage.zhHant: '參數值超出範圍',
      AppLanguage.en: 'Parameter out of range',
      AppLanguage.ja: 'パラメータが範囲外です',
    },
    'error.20010': {
      AppLanguage.zh: '请提供图片',
      AppLanguage.zhHant: '請提供圖片',
      AppLanguage.en: 'Please provide an image',
      AppLanguage.ja: '画像を提供してください',
    },
    'error.20011': {
      AppLanguage.zh: '缺少消息标识',
      AppLanguage.zhHant: '缺少訊息標識',
      AppLanguage.en: 'Missing message ID',
      AppLanguage.ja: 'メッセージIDがありません',
    },
    // 张数 2026-08-12 由 4 张放宽到 5 张（与 `_kMaxImages` / [AppL10n.aiMaxImages] 必须一致）。
    // ⚠️ BoltStar 文档 §二写的仍是 4 张，若服务端没同步放宽，第 5 张会被它按 20012 打回。
    'error.20012': {
      AppLanguage.zh: '一次最多处理 5 张图片',
      AppLanguage.zhHant: '一次最多處理 5 張圖片',
      AppLanguage.en: 'You can process up to 5 images at a time',
      AppLanguage.ja: '一度に処理できる画像は最大5枚です',
    },
    // v1.0.4 新增：每用户最多 20 个会话（`POST /session/new` 回 20013 MAX_SESSIONS_REACHED）
    'error.20013': {
      AppLanguage.zh: '会话数量已达上限（20 个），请先删除部分旧会话',
      AppLanguage.zhHant: '會話數量已達上限（20 個），請先刪除部分舊會話',
      AppLanguage.en:
          'You have reached the limit of 20 sessions. Please delete some old ones first.',
      AppLanguage.ja: 'セッション数が上限（20件）に達しました。古いセッションを削除してください',
    },
    'error.22001': {
      AppLanguage.zh: '内容不符合规范，请修改后重试',
      AppLanguage.zhHant: '內容不符合規範，請修改後重試',
      AppLanguage.en:
          'Content does not comply with guidelines. Please modify and try again.',
      AppLanguage.ja: '内容がガイドラインに違反しています。修正して再試行してください',
    },
    'error.22002': {
      AppLanguage.zh: '账号已被临时限制，{hours} 小时后恢复',
      AppLanguage.zhHant: '帳號已被暫時限制，{hours} 小時後恢復',
      AppLanguage.en: 'Account temporarily restricted. Recovery in {hours} hours.',
      AppLanguage.ja: 'アカウントが一時的に制限されています。{hours}時間後に復旧します',
    },
    'error.22003': {
      AppLanguage.zh: '账号已被永久限制',
      AppLanguage.zhHant: '帳號已被永久限制',
      AppLanguage.en: 'Account permanently restricted.',
      AppLanguage.ja: 'アカウントが永久的に制限されました',
    },
    'error.22005': {
      AppLanguage.zh: '请求过于频繁，请稍后再试',
      AppLanguage.zhHant: '請求過於頻繁，請稍後再試',
      AppLanguage.en: 'Too many requests. Please try again later.',
      AppLanguage.ja: 'リクエストが多すぎます。しばらくしてから再試行してください',
    },
    'error.23001': {
      AppLanguage.zh: '会话不存在或已删除',
      AppLanguage.zhHant: '會話不存在或已刪除',
      AppLanguage.en: 'Session not found or deleted.',
      AppLanguage.ja: 'セッションが存在しないか削除されました',
    },
    'error.23002': {
      AppLanguage.zh: '消息不存在或已删除',
      AppLanguage.zhHant: '訊息不存在或已刪除',
      AppLanguage.en: 'Message not found or deleted.',
      AppLanguage.ja: 'メッセージが存在しないか削除されました',
    },
    'error.30001': {
      AppLanguage.zh: '服务暂时不可用，请稍后重试',
      AppLanguage.zhHant: '服務暫時不可用，請稍後重試',
      AppLanguage.en: 'Service temporarily unavailable. Please try again later.',
      AppLanguage.ja: 'サービスが一時的に利用できません。しばらくしてから再試行してください',
    },
    'error.30002': {
      AppLanguage.zh: '响应超时，请稍后重试',
      AppLanguage.zhHant: '回應逾時，請稍後重試',
      AppLanguage.en: 'Response timed out. Please try again later.',
      AppLanguage.ja: '応答がタイムアウトしました。しばらくしてから再試行してください',
    },
    'error.30003': {
      AppLanguage.zh: '图片上传失败，请重试',
      AppLanguage.zhHant: '圖片上傳失敗，請重試',
      AppLanguage.en: 'Image upload failed. Please try again.',
      AppLanguage.ja: '画像のアップロードに失敗しました。再試行してください',
    },
    'error.30004': {
      AppLanguage.zh: '数据读取失败，请重试',
      AppLanguage.zhHant: '資料讀取失敗，請重試',
      AppLanguage.en: 'Data read failed. Please try again.',
      AppLanguage.ja: 'データの読み取りに失敗しました。再試行してください',
    },
    'error.31001': {
      AppLanguage.zh: '系统异常，请稍后重试',
      AppLanguage.zhHant: '系統異常，請稍後重試',
      AppLanguage.en: 'System error. Please try again later.',
      AppLanguage.ja: 'システムエラーが発生しました。しばらくしてから再試行してください',
    },
  };

  /// 一键生图自动拼接的 message 文案（文档 §5.3.2：img_style 触发生图时 message 仍必填）。
  static const Map<String, Map<AppLanguage, String>> _genMessages = {
    'cartoon': {
      AppLanguage.zh: '生成图片-卡通',
      AppLanguage.zhHant: '生成圖片-卡通',
      AppLanguage.en: 'Generate image - Cartoon',
      AppLanguage.ja: '画像を生成-漫画',
    },
    'landscape': {
      AppLanguage.zh: '生成图片-风景',
      AppLanguage.zhHant: '生成圖片-風景',
      AppLanguage.en: 'Generate image - Landscape',
      AppLanguage.ja: '画像を生成-風景',
    },
    'portrait': {
      AppLanguage.zh: '生成图片-人像',
      AppLanguage.zhHant: '生成圖片-人像',
      AppLanguage.en: 'Generate image - Portrait',
      AppLanguage.ja: '画像を生成-人物',
    },
    'anime': {
      AppLanguage.zh: '生成图片-动漫',
      AppLanguage.zhHant: '生成圖片-動漫',
      AppLanguage.en: 'Generate image - Anime',
      AppLanguage.ja: '画像を生成-アニメ',
    },
  };

  /// 取文案并替换 `{hours}` 之类的占位；key 不存在返回 ''（由调用方决定降级）。
  String t(String key, [Map<String, dynamic>? params]) {
    final template = _texts[key]?[language] ?? '';
    if (template.isEmpty) {
      return '';
    }
    return template.replaceAllMapped(RegExp(r'\{(\w+)\}'), (match) {
      final value = params?[match.group(1)];
      return value == null ? match.group(0)! : '$value';
    });
  }

  /// 错误码 → 文案；未知 code 降级到 31001「系统异常」。
  String textForCode(int code, [Map<String, dynamic>? params]) {
    final text = t('error.$code', params);
    return text.isEmpty ? t('error.31001') : text;
  }

  /// 一键生图按当前语种拼 message（如「生成图片-卡通」）。
  String genMessage(String styleKey) {
    final map = _genMessages[styleKey] ?? _genMessages['cartoon']!;
    return map[language] ?? map[AppLanguage.zh]!;
  }

  /// 统一错误分发（文档 §6.7 /「前端处理区间速查」）：
  ///   - 22002/22003 封禁      → 弹窗（只有「知道了」）+ 回调 [onBanned]，页面据此禁用输入；
  ///   - 20013 会话数达上限     → 传了 [onSessionLimit] 则弹「去清理」确认框（v1.0.4），否则 toast；
  ///   - 30000~30999 上游错误   → 传了 [onRetry] 则弹「重试」确认框，否则 toast；
  ///   - 其余（参数/违规/资源） → toast。
  ///
  /// [error] 为 [AiApiException]；其它异常按 31001 处理。**用户主动 abort 的静默**，
  /// 调用方应在 catch 里先判 [AiApiException.aborted] 直接 return，不进这里。
  Future<void> handleError(
    BuildContext context,
    Object error, {
    VoidCallback? onRetry,
    void Function(int code)? onBanned,
    VoidCallback? onSessionLimit,
  }) async {
    final ai = error is AiApiException ? error : null;
    if (ai != null && ai.aborted) {
      return; // 双保险：用户主动停止，静默
    }
    final code = ai?.code ?? 31001;
    final userMessage = ai?.userMessage?.trim() ?? '';
    final message = userMessage.isNotEmpty
        ? userMessage
        : textForCode(code, ai?.params);

    // detail 是开发者排障信息，严禁展示给用户，只打日志
    if (ai?.detail != null) {
      debugPrint('[BoltStar] code=$code ${ai!.detail}');
    }

    // userMessage 只由网络层对白名单中的固定网关字段签名生成。它必须直接 toast，
    // 并保留 RequestId 供用户截图后定位；不能退化成展示任意 detail。
    if (userMessage.isNotEmpty) {
      if (context.mounted) {
        AppToast.show(
          context,
          '接口-$message',
          duration: const Duration(seconds: 5),
        );
      }
      return;
    }

    final l10n = AppL10n.of(context);
    if (code == 22002 || code == 22003) {
      onBanned?.call(code);
      await showAppConfirmDialog(
        context,
        title: l10n.tipTitle,
        message: message,
        icon: Icons.block_rounded,
        tone: AppDialogTone.danger,
        showCancel: false,
        confirmLabel: l10n.otaKnow,
      );
      return;
    }

    // 20013 MAX_SESSIONS_REACHED（v1.0.4，每用户上限 20 个会话）：文档要求「引导用户清理旧会话」。
    // 光 toast 用户不知道去哪清，所以页面传了 onSessionLimit 就弹确认框直接把人送到会话列表页去删；
    // 没传就退回 toast（与 30xxx 的 onRetry 同一套路）。重试对它没意义，故不落下面的重试分支。
    if (code == 20013 && onSessionLimit != null) {
      final go = await showAppConfirmDialog(
        context,
        title: l10n.tipTitle,
        message: message,
        icon: Icons.cleaning_services_rounded,
        confirmLabel: l10n.aiGoCleanSessions,
        cancelLabel: l10n.cancel,
      );
      if (go == true) {
        onSessionLimit();
      }
      return;
    }

    if (code >= 30000 && code < 31000 && onRetry != null) {
      final retry = await showAppConfirmDialog(
        context,
        title: l10n.tipTitle,
        message: message,
        icon: Icons.refresh_rounded,
        confirmLabel: l10n.retry,
        cancelLabel: l10n.cancel,
      );
      if (retry == true) {
        onRetry();
      }
      return;
    }

    if (context.mounted) {
      AppToast.show(context, message);
    }
  }
}
