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
  String get wifiStatusSleeping => pick('休眠中', 'Sleeping', 'スリープ中');
  String get wifiStatusShutdown => pick('已关机', 'Powered off', '電源オフ');
  String get wifiStatusUnknown => pick('状态未知', 'Status unknown', '状態不明');
  String get wifiStatusLocal => pick('本地模式', 'Local mode', 'ローカルモード');
  String get wifiRefreshStatus => pick('刷新状态', 'Refresh', '状態を更新');
  String get wifiSleepingTip => pick(
    '设备休眠中，唤醒后可操作',
    'The device is sleeping. Try again after it wakes up.',
    'デバイスはスリープ中です。起動後に操作してください',
  );
  String get wifiShutdownTip => pick(
    '设备已关机，开机后可操作',
    'The device is powered off. Try again after turning it on.',
    'デバイスの電源がオフです。電源を入れてから操作してください',
  );
  String get wifiLocalTip => pick(
    '当前设备状态：本地模式，请恢复设备网络再试',
    'The device is in local mode. Restore its network and try again.',
    'デバイスはローカルモードです。ネットワークを復旧してから再度お試しください',
  );
  String get wifiNotOnlineTip => pick('设备不在线', 'The device is not online', 'デバイスがオンラインではありません');
  String get wifiNoPickableDevice => pick(
    '暂无可投屏的电子纸设备',
    'No frame is available for casting',
    'キャストできるフォトフレームがありません',
  );
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
    '进度含图片上传与处理；发送后设备会自行下载并刷新屏幕，多张时只在最后一张刷屏',
    'Progress covers uploading and processing. After sending, the device downloads and refreshes the screen; with several photos it refreshes only on the last one.',
    '進捗にはアップロードと処理が含まれます。送信後、デバイスがダウンロードして画面を更新します。複数枚の場合は最後の1枚でのみ更新します',
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
    'SENT' => pick('已发送，屏幕即将刷新', 'Sent. The screen will refresh soon.', '送信しました。まもなく画面が更新されます'),
    'UPLOADED' => pick('已上传', 'Uploaded', 'アップロード済み'),
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

  // ── WiFi 投屏结果页（V1.4：写我的相册、同时加入轮播、投屏日志） ──
  String wifiCastAllSent(int total) => pick(
    '已发送 $total 张，屏幕即将刷新',
    '$total photos sent. The screen will refresh soon.',
    '$total 枚送信しました。まもなく画面が更新されます',
  );
  String get wifiCastSavingAlbum => pick('正在存入我的上传', 'Saving to My Uploads', 'マイアップロードに保存中');
  String wifiCastAlbumNotSaved(String text) =>
      pick('$text（未存入我的上传）', '$text (not saved to My Uploads)', '$text（マイアップロードに未保存）');
  String get wifiCarouselAddFailed => pick(
    '未成功加入轮播，请前往轮播设置添加',
    'Not added to the slideshow. Add it in Slideshow settings.',
    'スライドショーに追加できませんでした。スライドショー設定で追加してください',
  );
  String get wifiAddToCarousel => pick('同时加入轮播', 'Also add to slideshow', 'スライドショーにも追加');
  String get wifiCastLogTitle => pick('投屏日志', 'Cast log', 'キャストログ');
  String get wifiCopyLog => pick('复制日志', 'Copy log', 'ログをコピー');
  String get wifiLogEmpty => pick('（暂无）', '(empty)', '（なし）');
  String get wifiLogCopied => pick('已复制', 'Copied', 'コピーしました');

  // ── 我的相册：WiFi 版照片删除（V1.4 更新说明九、反馈追加内容第三节） ──
  String get wifiDeleteMayNeedSwitch => pick(
    '删除后相框可能需手动切换才会更新。',
    'The frame may need to be switched manually to update after deletion.',
    '削除後、フォトフレームの表示を更新するには手動で切り替える必要がある場合があります。',
  );
  String get wifiDeleteDoneMaySwitch => pick(
    '已删除；若相框未更新，请手动切换或重新设置轮播',
    'Deleted. If the frame does not update, switch manually or set up the slideshow again.',
    '削除しました。フォトフレームが更新されない場合は、手動で切り替えるかスライドショーを再設定してください',
  );
  String get wifiDeleteSwitched => pick(
    '已删除，相框已切换到下一张',
    'Deleted. The frame has switched to the next photo.',
    '削除しました。フォトフレームは次の写真に切り替わりました',
  );
  String get wifiDeleteOffline => pick(
    '已删除；设备离线，相框换图将在设备联网后进行',
    'Deleted. The device is offline; the frame will update once it is back online.',
    '削除しました。デバイスがオフラインのため、オンラインになってから表示を更新します',
  );
  String wifiDeletePartial(int deleted, int failed) => pick(
    '已删除 $deleted 张，$failed 张未删除成功，请稍后重试',
    '$deleted deleted, $failed failed. Please try again later.',
    '$deleted 枚削除、$failed 枚は削除できませんでした。しばらくしてからお試しください',
  );
  String wifiDeleteCloudFailed(String reason) => pick(
    '照片已从我的上传删除，相框播放列表更新失败：$reason',
    'Removed from My Uploads, but updating the frame playlist failed: $reason',
    'マイアップロードから削除しましたが、再生リストの更新に失敗しました：$reason',
  );
  String get wifiCloudDeleteFailed => pick('云端删除失败', 'Cloud deletion failed', 'クラウドでの削除に失敗しました');
  String get wifiDeleteFailed => pick('删除失败，请稍后重试', 'Deletion failed. Please try again later.', '削除に失敗しました。しばらくしてからお試しください');

  // ── 设置页通用 ──
  String get wifiSave => pick('保存', 'Save', '保存');
  String get wifiSaving => pick('保存中…', 'Saving…', '保存中…');
  String get wifiSaveFailed => pick('保存失败，请稍后重试', 'Save failed. Please try again later.', '保存に失敗しました。しばらくしてからお試しください');
  String wifiSaveFailedWith(String reason) => pick('保存失败：$reason', 'Save failed: $reason', '保存に失敗しました：$reason');
  String wifiLastSet(String time) => pick('最后设置 $time', 'Last set $time', '最終設定 $time');
  String wifiNextDay(String time) => pick('次日 $time', 'Next day $time', '翌日 $time');
  String wifiMinutes(int n) => pick('$n 分钟', '$n min', '$n 分');
  String wifiHours(int n) => pick('$n 小时', '$n h', '$n 時間');
  String wifiDays(int n) => pick('$n 天', '$n day${n == 1 ? '' : 's'}', '$n 日');
  String get wifiLoadFailed => pick('加载失败', 'Failed to load', '読み込みに失敗しました');
  String get wifiLoadFailedRetry => pick('加载失败，请稍后重试', 'Failed to load. Please try again later.', '読み込みに失敗しました。しばらくしてからお試しください');
  String get wifiReload => pick('重新加载', 'Reload', '再読み込み');
  String get wifiLoadingMore => pick('加载中…', 'Loading…', '読み込み中…');
  String get wifiLoadMoreFailed => pick('加载失败，点击重试', 'Failed to load. Tap to retry.', '読み込みに失敗しました。タップして再試行');
  String get wifiPullUpMore => pick('上拉加载更多', 'Scroll up to load more', '上にスクロールしてさらに読み込む');
  String get wifiNoMore => pick('没有更多了', 'No more', 'これ以上ありません');

  // ── 轮播设置（V1.4 更新说明 1.5 / 第五节、实现报告反馈六、反馈追加内容第一节） ──
  String get wifiSlideshowSettings => pick('轮播设置', 'Slideshow', 'スライドショー設定');
  String get wifiSlideState => pick('轮播状态', 'Slideshow status', 'スライドショーの状態');
  String get wifiSlideRunning => pick('轮播中', 'Playing', '再生中');
  String get wifiSlidePaused => pick('已暂停', 'Paused', '一時停止中');
  String get wifiSlideNotSet => pick('未设置', 'Not set', '未設定');
  String get wifiSlideMode => pick('轮播方式', 'Mode', '再生方式');
  String get wifiSlideInterval => pick('间隔时间', 'Interval', '間隔');
  String get wifiSlideFixed => pick('固定时间', 'Fixed times', '固定時刻');
  String get wifiSlideBegin => pick('开始时间', 'Start time', '開始時刻');
  String get wifiSlideEnd => pick('结束时间', 'End time', '終了時刻');
  String get wifiSlideEvery => pick('每隔', 'Every', '間隔');
  String wifiSlideEveryValue(String interval) => pick('$interval 换一张', 'Next photo every $interval', '$interval ごとに切り替え');
  String get wifiSlideUpdateTime => pick('更新时间', 'Update times', '更新時刻');
  String get wifiSlideAddTime => pick('+ 添加', '+ Add', '+ 追加');
  String get wifiSlideOrder => pick('播放顺序', 'Order', '再生順');
  String get wifiSlideSequential => pick('顺序播放', 'In order', '順番に再生');
  String get wifiSlideRandom => pick('随机播放', 'Shuffle', 'シャッフル再生');
  String get wifiSlideIdle => pick('轮播后休眠', 'Sleep after each change', '切り替え後にスリープ');
  String get wifiSlidePhotos => pick('轮播照片', 'Slideshow photos', 'スライドショーの写真');
  String get wifiSlideSelectAll => pick('全选', 'Select all', 'すべて選択');
  String get wifiSlideUnselectAll => pick('取消全选', 'Deselect all', '選択解除');
  String wifiSlidePhotosDesc(int max) => pick(
    '从「我的上传」选择，按选择顺序轮播；全选即轮播全部照片（含之后新上传的）。最多 $max 张',
    'Choose from My Uploads; photos play in the order selected. Select all to play every photo (including future uploads). Up to $max.',
    'マイアップロードから選択し、選んだ順に再生します。すべて選択すると今後のアップロードも含めて再生します。最大 $max 枚',
  );
  String wifiSlideSelectedCount(int count, int max) => pick('已选 $count/$max', 'Selected $count/$max', '選択中 $count/$max');
  String get wifiSlidePhotosFailed => pick('「我的上传」加载失败，请返回重试', 'Failed to load My Uploads. Go back and try again.', 'マイアップロードを読み込めませんでした。戻って再度お試しください');
  String get wifiSlidePhotosEmpty => pick('还没有可轮播的照片，先投屏几张吧', 'No photos to play yet. Cast a few first.', 'スライドショーにできる写真がありません。まず何枚かキャストしてください');
  String get wifiSlideQueryFailed => pick('轮播配置查询失败，以下为默认设置', 'Failed to load slideshow settings. Showing defaults.', 'スライドショー設定を取得できませんでした。既定値を表示しています');
  String get wifiSlideAllDeleted => pick('之前选择的照片已全部删除，请重新选择', 'All previously selected photos were deleted. Please choose again.', '以前選んだ写真はすべて削除されました。選び直してください');
  String get wifiSlideNotInAlbum => pick('之前选择的照片已不在「我的上传」中', 'Previously selected photos are no longer in My Uploads', '以前選んだ写真はマイアップロードにありません');
  String wifiSlideSomeDeleted(int n) => pick('之前选择的照片有 $n 张已删除', '$n previously selected photos were deleted', '以前選んだ写真のうち $n 枚が削除されました');
  String wifiSlideWholeAlbumOverLimit(int max) => pick(
    '当前轮播全部照片；最多选择 $max 张，已选前 $max 张，保存后只轮播所选',
    'Currently playing all photos. Up to $max can be selected, so the first $max are selected; after saving only these will play.',
    '現在すべての写真を再生中です。選択は最大 $max 枚のため先頭 $max 枚を選択しました。保存後は選択した写真のみ再生します',
  );
  String wifiSlideFull(int max) => pick(
    '最多选择 $max 张，请先取消部分照片',
    'Up to $max photos. Deselect some first.',
    '最大 $max 枚です。先にいくつか選択を解除してください',
  );
  String wifiSlideMax(int max) => pick('最多选择 $max 张', 'Up to $max photos', '最大 $max 枚まで');
  String wifiSlideOverLimit(int max) => wifiSlideFull(max);
  String wifiSlideSaveOverLimit(int max) => pick(
    '轮播照片最多 $max 张，请先取消部分照片后再保存',
    'The slideshow allows up to $max photos. Deselect some and save again.',
    'スライドショーは最大 $max 枚です。いくつか選択を解除してから保存してください',
  );
  String get wifiSlideSaveInvalid => pick('保存失败：轮播设置有误，请检查后重试', 'Save failed: the slideshow settings are invalid. Please check and try again.', '保存に失敗しました：設定に誤りがあります。確認して再度お試しください');
  String get wifiSlideNeedTimes => pick('请选择轮播开始和结束时间', 'Choose the start and end times', '開始時刻と終了時刻を選択してください');
  String get wifiSlideNeedInterval => pick('请选择轮播间隔', 'Choose an interval', '間隔を選択してください');
  String get wifiSlideDaysRange => pick('每隔天数需在 1~365 之间', 'Days must be between 1 and 365', '日数は1〜365の範囲で指定してください');
  String get wifiSlideNeedTimePoint => pick('请至少添加一个更新时间', 'Add at least one update time', '更新時刻を1つ以上追加してください');
  String get wifiSlideNeedPhoto => pick('请至少选择一张照片', 'Select at least one photo', '写真を1枚以上選択してください');
  String get wifiSlideTimeExists => pick('这个时间点已添加', 'This time has already been added', 'この時刻は追加済みです');
  String wifiSlideTimeMax(int max) => pick('最多添加 $max 个时间点', 'Up to $max times', '最大 $max 個まで追加できます');
  String get wifiSlideSaveStart => pick('保存并开始轮播', 'Save and start', '保存して開始');
  String get wifiSlideStop => pick('暂停轮播', 'Pause slideshow', 'スライドショーを一時停止');
  String get wifiSlideStopping => pick('暂停中…', 'Pausing…', '一時停止中…');
  String get wifiSlideStopped => pick('已暂停轮播', 'Slideshow paused', 'スライドショーを一時停止しました');
  String get wifiSlideStopFailed => pick('暂停失败，请稍后重试', 'Failed to pause. Please try again later.', '一時停止に失敗しました。しばらくしてからお試しください');
  String get wifiSlideSwitching => pick('正在切到第一张…', 'Switching to the first photo…', '最初の写真に切り替え中…');
  String wifiSlideSavedSome(int n) => pick('已保存，轮播所选 $n 张', 'Saved. Playing $n selected photos', '保存しました。選択した $n 枚を再生します');
  String get wifiSlideSavedAll => pick('已保存，轮播全部照片', 'Saved. Playing all photos', '保存しました。すべての写真を再生します');
  String wifiSlideSavedPlaying(String saved) => pick('$saved，屏幕即将切到第一张', '$saved. The screen will switch to the first photo.', '$saved。まもなく最初の写真に切り替わります');
  String get wifiSlideFirstNoImage => pick('第一张照片缺少原图，等下一个轮播周期再切换', 'The first photo has no original image; it will switch at the next cycle', '最初の写真に元画像がないため、次の周期で切り替わります');
  String get wifiSlideFirstDownloadFailed => pick('第一张照片下载失败，等下一个轮播周期再切换', 'Failed to download the first photo; it will switch at the next cycle', '最初の写真をダウンロードできなかったため、次の周期で切り替わります');
  String wifiSlideFirstFailed(String reason) => pick('切换第一张失败：$reason', 'Failed to switch to the first photo: $reason', '最初の写真への切り替えに失敗しました：$reason');

  // ── 休眠设置（实现报告反馈第二节） ──
  String get wifiSleepSettings => pick('休眠设置', 'Sleep settings', 'スリープ設定');
  String get wifiSleepCurrent => pick('当前设置', 'Current setting', '現在の設定');
  String get wifiSleepNotSet => pick('未开启休眠', 'Sleep is not enabled', 'スリープは未設定です');
  String get wifiSleepClosed => pick('已关闭休眠', 'Sleep is off', 'スリープはオフです');
  String get wifiSleepQueryFailed => pick('当前设置查询失败', 'Failed to load the current setting', '現在の設定を取得できませんでした');
  String wifiSleepDailySummary(String sleep, String wake, bool crossDay) => pick(
    '周期休眠：每天 $sleep ~ ${crossDay ? '次日 ' : ''}$wake',
    'Daily sleep: $sleep – ${crossDay ? 'next day ' : ''}$wake',
    '毎日スリープ：$sleep 〜 ${crossDay ? '翌日 ' : ''}$wake',
  );
  String wifiSleepOnceSummary(String begin, String end) =>
      pick('一次性休眠：$begin ~ $end', 'One-time sleep: $begin – $end', '1回のみスリープ：$begin 〜 $end');
  String get wifiSleepMode => pick('休眠方式', 'Sleep mode', 'スリープ方式');
  String get wifiSleepModeOff => pick('关闭', 'Off', 'オフ');
  String get wifiSleepModeDaily => pick('周期', 'Daily', '毎日');
  String get wifiSleepModeOnce => pick('一次性', 'One-time', '1回のみ');
  String get wifiSleepDailySleep => pick('每天休眠', 'Sleep at', 'スリープ時刻');
  String get wifiSleepDailyWake => pick('每天唤醒', 'Wake at', '起動時刻');
  String get wifiSleepCrossDayTip => pick(
    '唤醒时间早于休眠时间时按次日唤醒（跨午夜）',
    'If the wake time is earlier than the sleep time, it wakes the next day (past midnight).',
    '起動時刻がスリープ時刻より早い場合は翌日に起動します（日付をまたぐ）',
  );
  String get wifiSleepBegin => pick('开始', 'Start', '開始');
  String get wifiSleepEnd => pick('结束', 'End', '終了');
  String get wifiSleepOnceTip => pick('只休眠这一次，开始时间需早于结束时间', 'Sleeps just once; the start must be earlier than the end.', 'この1回だけスリープします。開始は終了より前にしてください');
  String get wifiSleepOffTip => pick('关闭后设备保持联网，不按计划休眠', 'When off, the device stays online and does not sleep on a schedule.', 'オフの場合、デバイスはオンラインのままでスケジュールによるスリープは行いません');
  String get wifiSleepNote => pick('设置时设备需要在线；时间按手机本地时间填写', 'The device must be online. Times use your phone’s local time.', '設定時はデバイスがオンラインである必要があります。時刻はスマートフォンの現地時間です');
  String get wifiSleepNeedTimes => pick('请选择休眠时间和唤醒时间', 'Choose the sleep and wake times', 'スリープ時刻と起動時刻を選択してください');
  String get wifiSleepSameTime => pick('休眠时间和唤醒时间不能相同', 'The sleep and wake times cannot be the same', 'スリープ時刻と起動時刻を同じにすることはできません');
  String get wifiSleepNeedDateTimes => pick('请选择开始和结束的日期与时间', 'Choose the start and end dates and times', '開始と終了の日付・時刻を選択してください');
  String get wifiSleepBeginBeforeEnd => pick('开始时间必须早于结束时间', 'The start must be earlier than the end', '開始は終了より前にしてください');
  String get wifiSleepEndPassed => pick('结束时间已过，请重新选择', 'The end time has passed. Please choose again.', '終了時刻を過ぎています。選び直してください');
  String get wifiSleepCloseTitle => pick('关闭休眠', 'Turn off sleep', 'スリープをオフ');
  String get wifiSleepCloseConfirm => pick(
    '关闭后设备将保持联网，不再按计划休眠，确认关闭吗？',
    'The device will stay online and stop sleeping on a schedule. Turn it off?',
    'オフにするとデバイスはオンラインのままになり、スケジュールによるスリープを行いません。オフにしますか？',
  );
  String get wifiSleepClosedToast => pick('已关闭休眠', 'Sleep turned off', 'スリープをオフにしました');
  String get wifiSleepSaved => pick('休眠设置已保存', 'Sleep settings saved', 'スリープ設定を保存しました');

  // ── 消息中心（实现报告反馈第三节、对接文档第八节） ──
  String get wifiMessageCenter => pick('消息中心', 'Messages', 'メッセージ');
  String get wifiMsgUnreadOnly => pick('只看未读', 'Unread only', '未読のみ');
  String wifiMsgReadAll(int unread) => pick(
    unread > 0 ? '全部已读（$unread）' : '全部已读',
    unread > 0 ? 'Mark all read ($unread)' : 'Mark all read',
    unread > 0 ? 'すべて既読（$unread）' : 'すべて既読',
  );
  String get wifiMsgAllRead => pick('已全部标记为已读', 'All marked as read', 'すべて既読にしました');
  String get wifiMsgEmpty => pick('暂无消息', 'No messages', 'メッセージはありません');
  String get wifiMsgNoUnread => pick('没有未读消息', 'No unread messages', '未読メッセージはありません');
  String get wifiMsgEmptyDesc => pick(
    '设备上下线、电量、投屏结果等消息会出现在这里（保留 90 天）',
    'Messages about the device going online/offline, battery, cast results, etc. appear here (kept for 90 days).',
    'デバイスのオンライン/オフライン、バッテリー、キャスト結果などのメッセージがここに表示されます（90日間保存）',
  );
  String get wifiMsgNoPermission => pick('没有查看该设备消息的权限', 'No permission to view this device’s messages', 'このデバイスのメッセージを表示する権限がありません');
  String get wifiMsgSeparator => pick('，', ', ', '、');
  String wifiMsgSignalLevel(String level) => pick('信号等级 $level', 'Signal level $level', '信号レベル $level');
  String wifiMsgBatteryLevel(String level) => pick('电量等级 $level', 'Battery level $level', 'バッテリーレベル $level');
  String wifiMsgBattery(String battery) => pick('电量 $battery%', 'Battery $battery%', 'バッテリー $battery%');
  String wifiMsgRssi(String rssi) => pick('信号 ${rssi}dBm', 'Signal ${rssi}dBm', '信号 ${rssi}dBm');
  String wifiMsgResultCode(String code) => pick('设备返回码 $code', 'Device code $code', 'デバイスの応答コード $code');
  String get wifiMsgCorrected => pick('设备超时后才返回成功', 'The device reported success after the timeout', 'タイムアウト後にデバイスが成功を報告しました');

  /// 消息标题（服务端只给短码 type，文案由 App 维护）；未知 type 显示通用文案。
  String wifiMessageTitle(String type) => switch (type) {
    'DEVICE_ONLINE' => pick('设备已上线', 'Device online', 'デバイスがオンラインになりました'),
    'DEVICE_OFFLINE' => pick('设备已离线', 'Device offline', 'デバイスがオフラインになりました'),
    'LOW_BATTERY' => pick('设备电量低', 'Low battery', 'バッテリー残量低下'),
    'WIFI_WEAK' => pick('设备 WiFi 信号弱', 'Weak Wi-Fi signal', 'Wi-Fi信号が弱い'),
    'TF_FULL' => pick('TF 卡容量将满', 'TF card almost full', 'TFカードの容量がまもなくいっぱいです'),
    'TF_LOCAL_MODE' => pick('设备已进入本地模式', 'Device entered local mode', 'デバイスがローカルモードになりました'),
    'PLAY_SUCCESS' => pick('投屏成功', 'Cast succeeded', 'キャスト成功'),
    'PLAY_DOWNLOAD_FAILED' => pick('投屏失败：设备下载图片失败', 'Cast failed: the device could not download the image', 'キャスト失敗：デバイスが画像をダウンロードできませんでした'),
    'PLAY_STORAGE_ERROR' => pick('投屏失败：设备存储异常', 'Cast failed: device storage error', 'キャスト失敗：デバイスのストレージエラー'),
    'PLAY_FAILED' => pick('投屏失败', 'Cast failed', 'キャスト失敗'),
    'EXCEPTION_UP_PARSE' => pick('设备上报数据解析失败', 'Failed to parse device data', 'デバイスのデータを解析できませんでした'),
    'EXCEPTION_UNKNOWN_ACTION' => pick('设备上报了未知指令', 'The device reported an unknown command', 'デバイスが不明なコマンドを報告しました'),
    'EXCEPTION_COMMAND_BUILD' => pick('平台下发指令构造失败', 'Failed to build the command', 'コマンドの作成に失敗しました'),
    _ => pick(
      type.isNotEmpty ? '设备消息（$type）' : '设备消息',
      type.isNotEmpty ? 'Device message ($type)' : 'Device message',
      type.isNotEmpty ? 'デバイスメッセージ（$type）' : 'デバイスメッセージ',
    ),
  };

  String wifiMessageCategory(String category) => switch (category) {
    'DEVICE' => pick('设备', 'Device', 'デバイス'),
    'ALARM' => pick('告警', 'Alert', 'アラート'),
    'EXCEPTION' => pick('异常', 'Error', '異常'),
    'BUSINESS' => pick('业务', 'Activity', '利用'),
    _ => pick('消息', 'Message', 'メッセージ'),
  };

  // ── WiFi 设备详情改版（2026-10-29）：功能栏、设备信息、解绑 / 删除 ──
  String get wifiDeviceInfo => pick('设备信息', 'Device info', 'デバイス情報');
  String get wifiShareDevice => pick('分享设备', 'Share device', 'デバイスを共有');
  String get wifiUnbindMessage => pick(
    '解除绑定后，照片将保留，您可以稍后重新绑定电子纸设备。',
    'After unbinding, your photos are kept and you can bind the frame again later.',
    'バインド解除後も写真は保持され、後でフォトフレームを再バインドできます。',
  );
  String get wifiDeleteDeviceMessage => pick(
    '删除设备将清空该设备的云端照片及小程序/APP内的照片，防止隐私泄露；已分享的成员也将同时失去这台设备及其照片。是否确认删除设备？',
    "Deleting the device clears its cloud photos and the photos in the mini program/app to protect your privacy. Members you shared it with also lose the device and its photos. Delete the device?",
    'デバイスを削除すると、プライバシー保護のためクラウドとミニプログラム/アプリ内の写真が消去されます。共有したメンバーもこのデバイスと写真を利用できなくなります。削除しますか？',
  );
  String wifiCloudDeleteFailed(String reason) => pick(
    '云端照片删除失败：$reason',
    'Failed to delete cloud photos: $reason',
    'クラウドの写真を削除できませんでした：$reason',
  );

  // ── TF 卡设置（2026-10-29） ──
  String get wifiTfSettingsTitle => pick('TF卡设置', 'TF card settings', 'TFカード設定');
  String get wifiTfCapacity => pick('TF卡容量', 'TF card storage', 'TFカード容量');
  String get wifiTfPlay => pick('TF卡播放', 'Play from TF card', 'TFカード再生');
  String get wifiTfTip => pick(
    '开启后设备将进入本地模式，无法进行APP投屏和取消本地模式，如需恢复请将设备重新入网。',
    'Once enabled, the device enters local mode: you cannot cast from the app or turn local mode off here. To restore it, set up the device network again.',
    '有効にするとデバイスはローカルモードになり、アプリからのキャストやローカルモードの解除はできません。復旧するにはデバイスのネットワークを再設定してください。',
  );
  String get wifiTfConfirmTitle => pick('开启TF卡播放', 'Play from TF card', 'TFカード再生を有効にする');
  String get wifiTfConfirmMessage => pick(
    '开启后设备将断开网络进入本地模式，无法进行APP投屏，也无法在APP取消本地模式；如需恢复，请在设备上重新入网。确认开启？',
    'The device will disconnect and enter local mode. You cannot cast from the app or turn local mode off in the app; to restore, set up the network on the device again. Enable it?',
    'デバイスはネットワークから切断されローカルモードになります。アプリからのキャストやアプリでの解除はできません。復旧するにはデバイスでネットワークを再設定してください。有効にしますか？',
  );
  String get wifiTfOpen => pick('开启', 'Enable', '有効にする');
  String get wifiTfChecking => pick('检查设备', 'Checking device', 'デバイスを確認中');
  String get wifiTfSwitching => pick('切换中', 'Switching', '切り替え中');
  String get wifiTfNoCard => pick('设备未插TF卡，无法开启', 'No TF card in the device', 'TFカードが挿入されていないため有効にできません');
  String get wifiTfUnknownCard => pick('未检测到TF卡，请稍后重试', 'No TF card detected. Please try again later.', 'TFカードを検出できません。しばらくしてからお試しください');
  String get wifiTfNotOnline => pick('设备不在线，无法开启', 'The device is not online', 'デバイスがオンラインでないため有効にできません');
  String get wifiTfUpgrading => pick('设备升级中，请稍后', 'The device is upgrading. Please wait.', 'デバイスはアップグレード中です。しばらくお待ちください');
  String get wifiTfNoPermission => pick('无该设备操作权限', 'No permission for this device', 'このデバイスを操作する権限がありません');
  String get wifiTfOpenFailed => pick('开启失败，请稍后重试', 'Failed to enable. Please try again later.', '有効にできませんでした。しばらくしてからお試しください');
  String get wifiTfAccepted => pick('设备已切换，即将进入本地模式', 'Switched. The device is entering local mode.', '切り替えました。まもなくローカルモードになります');
  String wifiTfRejected(Object? result) => pick('设备拒绝切换（result=$result）', 'The device refused (result=$result)', 'デバイスが拒否しました（result=$result）');
  String get wifiTfNoResponse => pick('设备未响应，请稍后重试', 'The device did not respond. Please try again later.', 'デバイスが応答しません。しばらくしてからお試しください');
  String get wifiTfRestoreHint => pick(
    '如需恢复联网，请在设备上重新入网',
    'To go back online, set up the network on the device again',
    'オンラインに戻すには、デバイスでネットワークを再設定してください',
  );

  // ── 分享设备（2026-10-29，简化版：微信小程序卡片） ──
  String get wifiShareOwner => pick('所有者', 'Owner', 'オーナー');
  String get wifiShareShared => pick('已分享', 'Shared with', '共有中');
  String get wifiShareEmpty => pick('暂未分享给其他人', 'Not shared with anyone yet', 'まだ誰とも共有していません');
  String wifiShareJoinedAt(String time) => pick('加入时间 $time', 'Joined $time', '参加日時 $time');
  String get wifiShareRemove => pick('移除', 'Remove', '削除');
  String get wifiShareRemoveTitle => pick('移除成员', 'Remove member', 'メンバーを削除');
  String wifiShareRemoveMessage(String name) => pick(
    '移除后「$name」将不能再使用这台设备，确认移除？',
    '"$name" will no longer be able to use this device. Remove?',
    '「$name」はこのデバイスを使用できなくなります。削除しますか？',
  );
  String get wifiShareRemoved => pick('已移除', 'Removed', '削除しました');
  String get wifiShareRemoving => pick('移除中', 'Removing', '削除中');
  String get wifiShareUnavailable => pick('暂时无法分享，请稍后重试', 'Sharing is not available right now. Please try again later.', '現在共有できません。しばらくしてからお試しください');
  String get wifiShareTip => pick(
    '通过微信发送给对方，对方在小程序中确认后即可共用这台设备',
    'Send it via WeChat. Once they accept in the mini program, they can use this device too.',
    'WeChatで送信し、相手がミニプログラムで承認するとこのデバイスを共用できます',
  );
  String wifiShareCardTitle(String owner, String device) => pick(
    '${owner.isNotEmpty ? owner : '好友'}邀请你共用电子纸设备「$device」',
    '${owner.isNotEmpty ? owner : 'A friend'} invited you to share the frame "$device"',
    '${owner.isNotEmpty ? owner : '友だち'}がフォトフレーム「$device」の共用に招待しています',
  );
  String get wifiShareNoWeChat => pick('请先安装微信', 'Please install WeChat first', '先にWeChatをインストールしてください');
  String get wifiShareFailed => pick('分享失败，请稍后重试', 'Sharing failed. Please try again later.', '共有に失敗しました。しばらくしてからお試しください');
}
