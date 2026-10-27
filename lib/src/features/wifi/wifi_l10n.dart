import '../../shared/l10n/app_l10n.dart';

/// WiFi 版设备（搜索标签、配网三页、我的设备分组、WiFi 设备详情、WiFi 投屏结果）的文案。
///
/// 简中原文与小程序 main-wifi 分支逐字一致；繁中由简中自动转换（同 [AppL10n.pick]）。
/// 单独成文件而不并进 [AppL10n]：这批文案跟着 WiFi 版对接文档一起演进，混进主目录不好找。
extension WifiL10n on AppL10n {
  // ── 通信类型标签 / 信号 ──
  String get wifiBadge => pick('WiFi版', 'Wi-Fi', 'WiFi版');
  String get bleBadge => pick('蓝牙版', 'Bluetooth', 'Bluetooth版');
  String get wifiSignal => pick('信号', 'Signal', '信号');

  // ── 搜索设备页 ──
  String get wifiProvisionNow => pick('立即配网', 'Set up Wi-Fi', 'Wi-Fiを設定');
  String get wifiUnknownDevice => pick('未知设备', 'Unknown device', '不明なデバイス');
  String get wifiUnknownDeviceTip => pick(
    '未知设备，请联系客服开通',
    'Unknown device. Please contact customer service to activate it.',
    '不明なデバイスです。カスタマーサービスに開通をご依頼ください',
  );
  String get wifiLookingUp => pick(
    '正在查询设备信息，请稍候',
    'Checking device information, please wait',
    'デバイス情報を確認しています。しばらくお待ちください',
  );
  String get wifiConnectDeviceFailed => pick(
    '连接设备失败，请靠近设备后重试',
    'Failed to connect to the device. Move closer and try again.',
    'デバイスに接続できませんでした。デバイスに近づいて再度お試しください',
  );

  // ── 选择 WiFi 页 ──
  String get wifiListTitle => pick('选择WiFi', 'Choose Wi-Fi', 'Wi-Fiを選択');
  String get wifiOnly24G => pick(
    '设备仅支持 2.4G WiFi 配网',
    'The device only supports 2.4 GHz Wi-Fi',
    'デバイスは2.4GHzのWi-Fiのみ対応しています',
  );
  String get wifiManualHint => pick(
    '若搜索不到您的wifi，请手动输入',
    "Can't find your Wi-Fi? Enter it manually",
    'Wi-Fiが見つからない場合は手動で入力してください',
  );
  String get wifiListHead => pick('设备附近的2.4G WiFi', '2.4 GHz Wi-Fi near the device', 'デバイス付近の2.4GHz Wi-Fi');
  String get wifiRescan => pick('重新搜索', 'Search again', '再検索');
  String get wifiConnectingDevice => pick('正在连接设备...', 'Connecting to device...', 'デバイスに接続中...');
  String get wifiSearchingNetwork => pick('正在搜索网络...', 'Searching for networks...', 'ネットワークを検索中...');
  String get wifiManualInput => pick('手动输入WiFi名称', 'Enter Wi-Fi name manually', 'Wi-Fi名を手動入力');
  String get wifiTargetExpired => pick(
    '设备信息已失效，请返回重新搜索设备',
    'Device information has expired. Go back and search again.',
    'デバイス情報が無効になりました。戻って再検索してください',
  );
  String get wifiListConnectFailed => pick(
    '连接设备失败，请将手机靠近设备后重新搜索',
    'Failed to connect to the device. Move your phone closer and search again.',
    'デバイスに接続できませんでした。スマートフォンを近づけて再検索してください',
  );
  String wifiScanDeviceError(String message) => pick(
    '$message，请重新搜索或手动输入WiFi名称',
    'The device reported an error. Search again or enter the Wi-Fi name manually.',
    'デバイスでエラーが発生しました。再検索するか、Wi-Fi名を手動で入力してください',
  );
  String get wifiScanSendFailed => pick(
    '发送扫描指令失败，请重新搜索或手动输入WiFi名称',
    'Failed to start the scan. Search again or enter the Wi-Fi name manually.',
    'スキャンを開始できませんでした。再検索するか、Wi-Fi名を手動で入力してください',
  );
  String get wifiScanNoList => pick(
    '设备未返回WiFi列表（可能没扫到网络或设备不支持），请重新搜索或手动输入WiFi名称',
    'The device returned no Wi-Fi list. Search again or enter the Wi-Fi name manually.',
    'デバイスからWi-Fi一覧が返されませんでした。再検索するか、Wi-Fi名を手動で入力してください',
  );
  String get wifiScanNo24G => pick(
    '设备附近没有搜到2.4G WiFi，请重新搜索或手动输入WiFi名称',
    'No 2.4 GHz Wi-Fi found near the device. Search again or enter the name manually.',
    'デバイス付近に2.4GHz Wi-Fiが見つかりません。再検索するか、手動で入力してください',
  );

  // ── WiFi 账号密码页 ──
  String get wifiConfigTitle => pick('WiFi 配网', 'Wi-Fi setup', 'Wi-Fi設定');
  String get wifiSsidLabel => pick('WiFi名称', 'Wi-Fi name', 'Wi-Fi名');
  String get wifiSsidHint => pick('请输入或选择WiFi名称', 'Enter or choose a Wi-Fi name', 'Wi-Fi名を入力または選択');
  String get wifiPasswordLabel => pick('WiFi密码', 'Wi-Fi password', 'Wi-Fiパスワード');
  String get wifiPasswordHint => pick('请输入WiFi密码', 'Enter the Wi-Fi password', 'Wi-Fiパスワードを入力');
  String get wifiNext => pick('下一步', 'Next', '次へ');
  String get wifiConfigTargetExpired => pick(
    '设备信息已失效，请返回重新搜索',
    'Device information has expired. Go back and search again.',
    'デバイス情報が無効になりました。戻って再検索してください',
  );

  // ── 配网状态页 ──
  String get wifiProvisionTitle => pick('设备配网', 'Device setup', 'デバイス設定');
  String get wifiProvisionRunning => pick('设备正在进行配网', 'Setting up the device', 'デバイスを設定しています');
  String get wifiProvisionSuccess => pick('设备入网成功', 'Device is online', 'デバイスがネットワークに接続しました');
  String get wifiProvisionHint => pick(
    '请将手机靠近设备，保持网络连接稳定',
    'Keep your phone close to the device and stay connected',
    'スマートフォンをデバイスに近づけ、安定した接続を保ってください',
  );
  List<String> get wifiProvisionSteps => [
    pick('手机网络正常', 'Phone network OK', 'スマートフォンのネットワーク正常'),
    pick('设备网络配置已完成', 'Device network configured', 'デバイスのネットワーク設定完了'),
    pick('设备正在连接Wi-Fi', 'Device connecting to Wi-Fi', 'デバイスがWi-Fiに接続中'),
    pick('设备正在连接云端', 'Device connecting to the cloud', 'デバイスがクラウドに接続中'),
  ];
  String get wifiTryNow => pick('立即体验', 'Start using', '今すぐ使う');
  String get wifiRetryProvision => pick('重新配网', 'Try again', '再設定');
  String get wifiCancel => pick('取消', 'Cancel', 'キャンセル');
  String get wifiJobExpired => pick(
    '配网信息已失效，请返回重新配网',
    'Setup information has expired. Go back and try again.',
    '設定情報が無効になりました。戻って再設定してください',
  );
  String get wifiErrPhoneNetwork => pick(
    '手机网络不可用，请检查网络后重试',
    'Your phone has no network. Check it and try again.',
    'スマートフォンのネットワークが利用できません。確認して再度お試しください',
  );
  String get wifiErrRelogin => pick(
    '登录已失效，请重新登录',
    'Your session has expired. Please sign in again.',
    'ログインの有効期限が切れました。再度ログインしてください',
  );
  String get wifiErrMqtt => pick(
    '获取设备网络配置失败，请稍后重试',
    'Failed to get the device network configuration. Please try again later.',
    'デバイスのネットワーク設定を取得できませんでした。しばらくしてからお試しください',
  );
  String get wifiErrConnect => pick(
    '连接设备失败，请将手机靠近设备后重试',
    'Failed to connect to the device. Move your phone closer and try again.',
    'デバイスに接続できませんでした。スマートフォンを近づけて再度お試しください',
  );
  String get wifiErrSta => pick(
    '设备网络配置下发失败，请靠近设备后重试',
    'Failed to send the network settings. Move closer and try again.',
    'ネットワーク設定を送信できませんでした。デバイスに近づいて再度お試しください',
  );
  String get wifiErrMqttNoAck => pick(
    '设备未响应网络配置，请重试',
    'The device did not respond to the network settings. Please try again.',
    'デバイスがネットワーク設定に応答しませんでした。再度お試しください',
  );
  String wifiErrMqttResult(Object? code) => pick(
    '设备网络配置失败（错误码 $code）',
    'Device network configuration failed (code $code)',
    'デバイスのネットワーク設定に失敗しました（エラーコード $code）',
  );
  String wifiErrBind(String message) => pick(
    '设备绑定失败：$message',
    'Failed to bind the device: $message',
    'デバイスのバインドに失敗しました：$message',
  );
  String get wifiErrBindRetry => pick('请稍后重试', 'Please try again later', 'しばらくしてからお試しください');
  String get wifiErrServiceUnavailable => pick(
    '服务暂时不可用，请稍后重试',
    'Service temporarily unavailable. Please try again later.',
    'サービスが一時的に利用できません。しばらくしてからお試しください',
  );
  String get wifiErrOnlineTimeout => pick(
    '设备联网超时，请检查WiFi密码或信号后重试',
    'The device timed out going online. Check the Wi-Fi password or signal and try again.',
    'デバイスのネットワーク接続がタイムアウトしました。Wi-Fiのパスワードや電波を確認して再度お試しください',
  );
  String get wifiErrCancelled => pick('已取消配网', 'Setup cancelled', '設定をキャンセルしました');
  String get wifiErrProvisionFailed => pick('配网失败，请重试', 'Setup failed. Please try again.', '設定に失敗しました。再度お試しください');

  // ── 云端状态（我的设备 / 首页 / 详情） ──
  String get wifiStatusLoading => pick('查询中', 'Checking', '確認中');
  String get wifiStatusOnline => pick('在线', 'Online', 'オンライン');
  String get wifiStatusOffline => pick('离线', 'Offline', 'オフライン');
  String get wifiStatusUnknown => pick('状态未知', 'Status unknown', '状態不明');
  String get wifiRefreshStatus => pick('刷新状态', 'Refresh', '状態を更新');
  String get wifiOfflineTip => pick(
    '设备已离线，请检查设备网络',
    'The device is offline. Please check its network.',
    'デバイスがオフラインです。デバイスのネットワークをご確認ください',
  );

  // ── WiFi 设备详情 ──
  String get wifiDetailTitle => pick('设备详情', 'Device details', 'デバイス詳細');
  String get wifiRowBattery => pick('电量', 'Battery', 'バッテリー');
  String get wifiRowSignal => pick('WiFi信号', 'Wi-Fi signal', 'Wi-Fi信号');
  String get wifiRowName => pick('WiFi名称', 'Wi-Fi name', 'Wi-Fi名');
  String get wifiRowVersion => pick('固件版本', 'Firmware version', 'ファームウェアバージョン');
  String get wifiRowTf => pick('TF卡', 'TF card', 'TFカード');
  String get wifiRowCountry => pick('国家码', 'Country code', '国コード');
  String get wifiRowLastOnline => pick('最后上线', 'Last online', '最終オンライン');
  String get wifiRowLastHeart => pick('最后心跳', 'Last heartbeat', '最終ハートビート');
  String get wifiTfAbsent => pick('未插卡', 'No card', '未挿入');
  String get wifiTfPresent => pick('已插卡', 'Inserted', '挿入済み');
  String wifiTfUsage(num used, num total) => pick(
    '已用 ${used}MB / 共 ${total}MB',
    '$used MB used / $total MB',
    '使用 ${used}MB / 合計 ${total}MB',
  );
  String get wifiCountryWorld => pick('世界通用模式', 'Worldwide mode', 'ワールドワイドモード');
  String get wifiScreenSize => pick('屏幕尺寸', 'Screen size', '画面サイズ');

  // ── WiFi 投屏结果页 ──
  String get wifiCastTitle => pick('投屏', 'Cast', 'キャスト');
  String get wifiCastPrepare => pick('准备投屏', 'Preparing', '準備中');
  String get wifiCastWaiting => pick('等待投屏', 'Waiting', '待機中');
  String get wifiCastInProgress => pick('投屏中', 'Casting', 'キャスト中');
  String wifiCastPageIndex(int current, int total) =>
      pick('第 $current / $total 张', '$current / $total', '$current / $total 枚目');
  String wifiCastItemNo(int index) => pick('第 $index 张', 'Photo $index', '$index 枚目');
  String get wifiCastNote => pick(
    '进度为图片上传进度，上传完成后等待设备下载并刷屏',
    'Progress shows the upload. After uploading, the device downloads and refreshes the screen.',
    '進捗はアップロードの進捗です。完了後、デバイスがダウンロードして画面を更新します',
  );
  String get wifiCastRetryFailed => pick('重试未成功的', 'Retry unsuccessful', '失敗分を再試行');
  String get wifiCastDone => pick('完成', 'Done', '完了');
  String wifiCastPartial(int success, int failed) => pick(
    '成功 $success 张，$failed 张未成功',
    '$success succeeded, $failed not',
    '$success 枚成功、$failed 枚未完了',
  );
  String get wifiCastInfoExpired => pick(
    '投屏信息已失效，请返回重新选择',
    'Cast information has expired. Go back and choose again.',
    'キャスト情報が無効になりました。戻って選び直してください',
  );
  String get wifiCastDownloadFailed => pick('原图下载失败', 'Failed to download the original image', '元画像のダウンロードに失敗しました');
  String get wifiCastFailedGeneric => pick('投屏失败，请稍后重试', 'Cast failed. Please try again later.', 'キャストに失敗しました。しばらくしてからお試しください');

  /// 投屏阶段 / 终态文案（服务端只给状态码，文案由 App 维护，文档 1.4 文案对照表 + 评审回复 SENT 口径）。
  String wifiCastStage(String stage) => switch (stage) {
    'UPLOADING' => pick('图片上传中', 'Uploading image', '画像をアップロード中'),
    'PROCESSING' => pick('图片处理中', 'Processing image', '画像を処理中'),
    'SENT' => pick('指令已下发，等待设备', 'Sent, waiting for the device', '送信済み、デバイスを待機中'),
    'DOWNLOADING' => pick('屏幕即将刷新', 'Screen will refresh soon', 'まもなく画面が更新されます'),
    'FLASHING' => pick('设备刷屏中', 'Refreshing the screen', '画面を更新中'),
    'SUCCESS' => pick('投屏成功', 'Cast succeeded', 'キャスト成功'),
    'FAILED' => pick('投屏失败', 'Cast failed', 'キャスト失敗'),
    'TIMEOUT' => pick('投屏超时', 'Cast timed out', 'キャストがタイムアウトしました'),
    'CANCELLED' => pick('已取消', 'Cancelled', 'キャンセルしました'),
    'EXPIRED' => pick('任务已过期，结果未知', 'Task expired, result unknown', 'タスクの期限切れ、結果不明'),
    _ => pick('结果未知，请稍后查看设备', 'Result unknown, check the device later', '結果不明です。後でデバイスをご確認ください'),
  };

  /// 失败原因（play.result / 状态查询的 reason，评审回复 14.1）；认不得返回空串。
  String wifiCastReason(String reason) => switch (reason) {
    'PLAY_DOWNLOAD_FAILED' => pick('设备下载图片失败', 'The device failed to download the image', 'デバイスが画像をダウンロードできませんでした'),
    'PLAY_STORAGE_ERROR' => pick('设备存储异常', 'Device storage error', 'デバイスのストレージエラー'),
    'PLAY_FAILED' => pick('设备处理失败', 'The device failed to process it', 'デバイスの処理に失敗しました'),
    _ => '',
  };
}
