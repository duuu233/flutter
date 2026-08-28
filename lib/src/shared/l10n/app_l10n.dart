import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../state.dart';
import 'chinese_script.dart';

/// 语言作用域：由 [MaterialApp.builder] 注入到 Navigator **之上**，成为所有路由（含 push 出来的
/// 业务页）的祖先。切换语言时其 [language] 变化，凡是通过 [AppL10n.of] 读取文案的页面（都注册了
/// 对本 InheritedWidget 的依赖）都会重建——这正是 Flutter 自带 `Localizations` 的机制，只是这里用
/// 一个轻量自定义实现，避免为整改引入 `flutter_localizations` 依赖 / 生成 .arb。
///
/// 用法：页面里 `AppL10n.of(context).xxx` 取文案；新增文案在 [AppL10n] 里加一个 `_pick` 条目即可。
class AppLocalizationsScope extends InheritedWidget {
  const AppLocalizationsScope({
    super.key,
    required this.language,
    required super.child,
  });

  final AppLanguage language;

  static AppLanguage languageOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppLocalizationsScope>();
    return scope?.language ?? AppLanguage.zh;
  }

  @override
  bool updateShouldNotify(AppLocalizationsScope oldWidget) =>
      language != oldWidget.language;
}

/// 应用文案目录。`AppL10n.of(context)` 会订阅 [AppLocalizationsScope]，语言变即整页重译。
///
/// 目前已接入：设置页、语种设置页、以及少量通用文案。其余页面仍是硬编码中文，逐页迁移到此处即可
/// （把 `Text('中文')` 换成 `Text(AppL10n.of(context).key)`，并在这里补 en/ja 译文）。
class AppL10n {
  const AppL10n(this.language);

  final AppLanguage language;

  /// 订阅语言作用域并返回当前语言的文案目录（依赖注册在此，语言变化会触发调用方重建）。
  static AppL10n of(BuildContext context) =>
      AppL10n(AppLocalizationsScope.languageOf(context));

  String _pick(String zh, String en, String ja, [String? zhHant]) {
    switch (language) {
      case AppLanguage.zh:
        return zh;
      case AppLanguage.zhHant:
        return zhHant ?? toTraditionalChinese(zh);
      case AppLanguage.en:
        return en;
      case AppLanguage.ja:
        return ja;
    }
  }

  /// 供页面侧的长文（法务文档等）按当前语言取文案：与 [_pick] 同规则，
  /// 繁中缺省时由简中自动转换。短文案仍应集中在本目录里加 getter。
  String pick(String zh, String en, String ja, [String? zhHant]) =>
      _pick(zh, en, ja, zhHant);

  // ── 后端 retMsg 兜底本地化 ─────────────────────────────────────────────
  /// 已知的后端 retMsg 原文 → (zh, en, ja)。BoltFox 后端**忽略** language 参数，
  /// retMsg 以英文为主（个别中文，如「请重新登录！」），简中/繁中/日文用户会直接
  /// 看到英文提示。已知文案在这里查表按当前语言重译；没命中的原样透传。
  /// 均为 2026-07 实测各错误分支收集（另含少量同族猜测条目，未命中无副作用）。
  static const Map<String, (String, String, String)> _serverMessages = {
    // —— 实测确认 ——
    'Please enter the correct email address': (
      '请输入正确的邮箱地址',
      'Please enter the correct email address',
      '正しいメールアドレスを入力してください',
    ),
    'Email does not exist': (
      '邮箱不存在或密码错误',
      'Email does not exist or the password is incorrect',
      'メールアドレスが存在しないか、パスワードが正しくありません',
    ),
    'Please enter the confirmation password': (
      '请输入确认密码',
      'Please enter the confirmation password',
      '確認用パスワードを入力してください',
    ),
    'Please input a password': (
      '请输入密码',
      'Please input a password',
      'パスワードを入力してください',
    ),
    'Verification code error': (
      '验证码错误',
      'Verification code error',
      '認証コードが正しくありません',
    ),
    '请重新登录！': ('请重新登录', 'Please log in again.', '再度ログインしてください'),
    // —— 同族猜测（未实测，命中即译） ——
    'Password error': ('密码错误', 'Password error', 'パスワードが正しくありません'),
    'Incorrect password': ('密码错误', 'Incorrect password', 'パスワードが正しくありません'),
    'Verification code expired': (
      '验证码已过期',
      'Verification code expired',
      '認証コードの有効期限が切れました',
    ),
    'The verification code has expired': (
      '验证码已过期',
      'The verification code has expired',
      '認証コードの有効期限が切れました',
    ),
    'Email already exists': (
      '该邮箱已被注册',
      'Email already exists',
      'このメールアドレスは既に登録されています',
    ),
    'The email already exists': (
      '该邮箱已被注册',
      'The email already exists',
      'このメールアドレスは既に登録されています',
    ),
  };

  /// 把后端 retMsg 按当前语言重译；未知文案原样返回。
  String localizeServerMessage(String raw) {
    final entry = _serverMessages[raw.trim()];
    if (entry == null) {
      return raw;
    }
    return _pick(entry.$1, entry.$2, entry.$3);
  }

  // ── 通用 ────────────────────────────────────────────────────────────────
  String get cancel => _pick('取消', 'Cancel', 'キャンセル');
  String get confirm => _pick('确定', 'OK', '確定');
  String get gotIt => _pick('我知道了', 'Got it', '了解しました');

  /// 多步确认里的「非终局」确认按钮：点了还会再弹一次，不能叫「确定」。
  String get continueLabel => _pick('继续', 'Continue', '続ける');
  String get save => _pick('保存', 'Save', '保存');

  /// 通用提示弹窗标题（校验失败、纯告知类提示统一用它）。
  String get tipTitle => _pick('提示', 'Notice', 'お知らせ');
  String get loading => _pick('加载中…', 'Loading…', '読み込み中…');

  // ── 网络层兜底（ApiClient 经 ApiSession 语言取用，无 BuildContext）─────
  String get netTimeout => _pick(
    '网络超时，请稍后再试',
    'Network timeout. Please try again later.',
    'ネットワークタイムアウトです。しばらくしてから再試行してください。',
  );
  String get netConnectFailed => _pick(
    '网络连接失败，请稍后再试',
    'Network connection failed. Please try again later.',
    'ネットワーク接続に失敗しました。しばらくしてから再試行してください。',
  );
  String get netSessionExpired => _pick(
    '登录已过期',
    'Session expired. Please log in again.',
    'ログインの有効期限が切れました。',
  );
  String get netServerError => _pick(
    '服务器异常',
    'Server error. Please try again later.',
    'サーバーエラーが発生しました。',
  );
  String get netRequestFailed =>
      _pick('业务处理失败', 'Request failed. Please try again.', '処理に失敗しました。');
  String get netUploadFileRequired => _pick(
    '请选择上传文件',
    'Please choose a file to upload.',
    'アップロードするファイルを選択してください。',
  );
  // 上传源文件已被系统清理/移动（区别于网络失败，提示用户重新选择而非查网络）。
  String get netUploadFileMissing => _pick(
    '文件不存在或已被清理，请重新选择',
    'The file is missing or has been cleaned up. Please choose it again.',
    'ファイルが存在しないか削除されています。もう一度選択してください。',
  );
  String get loadFailedTitle => _pick('加载失败', 'Failed to Load', '読み込みに失敗しました');
  String get loadFailedDesc => _pick(
    '网络异常，请检查网络后重试',
    'Network error. Check your connection and try again.',
    'ネットワークエラーです。接続を確認して再試行してください。',
  );
  String get retry => _pick('重试', 'Retry', '再試行');

  // ── 底部导航 ────────────────────────────────────────────────────────────
  String get tabHome => _pick('首页', 'Home', 'ホーム');
  // 底栏中间两格的标题（2026-08-19 起底栏四格，与小程序 `custom-tabbar` 同位同名）。
  //
  // ⚠️ 这两条是**tab 专用短标题**，与页内标题不是同一个 key：
  // · [tabAi]      ↔ [aiTitle]（AI 页内标题「AI生图」）
  // · [tabGallery] ↔ [galleryOfficialTitle]（图库页导航标题「官方图库」）
  // 四格之后每格只有屏宽的四分之一，页内标题的完整译名（Official Gallery /
  // 公式ギャラリー）在这里放不下。别互相替换。
  String get tabAi => _pick('AI助手', 'AI Assistant', 'AIアシスタント');
  String get tabGallery => _pick('官方图库', 'Gallery', 'ギャラリー');
  String get tabMine => _pick('我的', 'Mine', 'マイ');

  // ── 设置页 ──────────────────────────────────────────────────────────────
  String get settingsTitle => _pick('设置', 'Settings', '設定');
  String get languageSetting => _pick('语种设置', 'Language', '言語設定');
  String get contactUs => _pick('联系我们', 'Contact Us', 'お問い合わせ');
  String get privacyPolicy => _pick('隐私政策', 'Privacy Policy', 'プライバシーポリシー');
  String get userAgreement => _pick('用户协议', 'User Agreement', '利用規約');
  String get aiServiceAgreement =>
      _pick('AI服务协议', 'AI Service Agreement', 'AIサービス規約');
  String get aiServiceAgreementTitle => _pick(
    'BoltStar AI服务协议',
    'BoltStar AI Service Agreement',
    'BoltStar AIサービス規約',
  );
  String get aiServiceAgreementRequired => _pick(
    '请先同意BoltStar AI服务协议',
    'Please agree to the BoltStar AI Service Agreement first',
    '先にBoltStar AIサービス規約に同意してください',
  );
  /// 同意弹窗正文（三段，与小程序 `utils/ai-service-consent.js` 的 `CONSENT_SUMMARY` 同源）：
  /// ① 发给谁、做什么；② 内容用途；③ **境外传输告知** —— AI 网关部署在新加坡，内容出境是
  /// 需要单独告知的事项，细则在隐私政策第八节，弹窗只告知并指路，不复述整节法律文本。
  ///
  /// ⚠️ 简中按产品给的原文**逐字**写死；改动前请确认 `CONSENT_VERSION` 是否需要同步升版
  /// （数据接收方 / 出境情形这类实质变更必须让老用户重新确认，见 [AiServiceConsent.version]）。
  String get aiServiceAgreementSummary => _pick(
    '为了使用 AI 服务（包括文本对话、根据文字生成图片、以及上传图片进行美化），'
        '我们需要将您当前发送的内容（文字或图片）传输至“火山引擎”AI 服务进行处理，'
        '该服务由北京火山引擎科技有限公司提供。\n\n'
        '您发送的内容仅用于本次操作，不会被存储或用于模型训练。\n\n'
        '因该 AI 服务网关部署于境外（新加坡），上述内容将传输至境外处理，'
        '详情请见《BoltStar 隐私政策》第八节。',
    'To use AI services—including text chat, generating images from text, '
        'and enhancing uploaded images—we need to transmit the text or images '
        'you send to the Volcano Engine AI service for processing. This service '
        'is provided by Beijing Volcano Engine Technology Co., Ltd.\n\n'
        'The content you send is used only for the current operation and will '
        'not be stored or used for model training.\n\n'
        'Because the AI service gateway is deployed outside mainland China '
        '(Singapore), the content above is transferred abroad for processing. '
        'See Section 8 of the BoltStar Privacy Policy for details.',
    'テキスト対話、テキストからの画像生成、アップロード画像の加工を含むAIサービスを'
        '利用するため、送信されたテキストまたは画像を、北京火山引擎科技有限公司'
        '（Beijing Volcano Engine Technology Co., Ltd.）が提供する'
        '「火山引擎（Volcano Engine）」AIサービスへ送信して処理します。\n\n'
        '送信内容は今回の操作にのみ使用され、保存されることも、モデル学習に'
        '利用されることもありません。\n\n'
        '当該AIサービスのゲートウェイは国外（シンガポール）に設置されているため、'
        '上記の内容は国外へ送信のうえ処理されます。詳細は「BoltStar プライバシー'
        'ポリシー」第8章をご覧ください。',
  );
  String get agree => _pick('同意', 'Agree', '同意する');
  String get disagree => _pick('不同意', 'Disagree', '同意しない');
  String get checkUpdate => _pick('检查更新', 'Check for Updates', 'アップデート確認');
  String get logout => _pick('退出登录', 'Log Out', 'ログアウト');
  String get deleteAccount => _pick('用户注销', 'Delete Account', 'アカウント削除');

  /// 设置页「语种设置」行右侧的当前语言短标签。
  String get currentLanguageLabel => _pick('简中', 'English', '日本語', '繁中');

  String get checkingUpdate =>
      _pick('正在检查更新…', 'Checking for updates…', '更新を確認中…');
  String checkUpdateFailed(Object error) => _pick(
    '检查更新失败：$error',
    'Update check failed: $error',
    '更新の確認に失敗しました：$error',
  );
  String get checkUpdateFailedGeneric => _pick(
    '检查更新失败，请稍后再试',
    'Update check failed. Please try again later.',
    '更新の確認に失敗しました。しばらくしてから再試行してください。',
  );
  String alreadyLatest(String version) => _pick(
    '当前已是最新版本 v$version。',
    "You're on the latest version v$version.",
    '最新バージョン v$version です。',
  );
  String newVersionFound(String version) => _pick(
    '发现新版本 v$version',
    'New version v$version found',
    '新しいバージョン v$version',
  );
  String get newVersionPrompt => _pick(
    '检测到新版本，是否立即更新？',
    'A new version is available. Update now?',
    '新しいバージョンがあります。今すぐ更新しますか？',
  );
  String get updateLater => _pick('暂不更新', 'Not Now', '後で');
  String get updateNow => _pick('立即更新', 'Update Now', '今すぐ更新');
  String get noDownloadUrl => _pick(
    '暂无下载地址，请前往官网或应用商店更新。',
    'No download link. Please update via the website or app store.',
    'ダウンロードリンクがありません。公式サイトまたはストアから更新してください。',
  );
  String get openDownloadFailed => _pick(
    '无法打开下载地址，请前往官网或应用商店更新。',
    'Could not open the download link. Please update via the website or app store.',
    'ダウンロードリンクを開けませんでした。公式サイトまたはストアから更新してください。',
  );
  String get contactCopied => _pick('已复制联系方式', 'Contact copied', '連絡先をコピーしました');

  String get logoutConfirmMessage => _pick(
    '退出后将返回登录页，是否继续?',
    "You'll return to the login page. Continue?",
    'ログイン画面に戻ります。続行しますか？',
  );
  String get deleteAccountWarn1 => _pick(
    '注销将永久删除您的所有账号数据，请确认电子纸设备照片已自行清空，否则注销后将无法删除电子纸设备照片。',
    'Deleting your account permanently erases all account data. Please clear the photos on your e-paper device first, or they cannot be removed after deletion.',
    'アカウントを削除するとすべてのデータが完全に削除されます。先に電子ペーパーの写真を消去してください。削除後は電子ペーパーの写真を消せなくなります。',
  );
  String get deleteAccountConfirmTitle =>
      _pick('确认注销', 'Confirm Deletion', '削除の確認');
  String get deleteAccountWarn2 => _pick(
    '我已了解电子纸设备照片需自行处理的说明，并确认继续注销。',
    'I understand I must handle the e-paper device photos myself and confirm the deletion.',
    '電子ペーパーの写真は自分で処理する必要があることを理解し、削除を続行します。',
  );

  // ── 语种设置页 ──────────────────────────────────────────────────────────
  String get langSimplifiedChinese =>
      _pick('简体中文', 'Simplified Chinese', '簡体字中国語');
  String get langTraditionalChinese =>
      _pick('繁体中文', 'Traditional Chinese', '繁体字中国語');
  String get langEnglish => 'English';
  String get langJapanese => _pick('日本语', 'Japanese', '日本語');
  String get saveSettings => _pick('保存设置', 'Save', '保存');
  String get languageSaved =>
      _pick('语种设置已保存', 'Language settings saved', '言語設定を保存しました');

  // ── 账号 ──
  String get accAgreementRequired => _pick(
    '请先阅读并同意用户协议和隐私政策',
    'Please read and agree to the User Agreement and Privacy Policy first',
    '先に利用規約とプライバシーポリシーをお読みの上、同意してください',
  );
  String get accWechatUnavailable => _pick(
    '微信登录暂未开放',
    'WeChat login is not available yet',
    'WeChatログインはまだご利用いただけません',
  );
  String get accWechatLogin =>
      _pick('微信授权登录', 'Sign in with WeChat', 'WeChatでログイン');
  String get accWechatNotInstalled => _pick(
    '请先安装微信后再使用微信授权登录。',
    'Please install WeChat before signing in with WeChat.',
    'WeChatをインストールしてからWeChatログインをご利用ください。',
  );
  String get accWechatCanceled => _pick(
    '已取消微信授权。',
    'WeChat authorization canceled.',
    'WeChat認証をキャンセルしました。',
  );
  String get accWechatDenied => _pick(
    '微信授权被拒绝。',
    'WeChat authorization was denied.',
    'WeChat認証が拒否されました。',
  );
  String get accWechatVersionUnsupported => _pick(
    '当前微信版本不支持授权登录。',
    'This WeChat version does not support sign-in.',
    'このWeChatバージョンはログインに対応していません。',
  );
  String get accWechatTimeout => _pick(
    '微信授权已超时，请重新登录。',
    'WeChat authorization timed out. Please try again.',
    'WeChat認証がタイムアウトしました。再度お試しください。',
  );
  /// 微信授权登录成功提示（2026-08-19 需求：Android/iOS 从微信跳回 App 都要有反馈）。
  /// 邮箱登录**不弹**成功提示（界面切到主壳层本身就是反馈），微信这条是特例——
  /// 中间去了一趟微信客户端再跳回来，用户需要一句确认「这趟走通了」。
  String get accWechatLoginSuccess => _pick(
    '授权登录成功',
    'Signed in with WeChat',
    'WeChatでログインしました',
  );
  String get accWechatAuthFailed => _pick(
    '微信授权失败，请稍后重试',
    'WeChat authorization failed, please try again later',
    'WeChat認証に失敗しました。後ほど再試行してください',
  );
  String get accEmailHint => _pick('请输入邮箱', 'Enter email', 'メールアドレスを入力');
  String get accEmailInvalid => _pick(
    '请输入正确的邮箱地址',
    'Please enter a valid email address',
    '正しいメールアドレスを入力してください',
  );
  String get accPasswordHint =>
      _pick('请输入密码', 'Enter your password', 'パスワードを入力してください');
  String get accPasswordEmpty =>
      _pick('密码不能为空', 'Password cannot be empty', 'パスワードは空にできません');
  // 密码规则（注册 / 忘记密码 / 修改密码设置新密码时用；登录页不校验规则）。
  String get accPasswordRuleHint =>
      _pick('请输入6-12位数字加英文密码', '6-12 chars, letters/numbers', '6〜12桁の英数字');
  String get accPasswordRuleError => _pick(
    '密码需为6-12位数字和英文字母组合',
    'Password must be 6-12 characters and contain both letters and digits.',
    'パスワードは英字と数字を含む6〜12桁で入力してください',
  );
  String get accForgotPasswordLink =>
      _pick('忘记密码?', 'Forgot password?', 'パスワードをお忘れですか？');
  String get accWelcome => _pick('欢迎使用', 'Welcome to', 'ようこそ');
  String get accLoginSubtitle => _pick(
    '使用邮箱密码登录或注册',
    'Sign in or sign up with your email and password',
    'メールアドレスとパスワードでログインまたは登録',
  );
  String get accLoginButton => _pick('登 录', 'Log In', 'ログイン');
  String get accNoAccount =>
      _pick('没有账户？', "Don't have an account?", 'アカウントをお持ちでないですか？');
  String get accGoRegister => _pick(' 去注册', ' Sign up', ' 登録する');
  String get accAgreementPrefix =>
      _pick('我已阅读并同意', 'I have read and agree to', '以下に同意します');
  String get accUserAgreementLink => _pick('《用户协议》', 'User Agreement', '利用規約');
  String get accAnd => _pick('和', 'and', 'および');
  String get accPrivacyPolicyLink =>
      _pick('《隐私政策》', 'Privacy Policy', 'プライバシーポリシー');
  String get accPasswordMismatch =>
      _pick('密码不一致', 'Passwords do not match', 'パスワードが一致しません');
  String get accCreateAccount => _pick('创建账户', 'Create Account', 'アカウント作成');
  String get accEmail => _pick('邮箱', 'Email', 'メールアドレス');
  String get accEmailAddressHint =>
      _pick('请输入邮箱地址', 'Enter your email address', 'メールアドレスを入力してください');
  String get accPassword => _pick('密码', 'Password', 'パスワード');
  String get accConfirmPassword => _pick('确认密码', 'Confirm Pwd', 'パスワード確認');
  String get accConfirmPasswordHint =>
      _pick('请确认密码', 'Re-enter password', 'パスワードを再入力');
  String get accPasswordMismatchReconfirm => _pick(
    '密码不一致，请重新确认密码',
    'Passwords do not match. Please re-enter the confirmation.',
    'パスワードが一致しません。確認用パスワードを再入力してください',
  );
  String get accRegisterButton => _pick('注 册', 'Sign Up', '登録');
  String get accShowPassword => _pick('显示密码', 'Show password', 'パスワードを表示');
  String get accHidePassword => _pick('隐藏密码', 'Hide password', 'パスワードを非表示');
  String get accHaveAccount =>
      _pick('已有账户？', 'Already have an account?', 'すでにアカウントをお持ちですか？');
  String get accGoLogin => _pick(' 去登录', ' Log in', ' ログイン');
  String get accForgotPasswordTitle =>
      _pick('忘记密码', 'Forgot Password', 'パスワードを忘れた');
  String get accConfirmButton => _pick('确认', 'Confirm', '確認');
  String get accPasswordMismatchTwice => _pick(
    '两次输入的密码不一致',
    'The two passwords do not match',
    '入力した2つのパスワードが一致しません',
  );
  // 验证码组件（忘记密码 / 修改密码 / 修改邮箱共用 FigmaVerificationField；注册页为登录风格胶囊行）。
  String get accVerifyCodeLabel => _pick('验证码', 'Code', 'コード');
  String get accVerifyCodeHint => _pick('请输入验证码', 'Enter code', 'コードを入力');
  String get accGetVerifyCode => _pick('获取验证码', 'Send', '送信');
  String get accSendingCode => _pick('发送中…', 'Sending…', '送信中…');
  // 注册页副标题（注册页与登录页共用标题组风格，见 auth_widgets.dart）。
  String get accRegisterSubtitle => _pick(
    '注册BoltStar账号，把美好，留在一张纸上',
    'Sign up for BoltStar — keep every beautiful moment on paper',
    'BoltStarに登録して、大切な瞬間を一枚の紙に残しましょう',
  );

  String get accModifyEmailTitle => _pick('修改邮箱', 'Change Email', 'メールアドレス変更');
  String get accCurrentEmail => _pick('当前邮箱', 'Current Email', '現在のメールアドレス');
  String get accNewEmail => _pick('新邮箱', 'New Email', '新しいメールアドレス');
  String get accNewEmailHint =>
      _pick('请输入新的邮箱地址', 'Enter your new email address', '新しいメールアドレスを入力してください');
  String get accConfirmModify => _pick('确认修改', 'Confirm Change', '変更を確定');
  String get accPasswordMismatchRetry => _pick(
    '两次输入的密码不一致，请重新输入。',
    'The two passwords do not match. Please try again.',
    '入力した2つのパスワードが一致しません。もう一度入力してください。',
  );
  String get accModifyPasswordTitle =>
      _pick('修改密码', 'Change Password', 'パスワード変更');
  // 已登录改密走 changePassword：验证码只能发到账号绑定邮箱，未绑定时引导先绑定。
  String get accModifyPasswordNeedEmail => _pick(
    '请先绑定邮箱后再修改密码。',
    'Bind an email before changing your password.',
    'パスワード変更の前にメールアドレスを連携してください。',
  );
  String get accNewPassword => _pick('新密码', 'New Pwd', '新パスワード');
  String get accProfileTitle => _pick('个人信息', 'Profile', '個人情報');
  String get accNickname => _pick('昵称', 'Nickname', 'ニックネーム');
  String get accNicknameHint =>
      _pick('请输入昵称', 'Enter your nickname', 'ニックネームを入力してください');
  String get accSaveProfile => _pick('保存资料', 'Save Profile', 'プロフィールを保存');
  String get accNotBound => _pick('暂未绑定', 'Not bound', '未連携');
  String get accAvatar => _pick('头像', 'Avatar', 'アバター');
  String get accAvatarUploading =>
      _pick('头像上传中…', 'Uploading avatar…', 'アバターをアップロード中…');
  String get accAvatarUpdated =>
      _pick('头像已更新', 'Avatar updated', 'アバターを更新しました');
  String get accAvatarUpdateFailed =>
      _pick('头像更新失败', 'Failed to update avatar', 'アバターの更新に失敗しました');
  String get accCannotReadAlbum => _pick(
    '无法读取相册，请检查相册权限后重试。',
    'Cannot access the photo library. Check album permissions and try again.',
    'アルバムを読み込めません。権限を確認して再試行してください。',
  );
  String get saving => _pick('保存中', 'Saving…', '保存中…');
  String get accAlbumReadFailed => _pick(
    '无法读取相册，请检查相册权限后重试。',
    'Cannot access the album. Please check album permissions and try again.',
    'アルバムを読み込めません。アルバムの権限を確認してから再試行してください。',
  );
  String get accBindEmailTitle => _pick('绑定邮箱', 'Bind Email', 'メールアドレス連携');
  String get accBindEmailTip => _pick(
    '绑定邮箱可以用于app登录',
    'A bound email can be used to log in to the app',
    '連携したメールアドレスはアプリのログインに使用できます',
  );
  String get accConfirmBind => _pick('确认绑定', 'Confirm Binding', '連携を確定');
  String get accSetLoginPassword => _pick(
    '请设置用于 app 登录的密码。',
    'Please set a password for app login.',
    'アプリログイン用のパスワードを設定してください。',
  );
  String accResendIn(int seconds) =>
      _pick('$seconds秒后重新获取', '${seconds}s', '$seconds秒');

  // ── 投屏 ──
  String get castStageTranscoding =>
      _pick('图片转码中', 'Transcoding Image', '画像を変換中');
  String get castStageProcessing =>
      _pick('图片处理中', 'Processing Image', '画像を処理中');
  String get castStageTransferring =>
      _pick('图片传输中', 'Transferring Image', '画像を転送中');
  String get castReadingDeviceInfo =>
      _pick(
        '正在读取电子纸设备信息…',
        'Reading e-paper device information…',
        '電子ペーパーの情報を読み込んでいます…',
      );

  /// 刚投完屏、设备正在刷新（0x24）时对任何指令都回忙(0x0B)。这几秒是可等的短暂
  /// 状态，投屏入口会自动等它刷完再继续，期间给用户这条提示。
  String get castDeviceRefreshing => _pick(
    '电子纸设备正在刷新，请稍候…',
    'The e-paper device is refreshing, please wait…',
    '電子ペーパーを更新中です。しばらくお待ちください…',
  );

  /// 设备一直忙到超时才放弃时的系统提示框文案。
  String get castDeviceBusyTitle =>
      _pick('设备繁忙中', 'Device Busy', 'デバイスがビジー状態です');
  String get castDeviceBusyMessage => _pick(
    '电子纸设备繁忙中，请稍后再试。',
    'The e-paper device is busy right now. Please try again shortly.',
    '電子ペーパーがビジー状態です。しばらくしてからもう一度お試しください。',
  );

  String castPreparingImage(int current, int total) => _pick(
    '正在准备第 $current/$total 张…',
    'Preparing image $current of $total…',
    '$total 枚中 $current 枚目を準備中…',
  );
  String castTransferringImage(int current, int total) => _pick(
    '正在投第 $current/$total 张…',
    'Casting image $current of $total…',
    '$total 枚中 $current 枚目をキャスト中…',
  );
  String castTransferredImages(int uploaded, int total) => _pick(
    '已投 $uploaded/$total 张',
    'Cast $uploaded of $total images',
    '$total 枚中 $uploaded 枚をキャストしました',
  );
  String get castPreparingImageSingle =>
      _pick('正在准备图片…', 'Preparing image…', '画像を準備中…');
  String get castTransferringSingle => _pick('正在投屏…', 'Casting…', 'キャスト中…');
  String get castTransferredSingle =>
      _pick('投屏成功', 'Cast successful', 'キャストに成功しました');
  String get castResultSuccessTitle => _pick('投屏完成', 'Cast Complete', 'キャスト完了');
  String get castResultSuccessDesc => _pick(
    '照片已成功投屏到电子纸设备，可前往相册查看',
    'Photos were cast to the e-paper device. You can view them in the album.',
    '写真を電子ペーパーにキャストしました。アルバムでご確認いただけます。',
  );
  String get castResultFailDefaultDesc => _pick(
    '电子纸设备连接中断，请检查电子纸设备状态后重试',
    'E-paper device connection lost. Check the e-paper device and try again.',
    '電子ペーパーの接続が切れました。電子ペーパーの状態を確認して再試行してください。',
  );
  String get castProgressDefaultDesc => _pick(
    '投屏过程中请不要关闭手机',
    "Don't close the app while casting.",
    'キャスト中はアプリを閉じないでください。',
  );
  String get castFailureBusy => _pick(
    '当前电子纸设备繁忙，请稍后重试',
    'The e-paper device is busy. Please try again later.',
    '電子ペーパーが混雑しています。しばらくしてから再試行してください。',
  );
  String get castFailureStorageFull => _pick(
    '电子纸设备内存已满，请清理后继续。',
    'E-paper device storage is full. Free up space and continue.',
    '電子ペーパーの容量がいっぱいです。空き容量を確保してから続行してください。',
  );
  String get castFailureDisconnected => _pick(
    '电子纸设备未连接，请检查手机或电子纸设备连接后继续',
    'E-paper device not connected. Check the phone or e-paper device connection and continue.',
    '電子ペーパーが接続されていません。スマートフォンまたは電子ペーパーの接続を確認して続行してください。',
  );
  String get castFailureTimeout => _pick(
    '传输超时，请将手机靠近电子纸设备后重试',
    'Transfer timed out. Move the phone closer to the e-paper device and try again.',
    '転送がタイムアウトしました。スマートフォンを電子ペーパーに近づけて再試行してください。',
  );
  String get castFailureCanceled =>
      _pick('投屏已取消', 'Casting canceled.', 'キャストをキャンセルしました。');
  String get castCannotReadPhoto => _pick(
    '无法读取照片，请检查相机/相册权限后重试。',
    'Cannot read photos. Check camera/album permissions and try again.',
    '写真を読み込めません。カメラ/アルバムの権限を確認して再試行してください。',
  );
  String get castProgressTip1 => _pick(
    '投屏过程请保持手机亮屏，不要远离电子纸设备',
    'Keep the screen on and stay near the e-paper device while casting.',
    'キャスト中は画面を点灯したまま、電子ペーパーから離れないでください。',
  );
  String get castProgressTip2 => _pick(
    '批量投屏如果意外中断，请前往图库主动刷新屏幕',
    'If a batch cast is interrupted, refresh the screen from the gallery.',
    '一括キャストが中断された場合は、ギャラリーから画面を更新してください。',
  );
  String get castProgressTip3 => _pick(
    '图片在投屏记录中可继续操作',
    'You can keep working with photos in the cast history.',
    'キャスト履歴で写真の操作を続けられます。',
  );
  String get castProgressTip4 => _pick(
    '投屏完成后电子纸设备会自动刷新，刷新期间电子纸设备繁忙无法投屏，请等待刷新结束',
    'After casting, the e-paper device refreshes automatically. It stays busy and cannot cast during the refresh, so please wait until it finishes.',
    'キャスト完了後、電子ペーパーは自動的に更新されます。更新中はビジー状態でキャストできませんので、完了までお待ちください。',
  );
  String get castFailTip1 => _pick(
    '请确认电子纸设备蓝牙正常连接中，手机蓝牙正常使用',
    'Make sure the e-paper device Bluetooth is connected and the phone Bluetooth is working.',
    '電子ペーパーのBluetoothが接続され、スマートフォンのBluetoothが正常に動作していることを確認してください。',
  );
  String get castFailTip2 => _pick(
    '如屏幕正在刷新中，请稍后再试',
    'If the screen is refreshing, please try again later.',
    '画面が更新中の場合は、しばらくしてから再試行してください。',
  );
  String get castFailTip3 => _pick(
    '如遇系统网络故障，请稍后再试',
    'If there is a network problem, please try again later.',
    'ネットワーク障害が発生した場合は、しばらくしてから再試行してください。',
  );
  String get castFailTip4 => _pick(
    '投屏失败的图片可以前往投屏记录重新上传',
    'Failed photos can be re-uploaded from the cast history.',
    'キャストに失敗した写真は、キャスト履歴から再アップロードできます。',
  );
  String get castContinue => _pick('继续投屏', 'Continue Casting', 'キャストを続ける');
  String get castRecast => _pick('重新投屏', 'Cast Again', 'もう一度キャスト');
  String get castBackHome => _pick('返回首页', 'Back to Home', 'ホームに戻る');

  // ── 投屏中退出确认（PopScope 拦截）────────────────────────────────────
  String get castExitConfirmTitle =>
      _pick('正在投屏', 'Casting in Progress', 'キャスト中');
  String get castExitConfirmContent => _pick(
    '现在退出将中断本次投屏，已传输的图片可能不完整。确定要退出吗？',
    'Leaving now will interrupt this cast and photos may be incomplete. Leave anyway?',
    '今終了すると、このキャストが中断され、写真が不完全になる可能性があります。終了しますか？',
  );
  String get castExitConfirmStay => _pick('继续投屏', 'Keep Casting', 'キャストを続ける');
  String get castExitConfirmLeave => _pick('退出', 'Leave', '終了する');
  String get castDefaultDeviceName => _pick('相框', 'Frame', 'フォトフレーム');
  String get castManagementTitle => _pick('投屏管理', 'Cast Management', 'キャスト管理');
  String castTotalRecords(int count) =>
      _pick('共 $count 条记录', '$count records', '全 $count 件');
  String get castSucceeded => _pick('投屏成功', 'Cast Succeeded', 'キャスト成功');
  String get castFailed => _pick('投屏失败', 'Cast Failed', 'キャスト失敗');
  String get castCastAgain => _pick('再次投屏', 'Cast Again', '再度キャスト');
  String get castDelete => _pick('删除', 'Delete', '削除');
  String get castDeleteRecordTitle => _pick('删除投屏记录', 'Delete Record', '記録を削除');
  String get castDeleteRecordConfirm => _pick(
    '确定删除这条投屏记录吗？删除后不可恢复。',
    'Delete this cast record? This cannot be undone.',
    'このキャスト記録を削除しますか？削除すると元に戻せません。',
  );
  String get castRecordMissingFrame => _pick(
    '该记录缺少设备帧文件，无法再次投屏',
    'This record has no device frame file and cannot be cast again.',
    'この記録にはデバイスフレームファイルがなく、再度キャストできません。',
  );
  String get castConnectingDevice =>
      _pick('正在连接设备…', 'Connecting to device…', 'デバイスに接続中…');
  String get castEmptySuccessTitle =>
      _pick('暂无成功记录', 'No successful casts yet', '成功した記録はありません');
  String get castEmptyFailedTitle =>
      _pick('暂无失败记录', 'No failed casts yet', '失敗した記録はありません');
  String get castEmptySuccessDesc => _pick(
    '完成一次照片投屏后会显示在这里。',
    'Completed photo casts will appear here.',
    '写真のキャストが完了するとここに表示されます。',
  );
  // castEmptyFailedDesc（「投屏失败时会保留原因，方便排查。」）已于 2026-07-19 按
  // 产品要求下线，失败空态只保留标题；小程序 records.wxml 同步去掉。
  String get castPreviewTitle => _pick('照片预览', 'Preview', 'プレビュー');
  String get castStartCasting => _pick('开始投屏', 'Start Casting', 'キャスト開始');

  /// 「开始投屏」按钮的处理中态（对齐小程序 `projecting ? '投屏中' : '开始投屏'`）。
  String get castCasting => _pick('投屏中', 'Casting…', 'キャスト中…');
  String get castNoPhotos =>
      _pick('暂无待投屏照片', 'No photos to cast', 'キャストする写真がありません');
  String get castOriginal => _pick('原图', 'Original', '元の写真');
  String get castProcessing => _pick('处理中', 'Processing', '処理中');
  String get castRestore => _pick('还原', 'Restore', '戻す');
  String get castRestoreTitle => _pick('还原原图', 'Restore Original', '元の写真に戻す');
  String get castRestoreConfirm => _pick(
    '确定要还原到最原始的图片吗？当前的编辑将不会保存。',
    'Restore the original photo? Your current edits will not be saved.',
    '元の写真に戻しますか？現在の編集は保存されません。',
  );
  String get castKeepOnePhoto => _pick(
    '请至少保留一张照片',
    'Please keep at least one photo.',
    '少なくとも1枚の写真を残してください。',
  );
  String get castImageLoadFailed =>
      _pick('图片加载失败', 'Failed to load image', '画像の読み込みに失敗しました');
  // ── 预览页 2026-07-22 ~ 07-24 重构（常驻编辑 + 竖/横取景 + 长按拖拽 + 转90°）──
  // 07-24 交互二次大改后「上一张/下一张」按钮已取消（切图回到左右滑动），
  // 对应的 castPrevPhoto/castNextPhoto 两个键随之删除，勿再加回。
  String get castPortrait => _pick('竖向', 'Portrait', '縦向き');
  String get castLandscape => _pick('横向', 'Landscape', '横向き');
  /// 提示里的时长必须与 `cast_preview_page.dart` 的 `_kLongPress` 一致（2026-07-31 起 0.5 秒）。
  String get castEditHint => _pick(
    '长按0.5秒后可拖拽图片、双指可缩放与旋转图片',
    'Press and hold 0.5s to drag · Pinch with two fingers to zoom and rotate',
    '0.5秒長押しでドラッグ · 2本指で拡大・回転',
  );
  String get castRecordNoImage => _pick(
    '该记录没有可投屏的图片',
    'This record has no image to cast.',
    'この記録には投影できる画像がありません。',
  );
  String get castRecordImageDownloadFailed => _pick(
    '图片下载失败，请稍后重试',
    'Failed to download the image. Please try again later.',
    '画像のダウンロードに失敗しました。後でもう一度お試しください。',
  );

  // ── AI 对话（星宝）2026-07-25 ──
  // 错误码文案不在这里：那套按 code 索引的表在 `features/ai/ai_i18n.dart`（对齐小程序 ai-i18n.js）。
  String get aiTitle => _pick('AI生图', 'AI Studio', 'AI生成');
  String get aiNewChat => _pick('新对话', 'New Chat', '新しいチャット');
  String get aiSessions => _pick('会话', 'Chats', '履歴');
  String get aiSessionsTitle => _pick('历史会话', 'Chat History', 'チャット履歴');

  /// 会话列表右上角的「新建」（区别于聊天页里那句完整的「新对话」[aiNewChat]）。
  String get aiNewSessionAction => _pick('新建', 'New', '新規');

  // 2026-07-31 视觉稿的欢迎页：大标题 + 一句副文案 + 三条灵感词（点了只填草稿，不自动发送）。
  String get aiWelcomeGreeting =>
      _pick('您好！我是星宝', 'Hi! I am BoltStar', 'こんにちは！星宝です');
  String get aiWelcomeText => _pick(
    '您的 AI 创作伙伴，有什么我可以帮您的吗？',
    'Your AI creative partner. How can I help?',
    'AI創作パートナーです。何をお手伝いしましょう？',
  );

  /// 欢迎页灵感词。顺序与三张图标 `ai-suggestion-home/sunrise/palette.png` 一一对应，
  /// 增删条目要同步改 `ai_chat_page` 里的图标数组。
  List<String> get aiWelcomeSuggestions => [
    _pick(
      '生成一张温馨的客厅插画',
      'Draw a cozy living room',
      '居心地のよいリビングのイラストを生成',
    ),
    _pick('帮我写一句早安文案', 'Write me a good-morning line', 'おはようの一言を書いて'),
    _pick('把照片变成漫画风', 'Turn my photo into a comic', '写真を漫画風にして'),
  ];
  /// 2026-08-10 需求 8：输入框默认文案改为「按住说话或输入您的想法...」
  /// —— 右侧那颗麦克风按钮是语音入口，提示语要把两条路都说出来。
  String get aiInputHint => _pick(
    '按住说话或输入您的想法...',
    'Hold to talk, or type your idea…',
    '長押しで話す、または入力…',
  );
  String get aiInputWithImagesHint => _pick(
    '描述您想对图片做什么…',
    'Describe what to do with the images…',
    '画像に対して何をしたいか入力…',
  );
  String get aiSend => _pick('发送', 'Send', '送信');
  String get aiStopGenerating => _pick('停止生成', 'Stop', '生成を停止');
  String get aiHoldToTalk => _pick('按住 说话', 'Hold to talk', '長押しで話す');

  /// App 侧无录音/转写依赖（小程序那边是「同声传译」插件未开通），两端都只给占位提示。
  String get aiVoicePending =>
      _pick('语音转文字待接入', 'Voice input is not available yet.', '音声入力は未対応です');
  String get aiAlbum => _pick('相册', 'Album', 'アルバム');
  String get aiCamera => _pick('拍照', 'Camera', '撮影');
  String get aiGenerateImage => _pick('一键生图', 'Generate', '一発生成');

  /// 一键生图浮层的副标题：点风格即发，没有二次确认，得先说清楚。
  String get aiGenerateImageDesc =>
      _pick('选择后立即发送', 'Sends as soon as you pick', '選択するとすぐ送信');
  String get aiImageRatio => _pick('图片比例', 'Ratio', '画像比率');

  /// 比例浮层顶部的标题（2026-08-10 需求 3）：光是三行「竖向/横向/方形」看不出在设置什么。
  String get aiImageRatioPickerTitle =>
      _pick('设置文生图比例', 'Set image ratio', '生成画像の比率を設定');
  String get aiPickStyle => _pick('选择生图模式', 'Choose a style', '生成スタイルを選択');

  // 30xxx / 未知上游失败：不再只弹一次性 toast，气泡原地变成可重试的失败卡（对齐小程序 2026-07-30）。
  String get aiFailureTitle => _pick('生成未完成', 'Generation failed', '生成できませんでした');
  String get aiFailureDesc => _pick(
    '网络或服务繁忙，请稍后重试',
    'Network or service is busy. Please try again.',
    'ネットワークまたはサービスが混雑しています。後でお試しください',
  );
  String get aiRetryGenerate => _pick('重新生成', 'Try again', '再生成');

  // aiMessageActions（「消息操作」底部面板标题）2026-08-10 随面板一起删除，见下方确认框文案。

  // ── 删除消息 / 删除图片（2026-08-10 需求 2 & 7）──
  // 长按气泡空白处、以及图下方常驻操作条的「删除」都走这一套确认框（与全站弹框同版式），
  // 取代原来的底部操作面板（小程序侧同步撤掉了 wx.showActionSheet）。
  String get aiDeleteMessageTitle => _pick('删除消息', 'Delete message', 'メッセージを削除');
  String get aiDeleteMessageDesc => _pick(
    '删除后这条消息会从对话中移除，且无法恢复',
    'This message will be removed from the chat and cannot be recovered.',
    'このメッセージはチャットから削除され、復元できません。',
  );
  String get aiDeleteMessageWithImagesDesc => _pick(
    '删除后这条消息和其中的图片都会从对话中移除，且无法恢复',
    'This message and its images will be removed from the chat and cannot be recovered.',
    'このメッセージと画像はチャットから削除され、復元できません。',
  );
  String get aiDeleteImageTitle => _pick('删除图片', 'Delete image', '画像を削除');
  String get aiDeleteImageDesc => _pick(
    '删除后这张图片会从对话中移除，且无法恢复',
    'This image will be removed from the chat and cannot be recovered.',
    'この画像はチャットから削除され、復元できません。',
  );
  String get aiDownload => _pick('下载', 'Download', 'ダウンロード');
  String get aiCast => _pick('投屏', 'Cast', 'キャスト');
  String get aiDelete => _pick('删除', 'Delete', '削除');
  String get aiDeleted => _pick('已删除', 'Deleted', '削除しました');

  /// ⚠️ 与小程序的差异：小程序保存进系统相册；Flutter 无内置相册写入能力（需额外插件），
  /// 本轮只落到应用缓存目录，文案如实说明。
  String get aiDownloaded => _pick(
    '图片已下载到应用缓存（保存到系统相册待接入插件）',
    'Image saved to app cache (system gallery support pending).',
    'アプリのキャッシュに保存しました（システムアルバム保存は未対応）',
  );
  String get aiImageExpired => _pick(
    '图片下载失败（生成图 24 小时后过期）',
    'Download failed. Generated images expire after 24 hours.',
    'ダウンロードに失敗しました（生成画像は24時間で失効）',
  );
  String get aiPreparingCast => _pick('准备投屏', 'Preparing cast…', 'キャストの準備中…');
  String get aiNoBoundDevice => _pick(
    '暂无已绑定电子纸设备，请先绑定电子纸设备',
    'No e-paper device bound yet. Please bind one first.',
    'バインド済みの電子ペーパーがありません。先に追加してください',
  );
  String get aiBindDeviceFirst => _pick(
    '使用 AI 创作前请先绑定电子纸设备',
    'Please bind an e-paper device before using AI.',
    'AIを使う前に電子ペーパーを追加してください',
  );
  String get aiGoBind => _pick('去绑定', 'Bind now', '追加する');
  String get aiBack => _pick('返回', 'Back', '戻る');
  String get aiNeedTextWithImages => _pick(
    '请输入文字后再发送（图片不能单独发送）',
    'Add a message — images cannot be sent alone.',
    'テキストを入力してください（画像だけでは送信できません）',
  );
  String get aiImageUploading =>
      _pick('图片上传中，请稍候…', 'Uploading images…', '画像をアップロード中…');

  /// 流式回复收完了，却一句话一张图都没有（服务端只推了进度就结束）。
  /// 留个空气泡纯属让人以为坏了，所以整条撤掉并提示一句。
  String get aiEmptyReply => _pick(
    '本次没有生成内容，请重试',
    'Nothing was generated this time. Please try again.',
    '今回は生成されませんでした。もう一度お試しください',
  );
  /// 上限 2026-08-12 由 4 张放宽到 5 张（与 `_kMaxImages` 必须一致），
  /// 文案也换成产品给的那句（不再是「一次最多选择 N 张图片」）。
  String get aiMaxImages => _pick(
    '当前AI只允许上传5张图',
    'You can upload up to 5 images to the AI.',
    'AIにアップロードできる画像は最大5枚です',
  );

  /// 货币单位。2026-08-12 起对外一律叫「星币」（后端字段名仍是 `availableToken`，不动）。
  String get aiTokenUnit => _pick('星币', 'Stars', 'スターコイン');
  String get aiTokenEmptyTitle => _pick('星币不足', 'Out of stars', 'スターコイン不足');

  /// 星币不足且**问得到**「至少需要多少」时的正文（数字来自后端 chkAiDialogue 的 retMsg）。
  String aiTokenShortMessage(String amount) => _pick(
    '发起一次 AI 对话至少需要 $amount 星币，当前余额不足。购买后即可继续和星宝聊天。',
    'Each AI chat needs at least $amount stars, and your balance is short. Top up to keep chatting.',
    'AI との会話には少なくとも $amount スターコインが必要です。チャージ後に続けられます。',
  );

  /// 抠不到数字（后端换了文案 / 403 是别的原因）时的兜底正文。
  /// 🔶 与小程序的差异：小程序这句带「去购买」引导，APP 侧还没有购买页（IAP 未接），
  /// 所以只说明情况、不指路。
  String get aiTokenEmptyMessage => _pick(
    '当前星币余额不足，无法发起 AI 对话。',
    'Your star balance is too low to start an AI chat.',
    'スターコイン残高が不足しているため、AI との会話を開始できません。',
  );
  String get aiBannedBanner => _pick(
    '账号已被限制，暂时无法使用 AI 对话',
    'Your account is restricted; AI chat is unavailable.',
    'アカウントが制限されています。AIチャットは利用できません',
  );
  String get aiBannedHint => _pick('账号已被限制', 'Account restricted', 'アカウント制限中');
  String get aiKeep7Days => _pick(
    '仅保留最近 7 天的会话',
    'Only the last 7 days of chats are kept.',
    '直近7日間のチャットのみ保持されます',
  );
  String get aiNoSessions =>
      _pick('暂时没有历史会话', 'No chats yet', '履歴はまだありません');
  String get aiNoSessionsDesc => _pick(
    '开始一次新的历史创作吧',
    'Start a new conversation.',
    '新しい会話を始めましょう',
  );
  String get aiPullToLoadMore =>
      _pick('上拉加载更多', 'Pull up to load more', '上にスワイプして続きを読み込む');

  /// 会话列表的日期分组标题：今天单列，其余按「几月几日」。
  String get aiToday => _pick('今天', 'Today', '今日');
  String aiMonthDay(int month, int day) =>
      _pick('$month月$day日', '$month/$day', '$month月$day日');
  // ⚠️ 2026-07-25 起本模块**没有也不要再加**任何「清空」入口（对齐小程序）：接口无批量删除能力，
  //    只能逐条串行 DELETE，中途失败会留下「删一半且无法回滚」的状态。原
  //    aiClearAll/aiClear/aiClearing/aiCleared/aiClearAllTitle/aiClearAllMessage 六条文案随功能删除。
  //    清理一律长按逐条删，列表底部有 [aiLongPressToDelete] 提示。
  String get aiLongPressToDelete =>
      _pick('长按会话可删除', 'Long-press a chat to delete it.', '長押しでチャットを削除できます');

  /// 20013 会话数达上限时把用户送去会话列表清理（对齐小程序「去清理」）。
  String get aiGoCleanSessions => _pick('去清理', 'Manage chats', '整理する');

  /// 已经停在「新对话」空态时再点＋的提示（不清输入草稿，只提示）。
  String get aiAlreadyNewChat =>
      _pick('已经在新对话中', 'You are already in a new chat.', 'すでに新しいチャットです');
  String get aiDeleteSessionTitle =>
      _pick('删除该会话', 'Delete this chat', 'このチャットを削除');
  String get aiDeleteSessionMessage => _pick(
    '删除后该会话的聊天记录不可恢复，确定删除？',
    'The messages in this chat cannot be recovered. Delete it?',
    'このチャットの履歴は復元できません。削除しますか？',
  );
  String aiMsgCount(int count) =>
      _pick('$count 条消息', '$count messages', '$count 件');

  /// 一键生图风格标签：key = cartoon / landscape / portrait / anime（需求文案：漫画/风景/肖像/动漫）。
  String aiStyleLabel(String key) {
    switch (key) {
      case 'landscape':
        return _pick('风景', 'Scenery', '風景');
      case 'portrait':
        return _pick('肖像', 'Portrait', '人物');
      case 'anime':
        return _pick('动漫', 'Anime', 'アニメ');
      case 'cartoon':
      default:
        return _pick('漫画', 'Cartoon', '漫画');
    }
  }

  /// 生图比例标签：key = vertical / horizontal / square（API `img_orientation` 值）。
  String aiOrientationLabel(String key) {
    switch (key) {
      case 'horizontal':
        return _pick('横向', 'Landscape', '横');
      case 'square':
        return _pick('方形', 'Square', '正方形');
      case 'vertical':
      default:
        return _pick('竖向', 'Portrait', '縦');
    }
  }

  // ── 投屏结果/预览 ──
  String get cresMethodTitle =>
      _pick('选择投屏方式', 'Select Casting Method', 'キャスト方法を選択');
  String get cresMethodCamera => _pick('拍照', 'Take Photo', '撮影');
  String get cresMethodAlbum => _pick('相册', 'Album', 'アルバム');
  String get cresMethodCameraDesc =>
      _pick('调用手机相机拍照', 'Take a photo with your camera', 'スマホのカメラで撮影');
  String get cresMethodAlbumDesc =>
      _pick('从手机相册选择照片', 'Choose a photo from your album', 'アルバムから写真を選択');
  String get cresFailedTitle => _pick('投屏失败', 'Casting Failed', 'キャスト失敗');
  String get cresFailedDesc => _pick(
    '电子纸设备连接中断，请检查电子纸设备状态后重试',
    'The e-paper device connection was lost. Check the e-paper device and try again.',
    '電子ペーパーとの接続が切れました。状態を確認して再試行してください。',
  );
  String get cresRecast => _pick('重新投屏', 'Cast Again', '再キャスト');
  String get cresBackHome => _pick('返回首页', 'Back to Home', 'ホームに戻る');
  String get cresSuccessTitle => _pick('投屏成功', 'Casting Succeeded', 'キャスト成功');
  String get cresSuccessDesc => _pick(
    '照片已成功投屏到电子纸设备，可前往相册查看',
    'The photo was cast to the e-paper device. You can view it in the album.',
    '写真を電子ペーパーにキャストしました。アルバムで確認できます。',
  );
  String get cresContinueCast => _pick('继续投屏', 'Continue Casting', 'キャストを続ける');
  String get cresDeviceLabel => _pick('投屏设备', 'Casting Device', 'キャスト先デバイス');
  String get cresManageLabel => _pick('投屏管理', 'Casting Management', 'キャスト管理');
  String get cresDetailLabel => _pick('投屏明细', 'Casting Details', 'キャスト明細');
  String get cresPreviewTitle => _pick('照片预览', 'Photo Preview', '写真プレビュー');
  String get cresSave => _pick('保存', 'Save', '保存');
  String get cresStartCast => _pick('开始投屏', 'Start Casting', 'キャスト開始');
  String get cresCompressLabel => _pick(
    '压缩图片（关闭后传原图，耗时更久）',
    'Compress image (off = send original, slower)',
    '画像を圧縮（オフで原本を送信、時間がかかります）',
  );
  String get cresCrop => _pick('裁剪', 'Crop', 'トリミング');
  String get cresRotate => _pick('旋转', 'Rotate', '回転');
  String get cresOriginal => _pick('原图', 'Original', '原本');
  String get cresImagePlaceholder =>
      _pick('图片占位', 'Image Placeholder', '画像プレースホルダー');

  // ── 绑定设备 ──
  String get bindDeviceTitle => _pick('绑定设备', 'Bind Device', 'デバイスの追加');
  String bindFoundCount(int count) =>
      _pick('已找到 $count 台', '$count found', '$count 台見つかりました');
  String get bindEndSearchInline => _pick('，结束搜索', ', End Search', '、検索を終了');
  String get bindBindNow => _pick('立即绑定', 'Bind Now', '今すぐ追加');
  String get bindNotFoundTitle =>
      _pick(
        '未发现电子纸设备',
        'No E-paper Device Found',
        '電子ペーパーが見つかりません',
      );
  String get bindNotFoundHint => _pick(
    '电子纸设备连接中断，请检查电子纸设备状态后重试',
    'Connection interrupted. Please check the e-paper device and try again.',
    '電子ペーパーの接続が切断されました。電子ペーパーの状態を確認して再試行してください。',
  );
  String get bindRescan => _pick('重新扫描', 'Rescan', '再スキャン');
  String get bindScanHelpLink =>
      _pick('扫描不到怎么办？', "Can't find your device?", 'スキャンできない場合は？');
  String get bindSearchingTitle =>
      _pick(
        '正在搜索附近电子纸设备',
        'Searching for nearby e-paper devices',
        '近くの電子ペーパーを検索中',
      );
  String get bindSearchingHint => _pick(
    '请尽量将手机靠近需要添加的电子纸设备...',
    'Please keep your phone close to the e-paper device you want to add...',
    '追加したい電子ペーパーにできるだけスマートフォンを近づけてください...',
  );
  String get bindCancelScan => _pick('取消扫描', 'Cancel Scan', 'スキャンを中止');
  String get bindPleaseCheck => _pick('请检查：', 'Please check:', '確認してください：');
  String get bindCheckList => _pick(
    '1.电子纸设备是否有电?\n'
        '2.当前电子纸设备是否被占用?\n'
        '3.电子纸设备蓝牙是否工作正常，手机蓝牙是否打开\n'
        '4.电子纸设备是否与手机距离过远，隔离或有其他遮挡物',
    '1. Is the e-paper device powered on?\n'
        '2. Is the e-paper device already in use?\n'
        "3. Is the e-paper device's Bluetooth working and your phone's Bluetooth on?\n"
        '4. Is the e-paper device too far away or blocked by obstacles?',
    '1. 電子ペーパーの電源は入っていますか？\n'
        '2. 電子ペーパーが他で使用されていませんか？\n'
        '3. 電子ペーパーのBluetoothは正常に動作し、スマートフォンのBluetoothはオンですか？\n'
        '4. 電子ペーパーが遠すぎたり、遮蔽物がありませんか？',
  );
  String get bindBtPermissionTitle =>
      _pick('需要蓝牙权限', 'Bluetooth Permission Required', 'Bluetoothの権限が必要です');
  String get bindBtPermissionMessage => _pick(
    '搜索附近相框需要「蓝牙」与「附近设备」权限。请在系统设置中开启后，点「重新扫描」重试。',
    'Searching for nearby frames requires "Bluetooth" and "Nearby devices" permissions. Please enable them in Settings, then tap "Rescan" to try again.',
    '近くのフォトフレームを検索するには「Bluetooth」と「付近のデバイス」の権限が必要です。設定で有効にしてから「再スキャン」をタップして再試行してください。',
  );
  String get bindGoSettings => _pick('去设置', 'Open Settings', '設定を開く');
  String get bindBtOffTitle => _pick(
    '请先打开手机蓝牙开关',
    'Please Turn On Bluetooth',
    'スマートフォンのBluetoothをオンにしてください',
  );
  String get bindBtOffMessage => _pick(
    '手机蓝牙未开启，无法搜索附近相框。打开蓝牙后，点「重新扫描」重试。',
    'Bluetooth is off, so nearby frames cannot be found. Turn on Bluetooth, then tap "Rescan" to try again.',
    'Bluetoothがオフのため、近くのフォトフレームを検索できません。Bluetoothをオンにしてから「再スキャン」をタップして再試行してください。',
  );
  String get bindGoOpenBt =>
      _pick('去打开蓝牙', 'Turn On Bluetooth', 'Bluetoothをオンにする');
  // ── 崩溃报告弹窗（上次异常退出的日志展示，见 bolt_star_app.dart）──
  String get crashReportTitle =>
      _pick('检测到上次异常退出', 'Previous Crash Detected', '前回の異常終了を検出しました');
  String get crashReportHint => _pick(
    '以下是崩溃日志，请「复制日志」后发给开发者定位问题。',
    'Below is the crash log. Please tap "Copy Log" and send it to the developer.',
    '以下はクラッシュログです。「ログをコピー」して開発者へお送りください。',
  );
  String get crashReportCopy => _pick('复制日志', 'Copy Log', 'ログをコピー');
  String get crashReportCopied => _pick('日志已复制', 'Log copied', 'ログをコピーしました');
  String get crashReportClose => _pick('清除并关闭', 'Clear & Close', '消去して閉じる');
  // ── 运行时权限引导（进相册 / 连接设备前的前置授权，见 PermissionGate）──
  String get permPhotoTitle =>
      _pick('需要相册权限', 'Photos Permission Required', '写真へのアクセス権限が必要です');
  String get permPhotoMessage => _pick(
    '访问相册需要「照片/媒体」权限。请允许后重试，或点「去设置」在系统设置中开启。',
    'Accessing the album requires the photos/media permission. Please allow it and retry, or tap "Open Settings" to enable it in system settings.',
    'アルバムへのアクセスには写真/メディアの権限が必要です。許可してから再試行するか、「設定を開く」からシステム設定で有効にしてください。',
  );
  String get permBleConnectMessage => _pick(
    '连接相框需要「蓝牙」与「附近设备」权限（部分系统显示为「位置信息」）。请允许后重试，或点「去设置」在系统设置中开启。',
    'Connecting to the frame requires the "Bluetooth" and "Nearby devices" permissions (shown as "Location" on some systems). Please allow them and retry, or tap "Open Settings" to enable them in system settings.',
    'フォトフレームへの接続には「Bluetooth」と「付近のデバイス」の権限（一部のシステムでは「位置情報」）が必要です。許可してから再試行するか、「設定を開く」からシステム設定で有効にしてください。',
  );
  String get permBtOffConnectMessage => _pick(
    '手机蓝牙未开启，无法连接相框。请打开蓝牙后重试。',
    'Bluetooth is off, so the frame cannot be connected. Please turn on Bluetooth and try again.',
    'Bluetoothがオフのため、フォトフレームに接続できません。Bluetoothをオンにしてから再試行してください。',
  );
  String get bindConnecting =>
      _pick('连接设备中', 'Connecting to device', 'デバイスに接続中');
  String get bindConnectSuccess => _pick('连接成功', 'Connected', '接続しました');
  String get bindAlreadyBoundConnected => _pick(
    '该电子纸设备已绑定，已为您连接',
    'This e-paper device is already bound. Connected for you.',
    'この電子ペーパーは既に追加済みです。接続しました。',
  );
  String get bindSuccess => _pick('绑定成功', 'Bound successfully', '追加しました');
  // 注意：这三条 toast **不要**把原始异常对象插值进用户文案——
  // MissingPluginException 之类的整段英文技术文本会出现在 2~3 秒的 toast 里，
  // 用户读不完也看不懂。异常详情由调用方 debugPrint 进日志。
  // ── BLE 层用户可见文案（BleController 经 languageResolver 取用）────────
  String get bleUnavailable => _pick(
    '蓝牙不可用：请开启蓝牙并授予“附近的设备”权限',
    'Bluetooth unavailable: turn on Bluetooth and grant the "Nearby devices" permission.',
    'Bluetoothを利用できません：Bluetoothをオンにし、「付近のデバイス」権限を許可してください。',
  );
  String get bleDeviceNotFound => _pick(
    '未搜索到该电子纸设备，请确认电子纸设备已开机并在附近',
    'E-paper device not found. Make sure it is powered on and nearby.',
    '電子ペーパーが見つかりません。電源が入っていて近くにあることを確認してください。',
  );
  String get bleIncompleteDeviceIdentity => _pick(
    '未读取到完整的6字节电子纸设备ID，请重新连接后再试',
    'The complete 6-byte e-paper device ID was not read. Reconnect and try again.',
    '完全な6バイトの電子ペーパーIDを取得できませんでした。再接続してお試しください。',
  );
  // 连接重入护栏：并发触发连接时第二路的提示（见 BleController.connect）。
  String get bleBusyConnecting => _pick(
    '正在连接电子纸设备，请稍候',
    'Connecting to the e-paper device, please wait.',
    '電子ペーパーに接続中です。しばらくお待ちください。',
  );
  // 物理连接失败的用户可见文案（含安卓 android-code:133 等）：只给可操作建议，不暴露原始异常。
  String get bleConnectFailed => _pick(
    '连接失败，请靠近电子纸设备后重试',
    'Connection failed. Move closer to the e-paper device and try again.',
    '接続に失敗しました。電子ペーパーに近づいてもう一度お試しください。',
  );
  // 连接/搜索超时（2026-08-01）：与上面的「连接失败」分开——超时多为设备没在广播或信号弱，
  // 用户该做的是等一会儿再试，而不是「靠近设备」。这一句必须跟随语种：此前底层抛的
  // TimeoutException 会把英文原文透到 toast，中文用户看到一串 "TimeoutException after…"。
  String get bleConnectTimeout => _pick(
    '连接超时，稍后再试',
    'Connection timed out. Please try again later.',
    '接続がタイムアウトしました。しばらくしてからお試しください。',
  );
  // 连接保活前台服务的常驻通知文案（Android 通知栏，连接期间可见）。
  String get bleKeepAliveNotification => _pick(
    '正在保持相框连接',
    'Keeping the photo frame connected',
    'フォトフレームとの接続を維持しています',
  );

  // 蓝牙信号原始五档文案；搜索列表会按产品口径保守下调一级（见 rssiToSignalLevel）。
  String get signalVeryStrong => _pick('极强', 'Excellent', '非常に強い');
  String get signalStrong => _pick('强', 'Strong', '強い');
  String get signalNormal => _pick('正常', 'Fair', '普通');
  String get signalWeak => _pick('偏弱', 'Weak', 'やや弱い');
  String get signalVeryWeak => _pick('弱', 'Very weak', '弱い');

  String get bindBtUnsupported => _pick(
    '当前手机暂不支持蓝牙或未授权，请检查系统蓝牙权限',
    'This phone does not support Bluetooth or is not authorized. Check system Bluetooth permissions.',
    'この端末はBluetoothに対応していないか、許可されていません。システムのBluetooth権限を確認してください。',
  );
  String get bindScanFailed => _pick(
    '扫描失败，请稍后重试',
    'Scan failed. Please try again.',
    'スキャンに失敗しました。再試行してください。',
  );
  String bindConnectFailed(Object error) => _pick(
    '电子纸设备连接失败：$error',
    'E-paper device connection failed: $error',
    '電子ペーパーの接続に失敗しました：$error',
  );
  String bindBatteryLabel(int battery) =>
      _pick('电量$battery%', 'Battery $battery%', 'バッテリー$battery%');
  String bindSignalLabel(String signal) =>
      _pick('信号 $signal', 'Signal $signal', '信号 $signal');
  String get carouselTitle => _pick('轮播设置', 'Slideshow Settings', 'スライドショー設定');
  String get carouselEnable =>
      _pick('开启轮播', 'Enable Slideshow', 'スライドショーを有効にする');
  String get carouselTip => _pick(
    '轮播以开启时间起算24小时后轮播下一张',
    'The slideshow advances to the next photo 24 hours after it is turned on.',
    'スライドショーを有効にしてから24時間後に次の写真へ切り替わります。',
  );
  String get carouselMode => _pick('轮播方式', 'Slideshow Mode', 'スライドショー方式');
  String get carouselSequence => _pick('顺序轮播', 'Sequential', '順番に再生');
  String get carouselRandom => _pick('随机轮播', 'Random', 'ランダム再生');
  String get devicesConnecting => _pick('连接设备中…', 'Connecting…', '接続中…');
  String get devicesReadPhotoFailed => _pick(
    '无法读取照片，请检查相机/相册权限后重试。',
    'Unable to read the photo. Please check camera/album permissions and try again.',
    '写真を読み込めません。カメラ／アルバムの権限を確認して再試行してください。',
  );

  // ── 设备详情/列表 ──
  String get devDetailTitle => _pick('设备详情', 'Device Details', 'デバイス詳細');
  String get devMyDevicesTitle => _pick('我的设备', 'My Devices', 'マイデバイス');
  String get devRenameTitle => _pick('重命名设备', 'Rename Device', 'デバイス名を変更');
  String get devDeviceNameTitle => _pick('设备名称', 'Device Name', 'デバイス名');
  String get devNameHint =>
      _pick('请输入设备名称', 'Enter a device name', 'デバイス名を入力してください');

  /// 设备名称弹窗副标题（小程序 `.name-dialog__tip`）。
  String get devNameDialogTip => _pick(
    '为电子纸设备设置一个容易识别的名称',
    'Give this e-paper device a name you can recognise',
    'すぐ分かる名前を電子ペーパーに付けてください',
  );

  /// 绑定成功后的命名引导标题：弱性强制，可以点「稍后」跳过。
  String get devBindNameTitle => _pick('设备命名', 'Name Your Device', 'デバイスに名前を付ける');

  /// 命名引导的取消按钮：2026-08-02 产品把「暂不修改」改成更短的「稍后」（对齐小程序 bind.wxml）。
  String get devBindNameLater => _pick('稍后', 'Later', '後で');
  String devNameTooLong(int max) => _pick(
    '设备名称最多$max个字符',
    'Device name must be at most $max characters.',
    'デバイス名は$max文字以内です。',
  );
  String get devConfirm => _pick('确认', 'Confirm', '確認');
  String get devConnecting =>
      _pick('连接设备中', 'Connecting to device…', 'デバイスに接続中…');
  String get devConnectFirst =>
      _pick(
        '请先连接电子纸设备',
        'Please connect the e-paper device first',
        '先に電子ペーパーを接続してください',
      );
  String get devDisconnecting => _pick('断开中', 'Disconnecting…', '切断中…');
  String get devPhotoReadFailed => _pick(
    '无法读取照片，请检查相机/相册权限后重试。',
    'Unable to read photos. Please check camera/album permissions and try again.',
    '写真を読み込めません。カメラ／アルバムの権限を確認して再試行してください。',
  );
  String get devConnected => _pick('已连接', 'Connected', '接続済み');
  String get devDisconnected => _pick('未连接', 'Not Connected', '未接続');
  String get devCast => _pick('投屏', 'Cast', 'キャスト');
  String get devDisconnect => _pick('断开连接', 'Disconnect', '接続を切断');
  String get devConnectBluetooth =>
      _pick('连接蓝牙', 'Connect Bluetooth', 'Bluetoothに接続');
  String get devDisconnectShort => _pick('断开', 'Disconnect', '切断');
  String get devConnectShort => _pick('连接', 'Connect', '接続');
  String get devCarouselSetting =>
      _pick('轮播设置', 'Slideshow Settings', 'スライドショー設定');
  String get devCarouselDisabled => _pick('未启用', 'Off', '無効');

  /// 详情页「轮播设置」右侧值：开着一律「已开启」，不再显示顺序/随机
  /// （2026-08-21 同步小程序 `getPlaybackLabel`：这一行只回答「开没开」，
  /// 具体是顺序还是随机进设置页看）。
  String get devCarouselEnabled => _pick('已开启', 'On', '有効');
  String get devCarouselRandom => _pick('随机轮播', 'Shuffle', 'ランダム再生');
  String get devCarouselSequential => _pick('顺序轮播', 'In Order', '順番再生');
  String get devDeviceId => _pick('设备ID', 'Device ID', 'デバイスID');

  /// 屏幕物理尺寸（像素，如 680*960），详情页紧跟「设备ID」。
  /// 2026-07-31 文案由「分辨率」改为「屏幕尺寸」（对齐小程序 detail.wxml）。
  String get devScreenSize => _pick('屏幕尺寸', 'Screen Size', '画面サイズ');

  /// 设备可存放的照片数量，文案由「设备内存」改为「最大照片数量」。
  /// 2026-08-01 曾改为「最大照片数量-已使用」+ 值 `上限-已用`；2026-08-02 产品定稿：
  /// 行名回到「最大照片数量」，已用与上限全部挪进右侧值里，写成分数式 `已用/上限`（如 8/51）。
  /// 行文案与取值口径必须成对，改一个要改另一个（值见 device_details_page.dart）。
  String get devMaxPhotoCount =>
      _pick('最大照片数量', 'Max Photos', '最大写真枚数', '最大照片數量');
  String get devOtaUpgrade => _pick('OTA升级', 'Firmware Update', 'OTAアップデート');
  String devFirmwareNewVersion(String version) => _pick(
    '发现新版本 $version',
    'New version $version available',
    '新しいバージョン $version',
  );

  // 2026-08-20 删除：`devFirmwareUpdateAvailable`「有版本可更新」/ `devFirmwareUpToDate`「已是最新版本」。
  // 「固件升级」行右侧改回只显示**设备当前在跑的版本号**（读不到给 `--`），有没有新版本改由箭头旁的
  // 红点表达，这两句结论文案在详情页已无处可用（点进 OTA 页后的结论文案是另一套 `ota*`）。
  // 与小程序同步删除 `detail.js` 的 `OTA_TEXT_UPDATE` / `OTA_TEXT_LATEST`。
  String get devClearAll => _pick('一键清空', 'Clear All', '一括消去');
  String get devClearing => _pick('清空中…', 'Clearing…', '消去中…');
  String get devCleared => _pick('已清空', 'Cleared', '消去しました');
  String get devClearAllValue => _pick(
    '清空电子纸设备及小程序/APP内的照片',
    'Erase the photos on the e-paper device and in the Mini Program / App',
    '電子ペーパーとミニプログラム／アプリ内の写真を消去',
  );

  /// 一键清空第一步的取消键（对齐小程序「再想想」）。
  String get devThinkAgain => _pick('再想想', 'Not now', 'もう一度考える');

  // 「解除绑定」与「删除设备」是两件事，文案与后果都不同，不要合并：
  //   · 解除绑定 = 只解除账号关系，设备上的照片保留；
  //   · 删除设备 = 一键清空 + 断开连接 + 解除绑定（需已连接）。
  String get devUnbindDevice => _pick('解除绑定', 'Unbind Device', 'ペアリング解除');
  String get devUnbindDeviceValue => _pick(
    '解除绑定电子纸设备，保留照片',
    'Unbind the e-paper device and keep its photos',
    '電子ペーパーのペアリングを解除し、写真は保持',
  );
  String get devUnbindDeviceMessage => _pick(
    '解除绑定后，电子纸设备上的照片将保留，您可以稍后重新绑定电子纸设备。',
    'After unbinding, photos on the e-paper device are kept and you can pair it again later.',
    'ペアリングを解除しても、電子ペーパー内の写真は残り、後で再度ペアリングできます。',
  );
  String get devUnbinding => _pick('解除绑定中', 'Unbinding…', 'ペアリング解除中…');
  String get devDeleteDevice => _pick('删除设备', 'Delete Device', 'デバイスを削除');
  String get devDeleting => _pick('删除设备中', 'Deleting device…', 'デバイスを削除中…');
  String get devDeviceDeleted => _pick(
    '电子纸设备已删除',
    'E-paper device deleted',
    '電子ペーパーを削除しました',
  );
  String get devDeleteDeviceValue => _pick(
    '清空照片并解除绑定',
    'Erase photos and unbind',
    '写真を消去してペアリング解除',
  );

  /// 删除设备第二次确认的标题与说明（对齐小程序 detail.wxml）。
  String get devDeleteDeviceConfirmTitle =>
      _pick('确认删除设备', 'Confirm Device Deletion', 'デバイス削除の確認');
  String get devDeleteDeviceConfirmMessage => _pick(
    '我已知晓删除电子纸设备相关内容，确认删除',
    'I understand what deleting this e-paper device means and confirm the deletion.',
    '電子ペーパー削除の内容を理解した上で、削除を確認します。',
  );
  String get devEmptyTitle => _pick('暂无设备', 'No Devices', 'デバイスがありません');
  String get devEmptySubtitle => _pick(
    '请先搜索并绑定附近的电子纸设备。',
    'Search for and pair a nearby e-paper device first.',
    'まず近くの電子ペーパーを検索してペアリングしてください。',
  );
  String get devAddDevice => _pick('添加设备', 'Add Device', 'デバイスを追加');
  String get devClearStep1Message => _pick(
    '将清空电子纸设备内所有照片，同时清空小程序/APP的图库，请谨慎选择是否继续。',
    'This will erase all photos on the e-paper device and also clear the gallery in the Mini Program / App. Please continue with care.',
    '電子ペーパー内のすべての写真と、ミニプログラム／アプリのギャラリーを消去します。続行するかどうか慎重にご判断ください。',
  );
  String get devClearStep2Message => _pick(
    '我已阅读并了解此操作的结果，确认清空电子纸设备与图库内的全部照片。',
    'I have read and understood the consequences and confirm erasing all photos on the e-paper device and in the gallery.',
    'この操作の結果を理解した上で、電子ペーパーとギャラリー内のすべての写真を消去することを確認します。',
  );
  /// 删除设备第一次确认：先劝一句「建议清空照片防隐私泄露」（对齐小程序 detail.wxml）。
  String get devDeleteDeviceMessage => _pick(
    '删除设备将执行一键清空电子纸设备及小程序/APP内的照片，防止隐私泄露。是否确认删除设备？',
    'Deleting the device also clears every photo on the e-paper device and in the Mini Program / App to protect your privacy. Delete this device?',
    'デバイスを削除すると、プライバシー保護のため電子ペーパーとミニプログラム／アプリ内の写真を一括消去します。削除しますか？',
  );

  // ── OTA 升级 ──
  String get otaTitle => _pick('OTA升级', 'OTA Update', 'OTAアップデート');
  String get otaFirmwareUpgrade =>
      _pick('固件升级', 'Firmware Update', 'ファームウェア更新');
  String get otaAlreadyLatestContent => _pick(
    '当前固件已是最新版本',
    'Your firmware is already up to date.',
    'ファームウェアはすでに最新です。',
  );
  String get otaKnow => _pick('知道了', 'Got it', '了解');
  String get otaLater => _pick('稍后', 'Later', '後で');
  String get otaUpdateNow => _pick('立刻更新', 'Update Now', '今すぐ更新');
  String get otaConnecting =>
      _pick('连接设备中', 'Connecting to device…', 'デバイスに接続中…');
  String get otaCheckingVersion =>
      _pick('检测版本中', 'Checking version…', 'バージョンを確認中…');
  String get otaDeviceNotFound =>
      _pick('设备不存在', 'Device not found', 'デバイスが見つかりません');
  String get otaMissingDeviceInfo => _pick(
    '缺少电子纸设备信息，无法检查固件版本。',
    'E-paper device info is missing; cannot check the firmware version.',
    '電子ペーパーの情報がなく、ファームウェアバージョンを確認できません。',
  );
  String get otaInvalidMissingInfo => _pick(
    '检测到可更新状态，但缺少新版本号或固件下载地址，请稍后重试。',
    'An update is available, but the new version number or firmware download URL is missing. Please try again later.',
    '更新可能ですが、新しいバージョン番号またはファームウェアのダウンロードURLがありません。後でもう一度お試しください。',
  );
  String get otaInvalidBinUrl => _pick(
    '固件下载地址不是有效的 .bin 文件，请稍后重试。',
    'The firmware download URL is not a valid .bin file. Please try again later.',
    'ファームウェアのダウンロードURLが有効な .bin ファイルではありません。後でもう一度お試しください。',
  );
  String get otaDefaultDeviceName =>
      _pick('智能相框', 'Smart Frame', 'スマートフォトフレーム');
  String get otaConfirmAfterDownload =>
      _pick('下载后确认', 'Confirm after download', 'ダウンロード後に確認');
  String get otaCannotUpgrade =>
      _pick('无法升级', 'Cannot upgrade', 'アップグレードできません');
  String get otaNewVersionFound =>
      _pick('发现新版本', 'New version available', '新しいバージョンあり');
  String get otaDeviceNotConnected =>
      _pick('设备未连接', 'Device not connected', 'デバイス未接続');
  /// 未连接时的主按钮文案：点它会先自动扫连再升级（不再是「按钮画着却点不动」）。
  String get otaConnectAndUpgrade =>
      _pick('连接并升级', 'Connect & upgrade', '接続してアップグレード');
  String get otaConnectFailedRetry => _pick(
    '未能连接电子纸设备，请确认设备已开机并靠近手机后重试。',
    'Could not connect to the e-paper device. Make sure it is powered on and nearby, then try again.',
    '電子ペーパーに接続できませんでした。電源が入っていて近くにあることを確認して、もう一度お試しください。',
  );
  String get otaConnectFirstHint => _pick(
    '请先在详情页连接电子纸设备，并在升级过程中保持电子纸设备在线。',
    'Please connect the e-paper device on the details page first, and keep it online during the upgrade.',
    '先に詳細ページで電子ペーパーを接続し、アップグレード中はオンラインを保ってください。',
  );
  String get otaUpToDate => _pick('已是最新', 'Up to date', '最新です');
  String get otaNoBleConnection => _pick(
    '未获取到电子纸设备蓝牙连接，请先在详情页连接电子纸设备后再升级。',
    'No Bluetooth connection to the e-paper device. Please connect it on the details page before upgrading.',
    '電子ペーパーのBluetooth接続がありません。詳細ページで接続してからアップグレードしてください。',
  );
  String get otaUpgrading => _pick('升级中', 'Upgrading…', 'アップグレード中…');
  String get otaPreparingUpgrade =>
      _pick('准备升级', 'Preparing upgrade…', 'アップグレードを準備中…');
  String get otaUnconfirmedRetry =>
      _pick('未确认(请重试)', 'Unconfirmed (retry)', '未確認（再試行）');
  String get otaUpgradeComplete =>
      _pick('升级完成', 'Upgrade complete', 'アップグレード完了');

  /// 升级成功后的收尾提示：设备在校验通过约 2s 后就复位运行新固件，链路当场作废。
  /// 不说这一句，用户立刻回去点投屏、连不上，会以为是升级把设备刷坏了。
  String get otaDeviceRebootingHint => _pick(
    '电子纸设备正在重启，请稍等几秒后重新连接',
    'The e-paper device is restarting. Please reconnect in a few seconds.',
    '電子ペーパーを再起動しています。数秒後に再接続してください。',
  );
  String get otaUpgradeFailed => _pick('升级失败', 'Upgrade failed', 'アップグレード失敗');
  String get otaInterrupted => _pick(
    '升级已中断：升级过程中手机切到后台或页面离开。请保持屏幕常亮后重试。',
    'The upgrade was interrupted: the phone went to the background or left the page during the upgrade. Please keep the screen on and try again.',
    'アップグレードが中断されました：アップグレード中にスマホがバックグラウンドに移行するかページを離れました。画面を常時点灯にして再試行してください。',
  );
  String get otaUpgradeNowAction => _pick('立即升级', 'Upgrade Now', '今すぐアップグレード');

  // ── OTA 升级中退出确认（PopScope 拦截）──────────────────────────────
  String get otaExitConfirmTitle =>
      _pick('固件升级中', 'Upgrade in Progress', 'アップグレード中');
  String get otaExitConfirmContent => _pick(
    '现在退出将中断固件传输，升级会失败并需要重新开始。确定要退出吗？',
    'Leaving now will interrupt the firmware transfer; the upgrade will fail and must be restarted. Leave anyway?',
    '今終了するとファームウェア転送が中断され、アップグレードは失敗し、最初からやり直しになります。終了しますか？',
  );
  String get otaExitConfirmStay =>
      _pick('继续升级', 'Keep Upgrading', 'アップグレードを続ける');
  String get otaExitConfirmLeave => _pick('退出', 'Leave', '終了する');

  String get otaRecheck => _pick('重新检查', 'Check Again', '再確認');
  String get otaDone => _pick('已完成', 'Done', '完了');
  String get otaChecking => _pick('检查中', 'Checking…', '確認中…');
  String get otaMissingDeviceId => _pick(
    '缺少电子纸设备ID，无法检查固件版本。',
    'Missing e-paper device ID; cannot check the firmware version.',
    '電子ペーパーIDがないため、ファームウェアバージョンを確認できません。',
  );
  String get otaGenericFailure => _pick(
    '升级失败，请重试',
    'Upgrade failed. Please try again.',
    'アップグレードに失敗しました。再試行してください。',
  );
  String get otaCheckingFirmware =>
      _pick('正在检查固件版本...', 'Checking firmware version…', 'ファームウェアバージョンを確認中…');
  String get otaKeepPoweredHint => _pick(
    '升级过程中请保持电子纸设备供电、手机屏幕常亮，并避免切换到后台。',
    'During the upgrade, keep the e-paper device powered, keep your phone screen on, and avoid switching to the background.',
    'アップグレード中は電子ペーパーの電源を入れたまま、スマホの画面を常時点灯にし、バックグラウンドへの切り替えを避けてください。',
  );

  // 升级中那一屏进度条下方的两条规则（2026-08-13 两端同改）。**只在进行中出现**：
  // 挂在「已是最新版本」下面写「意外中断可能导致设备无法使用」是没有意义的，只会跟结论文案抢注意力。
  // ⚠️ 简中按需求原文逐字，包括 `小程序\app` 里的反斜杠（Dart 里写成 `\\`）。
  String get otaRuleWaitPatiently => _pick(
    '1）升级过程请耐心等待升级结果，意外中断可能导致电子纸设备无法使用',
    '1) Please wait for the upgrade to finish. Interrupting it may leave the e-paper device unusable.',
    '1）アップグレードが完了するまでお待ちください。中断すると電子ペーパーが使用できなくなる可能性があります。',
  );
  String get otaRuleRecoverHint => _pick(
    '2）若升级失败造成设备无法连接，请尝试重新进入小程序\\app或断电重启设备',
    '2) If a failed upgrade leaves the device unreachable, reopen the mini program / app or power-cycle the device.',
    '2）アップグレード失敗で接続できなくなった場合は、ミニプログラム／アプリを開き直すか、デバイスの電源を入れ直してください。',
  );
  String get otaReadyToUpgrade =>
      _pick('可开始升级', 'Ready to upgrade', 'アップグレード可能');
  String get otaNoUpgradeNeeded =>
      _pick('无需升级', 'No upgrade needed', 'アップグレード不要');
  String get otaUpgradeContent => _pick('升级内容', 'Update Details', '更新内容');
  String get otaNoReleaseNotes =>
      _pick('暂无升级说明', 'No release notes', '更新説明はありません');
  String otaNewVersionConfirm(String version) => _pick(
    '检测到新版本：$version，是否升级？',
    'New version $version found. Update now?',
    '新しいバージョン $version が見つかりました。更新しますか？',
  );
  String otaNewVersionNote(String version) =>
      _pick('发现新版本：$version', 'New version: $version', '新しいバージョン：$version');
  String otaCurrentVersion(String version) =>
      _pick('当前版本 $version', 'Current version $version', '現在のバージョン $version');
  String otaFirmwareVersion(String version) => _pick(
    '固件版本 $version',
    'Firmware version $version',
    'ファームウェアバージョン $version',
  );
  String otaPackageSize(String size) =>
      _pick('升级包 $size', 'Package $size', 'パッケージ $size');
  String otaDoneDetail(String done, int size, int packets) => _pick(
    '$done（$size 字节 / $packets 包）',
    '$done ($size bytes / $packets packets)',
    '$done（$size バイト / $packets パケット）',
  );

  // ── 首页 ──
  String get homeNoDeviceTitle =>
      _pick('暂未绑定设备', 'No Device Bound', '端末が未登録です');
  String get homeNoDeviceMessage => _pick(
    '当前暂无可投屏电子纸设备，请先绑定电子纸设备',
    'No e-paper device to cast to. Please bind one first.',
    '投影できる電子ペーパーがありません。先に電子ペーパーを登録してください。',
  );
  String get homeBindNow => _pick('立即绑定', 'Bind Now', '今すぐ登録');
  String get homeReadPhotoFailed => _pick(
    '无法读取照片，请检查相机/相册权限后重试。',
    'Unable to read photo. Please check camera/album permissions and try again.',
    '写真を読み込めません。カメラ／アルバムの権限を確認して再試行してください。',
  );
  String get homeConnectingDevice => _pick('连接设备中', 'Connecting…', '接続中…');

  // ── 低电量提醒（2026-08-21 同步小程序）────────────────────────────────
  // 口径：**用户主动点**需要连接电子纸设备的功能按钮时，电量 ≤10% 弹一次；
  // 自动连接的场景不弹（投屏流程内部的续连等），弹窗只会打断正在跑的流程。
  // 两档分界：10%~4% 一段、≤3% 另一段（需求原文写「3%以下」，字面上 3% 落在两档中间的缝里，
  // 第一档明确到 4% 为止，所以 3% 归下面那档，与小程序 CRITICAL_BATTERY_MAX 一致）。
  String get lowBatteryTitle => _pick('电量提醒', 'Battery Notice', 'バッテリー通知');
  String get lowBatteryMessage => _pick(
    '目前电子纸设备电量较低，请将电子纸设备放置在光线明亮处使用，并可适当减少操作频次。',
    'The e-paper device is running low on battery. Place it in a well-lit spot and use it less often for now.',
    '電子ペーパーのバッテリー残量が少なくなっています。明るい場所に置いて、操作の頻度を控えめにしてください。',
  );
  String get lowBatteryCriticalMessage => _pick(
    '目前电子纸设备电量低于3%，即将关机，请将电子纸设备放置在阳光充足或光线明亮的区域，进行光能充电即可恢复使用。',
    'The e-paper device is below 3% battery and will power off soon. Place it in direct sunlight or a bright area to recharge with light and it will resume working.',
    '電子ペーパーのバッテリー残量が3%未満で、まもなく電源が切れます。日当たりの良い場所や明るい場所に置くと、光で充電されて再び使えるようになります。',
  );
  String get homeOfflineTitle => _pick('离线模式', 'Offline Mode', 'オフラインモード');
  String get homeOfflineMessage => _pick(
    '当前网络异常，app进入离线模式无法同步投屏记录与图库',
    'Network error. The app is offline and cannot sync cast records or the gallery.',
    'ネットワークエラーです。アプリはオフラインになり、投影履歴とギャラリーを同期できません。',
  );
  String get homeUnboundHint => _pick(
    '请先绑定电子纸设备后再投屏照片',
    'Bind an e-paper device before casting photos.',
    '写真を投影する前に電子ペーパーを登録してください。',
  );
  String get homeBindDevice => _pick('绑定设备', 'Bind Device', '端末を登録');
  String get homeCastSheetTitle =>
      _pick('选择投屏方式', 'Choose Cast Method', '投影方法を選択');
  String get homeCastCameraTitle => _pick('拍照', 'Camera', '撮影');
  String get homeCastAlbumTitle => _pick('相册', 'Album', 'アルバム');
  String get homeCastCameraCardSubtitle =>
      _pick('拍摄照片并投屏', 'Take a photo and cast it', '写真を撮って投影');
  String get homeCastAlbumCardSubtitle =>
      _pick('选择照片并投屏', 'Pick a photo and cast it', '写真を選んで投影');

  // ── 首页六大入口（2026-08-21 同步小程序改版）────────────────────────────
  // 原来首页只有「拍照 / 相册」两张卡，底栏另有「AI助手」「官方图库」两格；
  // 改版后底栏只剩「首页 / 我的」，六个入口全部收进首页 3×2 宫格。
  // ⚠️ 前两项的**标题变了**（拍照 → 拍照投屏、相册 → 相册投屏），
  //    但底部「选择投屏方式」弹层里那两行仍用旧的 homeCastCameraTitle/homeCastAlbumTitle，
  //    两套别互相替换。副标题两项复用旧的，文案完全一致。
  String get homeEntryCameraTitle =>
      _pick('拍照投屏', 'Camera Cast', 'カメラ投影');
  String get homeEntryAlbumTitle => _pick('相册投屏', 'Album Cast', 'アルバム投影');
  String get homeEntryUploadsTitle =>
      _pick('我的上传', 'My Uploads', 'マイアップロード');
  String get homeEntryUploadsSubtitle =>
      _pick('管理我的照片', 'Manage my photos', '写真を管理');
  String get homeEntryAiTitle => _pick('AI创作', 'AI Create', 'AI作成');
  String get homeEntryAiSubtitle =>
      _pick('AI生成精美图片', 'Generate images with AI', 'AIで画像を生成');
  String get homeEntryGallerySubtitle =>
      _pick('海量精选美图', 'Curated wallpapers', '厳選画像が多数');
  String get homeEntryDevicesSubtitle =>
      _pick('管理我的设备', 'Manage my devices', 'デバイスを管理');
  String get homeBindSearchingTitle =>
      _pick(
        '正在搜索附近电子纸设备',
        'Searching for nearby e-paper devices',
        '近くの電子ペーパーを検索中',
      );
  String get homeBindSearchingSubtitle => _pick(
    '请尽量将手机靠近需要添加的电子纸设备...',
    'Keep your phone close to the e-paper device you want to add...',
    '追加したい電子ペーパーにスマホをできるだけ近づけてください...',
  );
  String get homeBindCancelScan => _pick('取消扫描', 'Cancel Scan', 'スキャンを中止');
  String get homeBindNotFoundTitle =>
      _pick(
        '未发现电子纸设备',
        'No E-paper Device Found',
        '電子ペーパーが見つかりません',
      );
  String get homeBindNotFoundSubtitle => _pick(
    '电子纸设备连接中断，请检查电子纸设备状态后重试',
    'The connection was interrupted. Check the e-paper device and try again.',
    '接続が中断されました。電子ペーパーの状態を確認して再試行してください。',
  );
  String get homeRescan => _pick('重新扫描', 'Scan Again', '再スキャン');
  String get homeScanHelpTitle =>
      _pick('扫描不到怎么办?', "Can't find your device?", 'スキャンできない場合は？');
  String get homeNearbyDevices => _pick('附近设备', 'Nearby Devices', '近くの端末');
  String get homeScanHelpChecklistTitle =>
      _pick('请检查：', 'Please check:', '確認してください：');
  String get homeScanHelpBody => _pick(
    '1.电子纸设备是否有电?\n'
        '2.当前电子纸设备是否被占用?\n'
        '3.电子纸设备蓝牙是否工作正常，手机蓝牙是否打开\n'
        '4.电子纸设备是否与手机距离过远，隔离或有其他遮挡物',
    '1. Is the e-paper device powered on?\n'
        '2. Is the e-paper device already in use?\n'
        "3. Is the e-paper device's Bluetooth working, and is your phone's Bluetooth on?\n"
        '4. Is the e-paper device too far, isolated, or otherwise obstructed?',
    '1. 電子ペーパーの電源は入っていますか？\n'
        '2. 電子ペーパーが他で使用中ではありませんか？\n'
        '3. 電子ペーパーのBluetoothは正常で、スマホのBluetoothはオンですか？\n'
        '4. 電子ペーパーがスマホから離れすぎたり、遮蔽物はありませんか？',
  );
  String get homeCastCameraSheetSubtitle =>
      _pick('调用手机相机拍照', 'Use your phone camera to take a photo', 'スマホのカメラで撮影');
  String get homeCastAlbumSheetSubtitle => _pick(
    '从手机相册选择照片',
    'Choose a photo from your phone album',
    'スマホのアルバムから選択',
  );
  String get homeGreetingWelcome => _pick('欢迎使用 ', 'Welcome to ', 'ようこそ ');
  String get homeConnected => _pick('已连接', 'Connected', '接続済み');
  String get homeDisconnected => _pick('未连接', 'Not Connected', '未接続');
  String get homeConnectBluetooth =>
      _pick('连接蓝牙', 'Connect Bluetooth', 'Bluetooth接続');

  // ── 我的相册（2026-08-04 由「设备照片」+「投屏管理」合并而来）──
  /// 2026-07-31 标题由「我的图库」改为「设备照片」（对齐小程序 list.wxml 的 page-nav）。
  /// 2026-08-01 起页面不再显示标题（改由设备下拉承担），2026-08-04 模块更名为「我的相册」。
  /// 本条仅保留给别处引用。
  String get galTitle => _pick('我的相册', 'My Album', 'マイアルバム');

  /// 列表顶部的一行说明。2026-08-04：页面从「设备照片」改成「我的相册」（投屏成功的照片），
  /// 底部动作也由「刷新屏幕/删除」变成「再次投屏/删除」，说明条同步改写。
  String get galScreenHint => _pick(
    '选中照片可再次投屏或删除，支持多选/全选',
    'Select photos to cast again or delete. Multi-select and select-all supported.',
    '写真を選んで再キャストまたは削除できます。複数選択・全選択に対応。',
  );
  String get galFrame => _pick('相框', 'Photo Frame', 'フォトフレーム');
  String get galTip => _pick('提示', 'Notice', 'お知らせ');
  String get galDeviceClearedNotice => _pick(
    '当前电子纸设备已被执行清空操作，请重新上传图片',
    'This e-paper device has been cleared. Please upload photos again.',
    'この電子ペーパーはクリアされました。写真を再度アップロードしてください。',
  );
  String get galConfirm => _pick('确认', 'Confirm', '確認');
  String get galDeleting => _pick('删除中', 'Deleting…', '削除中…');
  // 2026-08-17 删除：`galRefreshing` / `galRefreshScreen`（手动「刷新屏幕」0x24 的文案）。
  // 入口 2026-08-04 页面合并时就没了（底部第一枚圆钮改成「再次投屏」），本轮随
  // `refreshGalleryPhotoOnScreen` 一并下线。删除时删到屏显图的自动补刷屏不带文案。

  /// 底部第一枚圆钮：2026-08-04 由「刷新屏幕(0x24)」改为「再次投屏」（对齐小程序底栏）。
  /// 本页只展示投屏成功的照片，所以恒为「再次投屏」，没有「重新投屏」这一态。
  String get galRecast => _pick('再次投屏', 'Cast Again', '再キャスト');

  /// 多选/全选超过一次可投的张数上限（[CastUploadLimit.batchLimit]，常规 10 张）。
  String galRecastLimit(int limit) => _pick(
    '一次最多投屏 $limit 张照片',
    'You can cast at most $limit photos at a time.',
    '一度にキャストできるのは最大$limit枚です。',
  );

  /// 所选记录都没有可用的图片地址（相册原图与记录图都缺失）。
  String get galRecastNoImage => _pick(
    '所选照片没有可投屏的图片',
    'The selected photos have no image to cast.',
    '選択した写真にキャストできる画像がありません。',
  );

  /// 批量再次投屏时的准备提示（连接完成后下载原图阶段）。
  String get galRecastPreparing => _pick('准备照片中', 'Preparing photos…', '写真を準備中…');

  /// 记录与设备下拉都定位不到目标设备（后端两处都没回 userProductId 时的兜底）。
  /// 再次投屏与删除共用：两条链路都要连「这些照片所属的那台设备」。
  String get galRecastNoDevice => _pick(
    '未找到这些照片所属的电子纸设备，请刷新后重试',
    'Could not find the e-paper device these photos belong to. Please refresh and retry.',
    'これらの写真が属する電子ペーパーが見つかりません。更新して再試行してください。',
  );
  // ── 星币（2026-08-12 App 侧补齐管理页与记录页，对齐小程序 subpackages/token）──
  // ⚠️ 购买链路 App 侧未接（IAP），页面只读，见 star_coin_page.dart 文件头。
  String get starCoinTitle => _pick('星币管理', 'Stars', 'スターコイン');
  String get starMyBalance => _pick('我的星币', 'My Stars', 'マイスターコイン');
  String get starAvailable => _pick('当前可用余额', 'Available', '利用可能残高');
  String get starTotalPurchased => _pick('总额（累计购买）', 'Purchased', '購入累計');
  String get starTotalSpent => _pick('已消耗', 'Used', '使用済み');
  String get starRecordsTitle =>
      _pick('购买 & 消费记录', 'Purchases & Usage', '購入・使用履歴');
  String get starRecordsDesc =>
      _pick('查看所有购买和消费明细', 'All purchase and usage details', '購入・使用の明細を見る');
  String get starPurchaseRecords => _pick('购买记录', 'Purchases', '購入履歴');
  String get starSpendRecords => _pick('消费记录', 'Usage', '使用履歴');
  String get starNoPurchaseRecords =>
      _pick('还没有购买记录', 'No purchases yet', '購入履歴はまだありません');
  String get starNoSpendRecords =>
      _pick('还没有消费记录', 'No usage yet', '使用履歴はまだありません');
  String get starGift => _pick('赠送', 'Bonus', 'ボーナス');
  String get starRulesTitle =>
      _pick('星币消耗规则', 'How stars are used', 'スターコインの消費ルール');
  String get starRuleColService => _pick('服务类型', 'Service', 'サービス');

  /// 表头就写「星币/次」（2026-08-13 两端同改）：原文「星币消耗（星币/次）」在窄列里必然
  /// 折成两行、把括号拆开，而「消耗」二字区块标题「星币消耗规则」已经交代过。
  String get starRuleColCost => _pick('星币/次', 'Per use', '1回あたり');

  /// ⚠️ **只在 iOS 上出现**：安卓 2026-08-27 起走 PayPal（见 [starBuyEntryTitle]），
  /// iOS 的 Apple 内购仍未接。措辞不能再写「App 端」——那会把已经能买的安卓也一起否掉。
  String get starPurchaseUnavailable => _pick(
    'iOS 端暂未开放星币购买，请前往微信小程序「BoltStar 智能相框」购买后在此查看余额。',
    'Buying stars is not available on iOS yet. Purchase in the BoltStar mini program; your balance shows up here.',
    'iOS ではスターコインを購入できません。WeChat ミニプログラムで購入すると、残高がここに反映されます。',
  );

  // ── 星币购买（2026-08-27 安卓接入 PayPal；小程序=微信支付、iOS=Apple 内购未接）──

  String get starBuyEntryTitle => _pick('购买星币', 'Buy Stars', 'スターコインを購入');
  String get starBuyEntryDesc =>
      _pick('选择套餐，PayPal 支付', 'Choose a plan, pay with PayPal', 'プランを選んで PayPal で支払う');
  String get starBuyTitle => _pick('确认购买', 'Confirm Purchase', '購入の確認');
  String get starBuyChoosePackage => _pick('选择套餐', 'Choose a plan', 'プランを選択');
  String get starBuyPayChannel => _pick('支付方式', 'Payment method', '支払い方法');

  /// 套餐卡上的赠送角标。
  String starBuyGift(int count) =>
      _pick('赠 $count', '+$count bonus', '$count ボーナス');

  /// 套餐卡底部的单价（约）。⚠️ 按含赠送总数算，见 [StarPackage.unitPrice]。
  String starBuyUnitPrice(String price, String currency) =>
      _pick('≈ $currency$price/星币', '≈ $currency$price/star', '≈ $currency$price/コイン');

  String get starBuyTotalGain => _pick('合计获得', 'You get', '合計獲得');
  String get starBuyAmountDue => _pick('应付金额', 'Total', 'お支払い金額');
  String get starBuyNow => _pick('立即购买', 'Buy now', '今すぐ購入');
  String get starBuyEmpty =>
      _pick('暂无可购买的套餐', 'No plans available right now', '購入できるプランがありません');

  /// 三段式 loading 文案：这条链路最长约 10s，中间没反馈用户会以为卡死。
  String get starBuyStageOrder => _pick('正在下单…', 'Creating order…', '注文を作成中…');
  String get starBuyStagePay =>
      _pick('正在拉起支付…', 'Opening PayPal…', 'PayPal を起動中…');
  String get starBuyStageConfirm =>
      _pick('正在确认到账…', 'Confirming payment…', '入金を確認中…');

  String get starBuyApprovingTitle =>
      _pick('已跳转 PayPal', 'PayPal opened', 'PayPal を開きました');
  String get starBuyApprovingDesc => _pick(
    '请在 PayPal 完成支付，然后回到这里。星币到账后余额会自动更新。',
    'Finish the payment in PayPal, then come back here. Your balance updates once the stars arrive.',
    'PayPal で支払いを完了してから、この画面に戻ってください。入金後に残高が更新されます。',
  );
  String get starBuyApprovingDone =>
      _pick('我已完成支付', 'I have paid', '支払いを完了しました');
  String get starBuyApprovingGiveUp =>
      _pick('放弃本次支付', 'Cancel this payment', 'この支払いをやめる');

  /// 到账确认成功。数量取**服务端余额的增量**，不是套餐上写的数（以服务端为准）。
  String starBuySucceeded(int gained) => _pick(
    '购买成功，到账 $gained 星币',
    'Purchase complete — $gained stars added',
    '購入完了：$gained コインが追加されました',
  );

  /// 查单说已支付、但余额还没变。⚠️ 不能说成失败：钱已经付了。
  String get starBuyPendingPaid => _pick(
    '已收到付款，星币稍后到账',
    'Payment received. Your stars will arrive shortly.',
    '支払いを受け付けました。まもなく反映されます。',
  );

  /// 余额没变、查单也没说已支付。⚠️ 同样**不说失败**：可能是用户取消了，
  /// 也可能是渠道回调慢，端上分不清，就别替后端下结论。
  String get starBuyPendingUnknown => _pick(
    '支付结果确认中，可稍后在购买记录里查看',
    'Still confirming the payment. Check your purchase records later.',
    '支払い結果を確認中です。購入履歴で後ほどご確認ください。',
  );

  String get starBuyOrderFailed =>
      _pick('下单失败，请稍后重试', 'Could not create the order. Please try again.', '注文の作成に失敗しました。後でもう一度お試しください。');
  String get starBuyCreatePayFailed => _pick(
    '未能拉起 PayPal 支付，请稍后重试',
    'Could not start the PayPal payment. Please try again.',
    'PayPal の支払いを開始できませんでした。後でもう一度お試しください。',
  );
  String get starBuyLaunchFailed => _pick(
    '打不开 PayPal 页面，请确认已安装浏览器或 PayPal App',
    'Could not open PayPal. Make sure a browser or the PayPal app is installed.',
    'PayPal を開けませんでした。ブラウザまたは PayPal アプリを確認してください。',
  );

  // ── 官方图库 / 我的收藏（2026-08-12 App 侧补齐该模块，对齐小程序 subpackages/gallery）──
  String get galleryOfficialTitle =>
      _pick('官方图库', 'Official Gallery', '公式ギャラリー');
  String get galleryFavoritesTitle => _pick('我的收藏', 'My Favorites', 'お気に入り');
  String get galleryFavorites => _pick('收藏', 'Favorites', 'お気に入り');

  /// 分类条首项。后端只给真实分类，「全部」是端上补的（列表接口不传 categoryId 即全部）。
  String get galleryAllCategory => _pick('全部', 'All', 'すべて');
  String get galleryEmptyCategory =>
      _pick('该分类下还没有图片', 'No images in this category yet.', 'このカテゴリーにはまだ画像がありません');
  String get galleryFavoritesEmpty => _pick(
    '还没有收藏任何官方图片',
    'You have not saved any official images yet.',
    'まだ公式画像をお気に入りに追加していません',
  );
  String galleryFavoriteCount(int count) => _pick(
    '共收藏 $count 张官方图片',
    '$count official images saved',
    '公式画像を$count枚保存済み',
  );
  String get galleryLoading => _pick('加载中…', 'Loading…', '読み込み中…');
  String get galleryPullMore =>
      _pick('上拉加载更多', 'Pull up to load more', '上にスワイプして続きを読み込む');
  String get galleryNoMore => _pick('没有更多了', 'No more items', 'これ以上ありません');
  String get galleryFavorite => _pick('收藏', 'Save', '保存');
  String get galleryCancelFavorite => _pick('取消收藏', 'Saved', '保存済み');
  String get galleryFavorited => _pick('已收藏', 'Saved', '保存しました');
  String get galleryUnfavorited => _pick('已取消收藏', 'Removed', '保存を解除しました');
  String get galleryFavoriteFailed =>
      _pick('操作失败，请重试', 'Action failed. Please try again.', '操作に失敗しました。再試行してください');
  String get galleryLoadFailed =>
      _pick('图片加载失败', 'Failed to load the image.', '画像の読み込みに失敗しました');
  String get galleryPhotoGone => _pick(
    '图片不存在或已下架',
    'This image no longer exists.',
    'この画像は存在しないか、公開が終了しました',
  );
  String get galleryStartCast => _pick('开始投屏', 'Start Casting', 'キャスト開始');
  String get galleryNoBoundDevice => _pick(
    '暂无已绑定电子纸设备，请先绑定',
    'No paired e-paper device yet. Please pair one first.',
    'ペアリング済みの電子ペーパーがありません。先にペアリングしてください',
  );
  // ── 「选择投屏设备」弹层（AI 对话页与官方图库详情页共用一份，见 device_picker_sheet.dart）──
  // 2026-08-13 起改「先选再连」：文案不能再说「选完自动连接」，那正是本轮要去掉的行为。
  String get devicePickerTitle =>
      _pick('选择投屏设备', 'Choose a device', 'キャスト先を選択');
  String get devicePickerDesc => _pick(
    '选择要投屏的电子纸设备，点击下方按钮开始连接',
    'Pick the e-paper device to cast to, then tap the button below to connect.',
    'キャスト先の電子ペーパーを選び、下のボタンで接続してください',
  );
  String get devicePickerConfirm =>
      _pick('连接并投屏', 'Connect and cast', '接続してキャスト');

  String get galSelectAll => _pick('全选', 'Select All', 'すべて選択');
  String galTotalCount(int count) =>
      _pick('共 $count 张', '$count total', '合計$count枚');
  String get galDeletePhotos => _pick('删除照片', 'Delete Photos', '写真を削除');

  /// 2026-08-04：删除同时清掉设备槽位、相册记录与来源投屏记录，文案同步说明。
  String galDeleteConfirm(int count) => _pick(
    '确认删除已选的$count张照片吗？删除后将同时从电子纸设备与我的相册中移除，且无法恢复',
    'Delete the $count selected photo(s)? They will be removed from both the e-paper device and My Album, and cannot be recovered.',
    '選択した$count枚の写真を削除しますか？電子ペーパーとマイアルバムの両方から削除され、復元できません。',
  );

  /// 选中的投屏记录里有缺索引/非法 `imgIndex` 的：设备上定位不到位置，**整批终止**。
  /// 刻意不推算——推算只会删掉别人的图（2026-08-17：图库列表下线后记录里的索引是唯一来源）。
  /// 取代了原来的 `galDeleteNeedAlbum`（相册账本没加载完的拦截，账本已不存在）。
  String get galDeleteNoSlot => _pick(
    '投屏记录未返回有效的图片索引，无法删除',
    'This cast record has no valid image index, so it cannot be deleted.',
    'この投映履歴には有効な画像インデックスがないため、削除できません。',
  );

  /// 设备与相册记录都删掉了，但来源投屏记录没删干净（照片下次进来可能还在列表里）。
  String get galDeleteRecordPartialFail => _pick(
    '照片已删除，投屏记录未全部删除，请稍后重试',
    'Photos deleted, but some cast records could not be removed. Please retry later.',
    '写真は削除しましたが、一部の投映履歴を削除できませんでした。後で再試行してください。',
  );

  /// 两半都删成功。原来这句写在 `state.dart` 的设备侧返回值里；2026-08-20 两半互不阻断后，
  /// 「成功」是由调用方合并两半结果才得出的结论，文案跟着搬到这里。
  String get galDeleteDone =>
      _pick('已删除所选照片。', 'Selected photos deleted.', '選択した写真を削除しました。');

  /// 2026-08-20（两半互不阻断）：设备侧没删掉，但投屏记录已经删了。
  /// 必须把设备侧的原因报出来——只说「已删除」的话，用户不会知道相框上那张图其实还在。
  String galDeleteRecordOnly(String reason) => _pick(
    '投屏记录已删除，$reason',
    'Cast records deleted. $reason',
    '投映履歴を削除しました。$reason',
  );

  /// 2026-08-20（两半互不阻断）：设备侧与记录侧都没删成功，两边原因一起说。
  String galDeleteBothFailed(String reason) => _pick(
    '电子纸设备与投屏记录都未删除成功：$reason',
    'Failed to delete from both the e-paper device and the cast records: $reason',
    '電子ペーパーと投映履歴のどちらも削除できませんでした：$reason',
  );
  String get galEmptyTitle => _pick(
    '当前电子纸设备还没有投屏成功的照片',
    'No successfully cast photos on this e-paper device yet',
    'この電子ペーパーにキャスト成功した写真はまだありません',
  );
  String get galEmptySubtitle => _pick(
    '投屏成功的照片会自动出现在这里',
    'Photos cast successfully will show up here',
    'キャストに成功した写真がここに表示されます',
  );

  // ── 引导 ──
  String get guideTitle => _pick('操作指南', 'User Guide', '操作ガイド');
  String get guideEmpty => _pick('暂无常见问题', 'No FAQs yet', 'よくある質問はありません');

  // ── 我的 ──
  // 「常用功能」标题 2026-08-19（同步小程序 08-11）按产品要求从「我的」页去掉，
  // 目前无消费方。留着这一条只为万一要改回来时不用重译；不要拿它当新标题复用。
  String get mineCommonFeatures => _pick('常用功能', 'Features', 'よく使う機能');
  String get mineServiceHelp => _pick('服务与帮助', 'Service & Help', 'サービスとヘルプ');
  /// 2026-08-04：「设备照片」与「投屏管理」两张卡合并为一张（投屏成功的照片）。
  /// 合并后宫格由三卡变两卡、卡片等分宽度，日语不再需要为 102 宽缩写。
  ///
  /// 2026-08-24 标题由「我的相册」改成「我的上传」（同步小程序 `mine.wxml`，旧 key
  /// `mineMyGallery` 一并改名）。与 [homeEntryUploadsTitle] 文案相同、**故意各留一份**：
  /// 首页宫格与「我的」页那张卡是两处产品件，以后只改一处时不该互相牵连。
  /// ⚠️ 卡片副标题的张数同日改取 `getUserInfo` 的 `imgCount`（上传口径，含投屏失败/已删），
  /// 与标题是同一个决定——目的地仍是「我的相册」页（投屏成功记录），别再把标题改回去。
  String get mineMyUploads => _pick('我的上传', 'My Uploads', 'マイアップロード');
  String get mineMyDevices => _pick('我的设备', 'My Devices', 'マイデバイス');
  // 英语「Cast Management」在窄卡里过长换行，缩为单词「Casting」。
  // 2026-08-04 起「我的」不再有这张卡，本条仍供投屏管理页自身（投屏结果页「投屏明细」进入）使用。
  String get mineCastManagement => _pick('投屏管理', 'Casting', 'キャスト管理');
  String get mineGuide => _pick('操作指南', 'User Guide', '操作ガイド');
  String get mineSettings => _pick('设置', 'Settings', '設定');
  String mineUserId(String id) => _pick('ID：$id', 'ID: $id', 'ID：$id');
  String minePhotoCountText(bool loaded, int value) => _pick(
    loaded ? '$value张照片' : '--张照片',
    loaded ? '$value photos' : '-- photos',
    loaded ? '$value枚' : '--枚',
  );
  String mineDeviceCountText(bool loaded, int value) => _pick(
    loaded ? '$value个设备' : '--个设备',
    loaded ? '$value devices' : '-- devices',
    loaded ? '$value台' : '--台',
  );

  /// 「我的 → 星币管理」行右侧的余额（对齐小程序 `.service-value` 的「剩余 N 星币」）。
  /// 余额还没到手时给 `--` 而不是 0：显示 0 会被当成「我的星币被清空了」。
  String mineStarBalanceText(int? value) {
    final amount = value?.toString() ?? '--';
    return _pick('剩余 $amount 星币', '$amount stars left', '残り $amount スターコイン');
  }

  // ── 设置 ──
  String get setPrivacyTitle => _pick('隐私政策', 'Privacy Policy', 'プライバシーポリシー');
  String get setAgreementTitle => _pick('用户协议', 'User Agreement', '利用規約');
  String get setUpdateBoltStar =>
      _pick('更新BoltStar', 'Update BoltStar', 'BoltStarを更新');
  String get setUpdateNow => _pick('立即更新', 'Update Now', '今すぐ更新');
  String get setUpdatedToLatest =>
      _pick('已更新到最新版本', 'Updated to the latest version', '最新バージョンに更新しました');
  String get setCheckingUpdate =>
      _pick('正在检查更新…', 'Checking for updates…', '更新を確認中…');
  String get setCheckUpdateFailed => _pick(
    '检查更新失败，请稍后重试',
    'Failed to check for updates. Please try again later.',
    '更新の確認に失敗しました。しばらくしてから再試行してください。',
  );
  String get setDownloadOpenFailed => _pick(
    '无法打开下载页面，请稍后重试',
    'Could not open the download page. Please try again later.',
    'ダウンロードページを開けませんでした。しばらくしてから再試行してください。',
  );
  String get setAppIntro => _pick(
    'BoltStar是一款帮助您轻松管理和分享照片的应用，连接电子纸设备，珍藏生活每一刻。',
    'BoltStar helps you easily manage and share photos, connect your e-paper device, and treasure every moment of life.',
    'BoltStarは写真を簡単に管理・共有し、電子ペーパーに接続して、生活の一瞬一瞬を大切に残せるアプリです。',
  );
  String setVersionLabel(String version) =>
      _pick('版本$version', 'Version $version', 'バージョン$version');
  String setVersionCompare(String current, String latest) => _pick(
    '当前版本$current · 最新版本$latest',
    'Current $current · Latest $latest',
    '現在 $current · 最新 $latest',
  );
  // setUpdating / setDownloading 已随「下载进度环」一并移除：下载安装交给应用商店，
  // App 侧拿不到真实进度，不再有「正在更新 / 正在下载」态。
  // 强制升级弹窗（登录成功后 compulsory=1 时弹出，不可关闭）。
  String get setForceUpdateTitle =>
      _pick('发现新版本', 'Update Required', '新しいバージョンがあります');
  String setForceUpdateVersion(String version) =>
      _pick('最新版本 $version', 'Latest version $version', '最新バージョン $version');
  String get setForceUpdateMessage => _pick(
    '当前版本过低，需要更新到最新版本后才能继续使用。',
    'This version is out of date. Please update to continue using the app.',
    'ご利用のバージョンは古いため、続行するには最新バージョンへの更新が必要です。',
  );
  String setUpdatedDate(String date) =>
      _pick('更新日期：$date', 'Updated: $date', '更新日：$date');
  String setEffectiveDate(String date) =>
      _pick('生效日期：$date', 'Effective: $date', '施行日：$date');
}

/// 语言选择的本地持久化（对齐 [EmailHistory] 的轻量键值做法），保证重启后仍是上次选的语言。
class LanguagePreference {
  LanguagePreference._();

  static const String _key = 'app_language';

  /// 读取上次保存的语言；无记录返回 null（调用方保留默认 zh）。
  static Future<AppLanguage?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    switch (value) {
      case 'zh':
        return AppLanguage.zh;
      case 'zhHant':
      case 'zh-Hant':
      case 'zh_hant':
        return AppLanguage.zhHant;
      case 'en':
        return AppLanguage.en;
      case 'ja':
        return AppLanguage.ja;
      default:
        return null;
    }
  }

  static Future<void> save(AppLanguage language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, language.name);
  }
}
