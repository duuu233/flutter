import 'dart:async';

import 'package:flutter/material.dart';

import 'device/ble_controller.dart';
import 'device/ble/ble_direct_connect_cache.dart';
// FrameBleException：删除链路要按**结果码**判断良性失败（0x05/0x07），不再匹配中文文案。
import 'device/ble/device_ble.dart' show FrameBleException;
import 'device/ble/frame_protocol.dart';
import 'device/battery_cache.dart';
import 'device/device_identity_registry.dart';
import 'device/device_interaction_trace.dart';
import 'device/frame_device_protocol.dart';
import 'device/recently_bound_device.dart';
import 'device/serial_match.dart';
import 'features/ai/ai_last_session.dart';
import 'features/ai/ai_token.dart';
import 'features/cast/cast_upload_limit.dart';
import 'network/api_exception.dart';
import 'network/api_rows.dart';
import 'network/api_session.dart';
import 'network/boltfox_api.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'shared/ai_service_consent.dart';
import 'shared/display_text.dart';
import 'shared/image_cache_cleanup.dart';
import 'shared/l10n/chinese_script.dart';

enum AppLanguage { zh, zhHant, en, ja }

enum PermissionKind { location, bluetooth, album, camera }

enum DeviceRole { owner, user }

enum ImageSourceType { camera, album }

/// 「固件升级」这一行的版本比对结论（2026-08-12 同步小程序 `evaluateFirmwareUpdate`）。
///
/// 改动前详情页右侧显示的是**版本号本身**（`newVersionNo` 或设备当前版本）——一个是云端最新、
/// 一个是设备当前，用户看到一个数字却无从判断该不该升级。现在给结论。
enum FirmwareUpdateVerdict {
  /// 设备实测版本 ≠ 云端最新版本，且升级包可用 → 「有版本可更新」。
  update,

  /// 版本相同，或后端根本没给 `newVersionNo` → 「已是最新版本」。
  latest,

  /// 版本不同但缺号/缺地址/不是 `.bin` → 对用户仍说「已是最新版本」，点进去才如实说明原因。
  invalid,

  /// 读不到设备当前固件版本（未连接 / `0x03` 失败）→ 显示 `--`。
  ///
  /// ⚠️ **绝不能在这里说「已是最新版本」**：那是在不知情时给用户一个可能是假的结论，
  /// 而这恰恰是最危险的一种假值 —— 用户会因此**不去升级**。
  unknown,
}

enum CastStatus { success, failed }

class ActionFeedback {
  const ActionFeedback({
    required this.success,
    required this.message,
    this.warn = false,
    this.diagnostics,
  });

  final bool success;
  final String message;

  /// 排查期附带的技术现场（当前仅微信登录用：本次实际发出的请求方法/URL/参数）。
  /// **不是**面向用户的文案，也不跟随语种；由调用页决定是否展示（见
  /// `auth_page._withDiagnostics`，受 `kWeChatLoginDiagnostics` 开关控制）。
  final String? diagnostics;

  /// 「成功了，但结果不理想」——如照片已在设备侧异常、刷屏失败。
  /// 调用方据此用 `AppToast.warn` 而不是普通 toast（对齐两端 toast 语义约定）。
  final bool warn;
}

/// App 版本检查结果（见 [PhotoFrameState.checkAppVersion]）。
class AppVersionInfo {
  const AppVersionInfo({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.description,
    this.compulsory = 0,
  });

  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final String description;

  /// 升级类型（swagger `AppVersionConApiOutput.compulsory`）：
  /// 1=强制升级 2=强提示升级 3=弱提示升级 4=不提示升级。
  final int compulsory;

  /// 是否必须马上升级：**必须同时有新版本**才成立。
  /// 只看 compulsory 是不够的——后端即使把版本配成强制类型，`isUpdate=0`（当前
  /// 已是最新）时也不该把用户锁在升级弹窗里。
  bool get isCompulsory => hasUpdate && compulsory == 1;
}

class UserProfile {
  UserProfile({
    required this.id,
    required this.nickname,
    required this.email,
    required this.avatarColor,
    required this.signature,
  });

  String id;
  String nickname;
  String email;
  Color avatarColor;
  String signature;

  /// 后端头像地址（登录后 getUserInfo 下发）；空则用本地默认头像。
  String avatarUrl = '';

  /// 后端统计的图片数 / 设备数（`UserInfoApiOut.imgCount` / `productCount`）。
  /// 「我的」页优先展示它们，未下发（0）时才回退本地列表长度，对齐小程序 mine.js。
  int imgCount = 0;
  int productCount = 0;

  /// 登录 / `getUserInfo` 出参新增的可用星币数（后端字段名仍是 `availableToken`，String）。
  ///
  /// ⚠️ **`null` 与 `0` 必须分开**：`null` = 这次响应没带这个字段（老后端灰度期），
  /// `0` = 余额真的是 0。混为一谈的后果是二选一的错——要么白多打一次 `getUserAccount`，
  /// 要么把 0 显示成上次的旧余额。AI 侧据此「先显示登录带回的值 → 再异步刷权威值」。
  int? availableToken;
}

class DeviceItem {
  DeviceItem({
    required this.id,
    required this.name,
    required this.kind,
    required this.screenType,
    required this.batteryLevel,
    required this.charging,
    required this.connected,
    required this.role,
    required this.serialNumber,
    required this.hardwareVersion,
    required this.firmwareVersion,
    required this.imageMask,
    required this.currentImageIndex,
    required this.playbackMode,
    required this.carouselIntervalSeconds,
    required this.carouselEnabled,
    this.screenWidth = 0,
    this.screenHeight = 0,
    this.verticalRotation = 0,
    this.isUpdate = 0,
    this.newVersionNo = '',
    this.downloadPath = '',
    this.firmwareSize = 0,
    this.isPlaceholder = false,
    this.batteryUpdatedAt,
  });

  /// 是否 `_findDevice` 兜底生成的占位设备（id 已不在列表）。
  /// 占位设备仅用于让当前帧安全渲染；破坏性/写后端的操作（清空、改名、轮播设置）
  /// 执行前应检查此标记并中止，防止对着一台已删除/已解绑的设备发真实请求。
  final bool isPlaceholder;

  final String id;
  String name;
  String kind;
  FrameScreenType screenType;
  int batteryLevel;

  /// 最近一次 0x04 返回有效电量的时间。null 表示从未成功读取，页面显示 `--`。
  ///
  /// 不能用 [batteryLevel] 是否大于 0 判断：真机 0% 是合法值。
  DateTime? batteryUpdatedAt;

  bool get hasBatteryReading =>
      batteryUpdatedAt != null && batteryLevel >= 0 && batteryLevel <= 100;

  String get batteryLabel => hasBatteryReading ? '$batteryLevel%' : '--';

  bool charging;
  bool connected;
  DeviceRole role;
  String serialNumber;
  String hardwareVersion;
  String firmwareVersion;
  int imageMask;
  int currentImageIndex;
  FramePlaybackMode playbackMode;
  int carouselIntervalSeconds;
  bool carouselEnabled;

  // ── 屏幕物理像素（后端记录 `width`/`height` 原样保留，0=未下发）─────────────
  /// 详情页「分辨率」在**未连接**时的取值来源。
  ///
  /// 为什么不直接用 [screenType] 反查 `FrameProtocol.screenTypes`：[_screenTypeFromSize] 在后端
  /// 没下发尺寸时会**回落 5.89 寸**，反查就会显示一个臆造的 `680*960`。原始宽高为 0 就老实显示 `--`。
  int screenWidth;
  int screenHeight;

  /// **竖向**构图导出时整幅画面的顺时针旋转角（度）。后端设备字段 `verticalRotation`
  /// （2026-08-04 新增），投屏预览页据此旋转上传给抖动接口、随后图传到设备的成品图。
  ///
  /// **未下发 / 非法值一律 0，即不旋转**——这是产品口径，不要改成 180 之类的「历史默认角」。
  /// ⚠️ 0 是合法值（设备明确要求不旋转），判空只能判 null/空串，绝不能用真假值。
  ///
  /// 横向构图的旋转角是另一个字段（`rotationDegree`），当前 App 侧仍写死 270°
  /// （见 `cast_preview_page.dart` 的 `_kLandscapeExportRotateDeg`），与小程序尚未对齐。
  final int verticalRotation;

  // ── 连接后由真机 0x01(readDeviceInfo) 回填的实时内存（对齐小程序 applyConnectedDevice
  //    的 usedMemory/totalMemory）。真机容量最多 95 槽，超出 int 位掩码(最多 32)的表示范围，
  //    故直接采用真机上报的计数/容量，而非从 [imageMask] 派生。断开后由页面按 connected 显示 --。
  /// 真机上报的已用图片数（未连接/未同步为 null，回退 [imageMask] 派生）。
  int? liveImageCount;

  /// 真机上报的图片容量上限（未连接/未同步为 null，回退常量 [FrameProtocolConfig.maxImages]）。
  int? liveCapacity;

  // ── OTA 固件更新信息（后端设备详情下发，见 getUserProductDetail）──────────
  /// 后端「可更新」标记：1=有可用更新。
  int isUpdate;

  /// 后端下发的最新固件版本号。
  String newVersionNo;

  /// 后端固件包下载地址（.bin）。
  String downloadPath;

  /// 后端固件包字节数（0=未知，下载后确认）。
  int firmwareSize;

  /// 是否存在有效可升级包（有更新标记 + 版本号 + .bin 下载地址）。
  bool get hasFirmwareUpdate => isUpdate == 1 && hasValidFirmwarePackage;

  /// 包本身是否可用（版本号 + 有效 `.bin` 地址），**不看后端的 `isUpdate` 标记**。
  /// 版本比对结论（[evaluateFirmwareUpdate]）用它：设备实测版本与 `newVersionNo` 不同时，
  /// 能不能升级取决于包在不在，而不取决于后端那个可能已过期的标记。
  bool get hasValidFirmwarePackage =>
      newVersionNo.isNotEmpty &&
      downloadPath.isNotEmpty &&
      RegExp(r'\.bin(?:[?#]|$)', caseSensitive: false).hasMatch(downloadPath);

  int get capacity => liveCapacity ?? FrameProtocolConfig.maxImages;

  int get imageCount =>
      liveImageCount ?? FrameDeviceProtocol.countImages(imageMask);

  int get storageFreeBytes =>
      FrameDeviceProtocol.estimateStorageFreeBytes(imageMask, screenType);

  String get maskLabel => FrameDeviceProtocol.maskHex(imageMask);

  FrameDeviceInfoSnapshot toSnapshot() {
    return FrameDeviceProtocol.readDeviceInfo(
      deviceId: id,
      hardwareVersion: hardwareVersion,
      firmwareVersion: firmwareVersion,
      imageMask: imageMask,
      batteryLevel: batteryLevel,
      charging: charging,
      playbackMode: playbackMode,
      intervalSeconds: carouselIntervalSeconds,
      screenType: screenType,
      currentImageIndex: currentImageIndex,
    );
  }
}

/// 版本号是否一致：去空格 + 不区分大小写；任一为空**不**视为一致
/// （避免「未知版本」被误判成已是最新）。与小程序 `sameVersion` 同口径。
bool sameFirmwareVersion(String a, String b) {
  final left = a.trim().toUpperCase();
  final right = b.trim().toUpperCase();
  return left.isNotEmpty && right.isNotEmpty && left == right;
}

/// 「固件升级」行右侧文案与点击流程**共用**的一处判定（2026-08-12 同步小程序）。
///
/// 判据是**设备实际在跑的固件版本**（BLE `0x03 GET_SW_VER`，连接后由 `readDeviceInfo` 回填到
/// [DeviceItem.firmwareVersion]）与接口 `newVersionNo` 的比较，而不是后端的 `isUpdate` 标记 ——
/// 两处若各判各的，就会出现「详情说有版本可更新、升级页却说已是最新」，用户永远升不了级。
///
/// [currentVersion] 显式传入时优先（OTA 页会用当前会话 BLE 实读的那份）。
/// 读不到设备版本时返回 [FirmwareUpdateVerdict.unknown]，调用方可退回后端 `isUpdate` 标志，
/// 以保住「不连蓝牙也能查版本」的能力。
FirmwareUpdateVerdict evaluateFirmwareUpdate(
  DeviceItem device, {
  String currentVersion = '',
}) {
  final current = (currentVersion.isNotEmpty ? currentVersion : device.firmwareVersion)
      .trim();
  if (current.isEmpty) {
    return FirmwareUpdateVerdict.unknown;
  }
  final latest = device.newVersionNo.trim();
  if (latest.isEmpty || sameFirmwareVersion(current, latest)) {
    return FirmwareUpdateVerdict.latest;
  }
  return device.hasValidFirmwarePackage
      ? FirmwareUpdateVerdict.update
      : FirmwareUpdateVerdict.invalid;
}

// 2026-08-17 删除：`AlbumPhoto`（「我的图库」列表项，来自 `getUserProductImgList`）。
// 端上已经没有任何页面渲染或读取图库列表——「我的相册」铺的是**投屏成功记录**（[CastRecord]），
// 删除只认记录自己的 `imgIndex`（2026-08-10 起），再次投屏直接用记录自己的 `img`
// （2026-07-22 起 setUserProductUpload 上传的就是原图）。图库照片的清理归后端。
// 对齐小程序 2026-08-17 同名清理，勿再接回来。

class CastRecord {
  CastRecord({
    required this.id,
    required this.title,
    required this.deviceId,
    required this.ownerUserId,
    required this.status,
    required this.source,
    required this.color,
    required this.width,
    required this.height,
    required this.message,
    required this.createdAt,
    this.imageIndex,
    this.command,
    this.resultCode,
    this.imageMask,
    this.imageUrl,
    this.thumbUrl,
    this.imgBle,
    this.deviceName = '',
  });

  final String id;
  final String title;
  final String deviceId;
  final String ownerUserId;
  final CastStatus status;
  final ImageSourceType source;
  final Color color;
  final double width;
  final double height;
  final String message;
  final DateTime createdAt;
  final int? imageIndex;
  final int? command;
  final FrameProtocolResultCode? resultCode;
  final int? imageMask;

  // 2026-08-17 删除：`photoId`（后端 `uProductImgId`，记录 ↔ 图库照片的关联键）。
  // 它只喂过「按记录找图库原图」和「按图库照片解析设备槽位」两处，两处都已改成直接吃
  // 记录自己的 `img` / `imgIndex`（见 [PhotoFrameState.resolveDeleteSlots]）。

  /// 后端投屏图片地址（来自 `getUserProductImgRecordList.img`，原图）；为空时回退占位色块。
  /// 再次投屏会下载它到本地重新裁剪（见 cast_management 的 recastImgUrl）。
  final String? imageUrl;

  /// 记录列表缩略图地址（来自 `getUserProductImgRecordList.imgThumb`，无则回退 `img`）。
  /// 对齐小程序 records.wxml 的 `item.imgThumb`：列表只加载缩略图。
  final String? thumbUrl;

  /// 后端转换好的设备帧文件地址(.bin，来自 `getUserProductImgRecordList` 的 imgBle)。
  /// 再次/重新投屏时直接下载它走 BLE 图传，不再走后端上传/转码；为空则该记录无法直接再次投屏。
  final String? imgBle;

  /// 投屏目标设备名（`getUserProductImgRecordList.productName`）。后端逐行下发，
  /// 记录页直接用它（对齐小程序 records.wxml 的 `item.deviceName`），
  /// 不再按 deviceId 反查设备列表——设备列表未加载时会退化成显示原始 id。
  final String deviceName;
}

/// 常见问题（操作指南）条目。[answer] 可懒加载（列表只给标题、展开时再取详情）。
class FaqArticle {
  FaqArticle({required this.id, required this.question, this.answer = ''});

  final String id;
  final String question;
  String answer;
}

/// 待删槽位按设备真实 IMG_MASK 分拨后的结果，见 [PhotoFrameState.splitSlotsByDeviceMask]。
class DeleteSlotSplit {
  const DeleteSlotSplit({required this.onDevice, required this.gone});

  /// 设备上确实还有图 → 进 `0x12` 的 IMG_INDEX_MASK。
  final List<int> onDevice;

  /// 设备上已经没有（另一端删过）→ 设备侧跳过，只删后端记录。
  final List<int> gone;
}

/// 「我的相册」删除**设备侧那一半**的结果（2026-08-20 两半互不阻断）。
///
/// 改前设备侧一失败就整批中止、后端记录一条都不删；现在产品口径改为：先发设备删除指令(0x12)，
/// 无论成败都继续删投屏记录，两半的结果最后合并成一条提示（见 `gallery_page._confirmDelete`）。
/// 所以这里不再用 [ActionFeedback] —— 那个只有「成功/失败」两态，表达不了「设备没删掉但记录删了」。
class DevicePhotoDeleteOutcome {
  const DevicePhotoDeleteOutcome({
    this.blockedMessage = '',
    this.deviceError = '',
    this.refreshWarn = '',
  });

  /// **前置条件**不满足（没选照片 / 设备记录不存在 / 连不上这台设备）：两半都不执行，原样提示。
  ///
  /// 与「设备侧失败」不是一回事：连不上设备时端上根本没发出过 0x12，此时照删记录会让用户在
  /// 完全没碰到设备的情况下丢掉记录。小程序侧同样保留了这道连接前置（`ensureConnectedDevice`）。
  final String blockedMessage;

  /// 设备侧**真失败**的原因（设备忙 0x0B / Flash 写失败 0x04 / 传输中断 0x09 / 断连超时）。
  /// 空 = 设备侧成功，或按良性结果码（0x05 图片不存在 / 0x07 掩码不一致）当作已删跳过。
  final String deviceError;

  /// 删到了「屏幕当前正显示的那张」，补发的刷屏(0x24)失败：图已经删掉了，只是屏幕没切过去。
  final String refreshWarn;

  bool get blocked => blockedMessage.isNotEmpty;
}

/// 应用级演示状态容器。
///
/// 页面只通过这个对象读取和触发业务动作；设备、相册、投屏记录、权限和登录态都在这里统一维护。
/// 后续接入真实接口时，建议优先替换这些 action 方法内部实现，而不是让页面直接操作数据列表。
class PhotoFrameState extends ChangeNotifier {
  PhotoFrameState.seeded()
    : _language = AppLanguage.zh,
      _isLoggedIn = false,
      _currentUser = UserProfile(
        id: '',
        nickname: '',
        email: '',
        avatarColor: const Color(0xFFBC6C25),
        signature: '',
      ),
      _permissions = {
        PermissionKind.location: false,
        PermissionKind.bluetooth: false,
        PermissionKind.album: false,
        PermissionKind.camera: false,
      },
      _devices = [],
      _selectedDeviceId = '',
      _castRecords = [] {
    // BLE 层没有 BuildContext，用户可见错误文案（连接失败等）经此按当前语言取。
    BleController.instance.languageResolver = () => _language;
  }

  AppLanguage _language;
  bool _isLoggedIn;

  /// 会话代际：登录成功/登出/注销/会话过期时 +1。
  /// 各 refresh* 在 await 前捕获、写回前比对——登出前发出的在途请求（headers 里
  /// 是发起时固化的旧 token）返回时代际已变，直接丢弃，防止 A 账号的响应回填进
  /// B 账号的首屏（跨账号串屏窗口 ≤ 请求超时上限）。
  int _sessionEpoch = 0;
  UserProfile _currentUser;
  final Map<PermissionKind, bool> _permissions;
  final List<DeviceItem> _devices;
  final DeviceBatteryCache _batteryCache = DeviceBatteryCache();
  final List<CastRecord> _castRecords;
  final List<FaqArticle> _faqArticles = _seedFaqArticles();

  /// `_faqArticles` 当前对应的语言。null = 还没成功从后端拉到（列表是内置兜底）。
  ///
  /// 常见问题是后端按 `language` 返回不同语种的整套文案，缓存必须带语种标签：
  /// 否则切到英文再进操作指南，看到的还是上次拉的中文列表。
  AppLanguage? _faqLanguage;

  String _selectedDeviceId;

  // ── 首屏加载态（对齐小程序各页 `data.loading` 初值 true）────────────────────
  // 空列表有两种含义：「还没拉」和「拉完了确实是空」。只用 `list.isEmpty` 判断，
  // 首帧必然先渲染一次空态/缺省页，接口回来再跳变（这正是各页空态先闪的根因）。
  // 这里为每个列表记一个「首屏是否已出结果」的标记：
  //   - false → 页面显示 loading（骨架/转圈），不显示空态；
  //   - true  → 才允许按 isEmpty 判定空态。
  // 成功和失败都会置 true（失败落空态，与小程序 catch 里 `setData({loading:false})` 一致）。
  // 二次进入不回退为 false：沿用旧列表静默刷新（stale-while-revalidate，同小程序）。
  bool _devicesLoaded = false;
  bool _castRecordsLoaded = false;
  bool _userLoaded = false;

  // 「我的」页「我的相册」卡片上的张数：**全部设备**的投屏成功记录条数（2026-08-05）。
  // 单独存一份计数（而不是复用 _castRecords.length）：那份列表被图库页/投屏管理页按各自的
  // 设备与状态条件反复覆盖，长度随最后一次谁刷的而变，不能当账号级合计用。
  int _mineCastSuccessCount = 0;
  bool _mineCastSuccessLoaded = false;

  // 「最近一次刷新是否失败」：与 loaded 标记配合，列表页据此把断网等失败
  // 渲染成「加载失败 + 重试」，而不是误导性的「暂无数据」空态
  // （空态文案只在确认成功且确实为空时出现）。成功刷新会清掉。
  bool _devicesLoadError = false;
  bool _castRecordsLoadError = false;

  /// 设备列表首屏是否已出结果（false=仍在首次加载，页面应显示 loading 而非「未绑定」空态）。
  bool get devicesLoaded => _devicesLoaded;

  /// 投屏记录首屏是否已出结果。
  bool get castRecordsLoaded => _castRecordsLoaded;

  /// 最近一次设备列表刷新是否失败（配合 [devicesLoaded]：列表为空时显示失败重试态）。
  bool get devicesLoadError => _devicesLoadError;

  /// 最近一次投屏记录刷新是否失败。
  bool get castRecordsLoadError => _castRecordsLoadError;

  /// 用户资料首屏是否已出结果（「我的」页据此决定显示真实统计还是占位 `--`）。
  bool get userLoaded => _userLoaded;

  /// 「我的相册」张数是否已出结果（「我的」页据此在拿到数字前显示 `--张照片`）。
  bool get mineCastSuccessLoaded => _mineCastSuccessLoaded;

  AppLanguage get language => _language;

  bool get isLoggedIn => _isLoggedIn;

  UserProfile get currentUser => _currentUser;

  List<DeviceItem> get devices => List.unmodifiable(_devices);

  List<CastRecord> get castRecords => List.unmodifiable(_castRecords);

  List<FaqArticle> get faqArticles => List.unmodifiable(_faqArticles);

  /// 常见问题是否需要（重新）拉取：从没拉到过，或缓存语种与当前语种不一致。
  bool get faqNeedsRefresh => _faqLanguage != _language;

  DeviceItem get selectedDevice => _findDevice(_selectedDeviceId);

  /// 当前选中设备的 id（可能为空串 / 不在列表中；[selectedDevice] 找不到时返回
  /// `isPlaceholder` 的占位设备而**不是抛异常**——只想知道「选了哪台」时用这个，
  /// 不要用 `selectedDevice.id`）。
  String get selectedDeviceId => _selectedDeviceId;

  String tr({required String zh, String? en, String? ja}) {
    switch (_language) {
      case AppLanguage.zh:
        return zh;
      case AppLanguage.zhHant:
        return toTraditionalChinese(zh);
      case AppLanguage.en:
        return en ?? zh;
      case AppLanguage.ja:
        return ja ?? zh;
    }
  }

  String languageLabel(AppLanguage value) {
    switch (value) {
      case AppLanguage.zh:
        return '中文';
      case AppLanguage.zhHant:
        return '繁體中文';
      case AppLanguage.en:
        return 'English';
      case AppLanguage.ja:
        return '日本語';
    }
  }

  String permissionLabel(PermissionKind kind) {
    switch (kind) {
      case PermissionKind.location:
        return tr(zh: '位置', en: 'Location', ja: '位置情報');
      case PermissionKind.bluetooth:
        return tr(zh: '蓝牙', en: 'Bluetooth', ja: 'Bluetooth');
      case PermissionKind.album:
        return tr(zh: '相册', en: 'Album', ja: 'アルバム');
      case PermissionKind.camera:
        return tr(zh: '相机', en: 'Camera', ja: 'カメラ');
    }
  }

  String roleLabel(DeviceRole role) {
    switch (role) {
      case DeviceRole.owner:
        return tr(zh: '所有者', en: 'Owner', ja: 'オーナー');
      case DeviceRole.user:
        return tr(zh: '使用者', en: 'User', ja: '利用者');
    }
  }

  String sourceLabel(ImageSourceType source) {
    switch (source) {
      case ImageSourceType.camera:
        return tr(zh: '拍照', en: 'Camera', ja: '撮影');
      case ImageSourceType.album:
        return tr(zh: '相册', en: 'Album', ja: 'アルバム');
    }
  }

  String statusLabel(CastStatus status) {
    switch (status) {
      case CastStatus.success:
        return tr(zh: '成功', en: 'Success', ja: '成功');
      case CastStatus.failed:
        return tr(zh: '失败', en: 'Failed', ja: '失敗');
    }
  }

  String formatDateTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    if (_language == AppLanguage.en) {
      return '$month/$day ${value.year} $hour:$minute';
    }
    if (_language == AppLanguage.ja || _language == AppLanguage.zhHant) {
      return '${value.year}/$month/$day $hour:$minute';
    }
    return '${value.year}-$month-$day $hour:$minute';
  }

  /// 「我的」页「我的相册」卡片上的张数 = **全部设备**的投屏成功记录条数
  /// （2026-08-05，由 [refreshMineCastSuccessCount] 写入；对齐小程序 mine.js
  /// `photoCount: castSuccessCount`）。
  ///
  /// 不再用账号级 `imgCount`（相册口径）：那个数把投屏失败的、已从设备删掉的都算在内，
  /// 与点进「我的相册」看到的列表对不上。
  int get minePhotoCount => _mineCastSuccessCount;

  /// 「我的」页的设备数：优先后端统计（getUserInfo 的 `productCount`），
  /// 未下发（0）时回退本地列表长度——对齐小程序 mine.js。
  int get mineDeviceCount => _currentUser.productCount > 0
      ? _currentUser.productCount
      : _devices.length;

  DeviceItem deviceById(String deviceId) => _findDevice(deviceId);

  String deviceName(String deviceId) {
    // 容错：后端相册/投屏记录的 deviceId 可能未在当前设备列表中，避免反查抛异常。
    final matches = _devices.where((device) => device.id == deviceId);
    return matches.isEmpty ? deviceId : matches.first.name;
  }

  void setPermission(PermissionKind kind, bool enabled) {
    _permissions[kind] = enabled;
    notifyListeners();
  }

  /// 连接设备（真实 BLE，移植小程序「按需手动连接」模型）：先设为当前选中设备，
  /// 再经 [BleController.connectBoundDevice] 复用活动会话或扫描匹配连接。
  /// 后端记录必须具备完整 6 字节设备 ID；广播 4 字节 ID 只用于扫描候选，
  /// 建连后仍以 0x01 完整 ID 精确验身。设备名不参与物理身份判断。
  Future<ActionFeedback> connectDevice(String deviceId) async {
    DeviceItem? device;
    for (final item in _devices) {
      if (item.id == deviceId) {
        device = item;
        break;
      }
    }
    if (device == null) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '电子纸设备不存在。',
          en: 'E-paper device not found.',
          ja: '電子ペーパーが見つかりません。',
        ),
      );
    }
    if (!isCompleteDeviceSerial(device.serialNumber)) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '当前电子纸设备记录缺少完整的6字节电子纸设备ID，请删除后重新绑定。',
          en: 'This e-paper device record has no complete 6-byte device ID. Remove it and bind it again.',
          ja: 'この電子ペーパーの記録には完全な6バイトIDがありません。削除して再度追加してください。',
        ),
      );
    }
    _selectedDeviceId = deviceId;
    notifyListeners();

    final ble = BleController.instance;
    final error = await ble.connectBoundDevice(
      serial: device.serialNumber,
      name: device.name,
      screenCode: device.screenType.code,
    );
    // await 期间 refreshDevices 可能并发完成并整体替换了 _devices（新对象列表），
    // 进场拿到的 device 引用已成孤儿——往孤儿上写标记 UI 看不见（表现为
    // 「toast 说连接成功、卡片却显示未连接」）。回来后按 id 重查，找不到就只做
    // reconcile 让连接态按活动会话如实回填。
    device = null;
    for (final item in _devices) {
      if (item.id == deviceId) {
        device = item;
        break;
      }
    }
    if (device == null) {
      reconcileConnectionFlags();
      return error != null
          ? ActionFeedback(success: false, message: error)
          : ActionFeedback(
              success: true,
              message: tr(
                zh: '已连接电子纸设备。',
                en: 'E-paper device connected.',
                ja: '電子ペーパーに接続しました。',
              ),
            );
    }
    if (error != null) {
      device.connected = false;
      notifyListeners();
      return ActionFeedback(success: false, message: error);
    }
    for (final item in _devices) {
      item.connected = identical(item, device);
    }
    // 连接 loading 内只把真机 0x01 核心字段回填到本地设备
    // （内存/播放模式/间隔/当前张）。电量独立走 0x04 后台刷新；
    // 固件版本保留后端值，不让 0x03 挡住连接页。
    _applyConnectedInfo(device, ble.info);
    notifyListeners();
    unawaited(_refreshDeviceBattery(deviceId));
    return ActionFeedback(
      success: true,
      message: tr(
        zh: '已连接电子纸设备。',
        en: 'E-paper device connected.',
        ja: '電子ペーパーに接続しました。',
      ),
    );
  }

  /// 断开设备的 BLE 连接（对齐小程序设备列表「断开」按钮）。
  Future<ActionFeedback> disconnectDevice(String deviceId) async {
    final trace = DeviceInteractionTrace('disconnect-device');
    final ble = BleController.instance;
    try {
      for (final device in _devices) {
        if (device.id != deviceId) {
          continue;
        }
        // 只允许目标设备自己占用的会话触发物理断开。缓存的 connected
        // 可能在切页/刷新期间过期，不能据此断开当前属于另一台设备的会话。
        if (ble.sessionMatchesSerial(
          device.serialNumber,
          screenCode: device.screenType.code,
        )) {
          await trace.measure('ble-disconnect', ble.disconnect);
        } else {
          trace.mark('ble-disconnect-skipped');
        }
        device.connected = false;
        notifyListeners();
        trace.finish(success: true);
        return ActionFeedback(
          success: true,
          message: tr(zh: '已断开。', en: 'Disconnected.', ja: '切断しました。'),
        );
      }
      trace.finish(success: false, stage: 'device-not-found');
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '电子纸设备不存在。',
          en: 'E-paper device not found.',
          ja: '電子ペーパーが見つかりません。',
        ),
      );
    } catch (error) {
      trace.finish(success: false, stage: 'ble-disconnect-failed');
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '断开电子纸设备失败，请稍后重试。',
          en: 'Failed to disconnect the e-paper device. Please try again.',
          ja: '電子ペーパーを切断できませんでした。もう一度お試しください。',
        ),
      );
    }
  }

  /// 这台设备是否正占着当前 BLE 活动会话（序列号容错交叉匹配）。
  bool _sessionMatches(DeviceItem device) =>
      BleController.instance.sessionMatchesSerial(
        device.serialNumber,
        screenCode: device.screenType.code,
      );

  /// [deviceId] 对应的后端设备记录是否正是当前 BLE 活动会话的物理设备。
  ///
  /// 页面和业务动作必须使用这个判断，不能只看 [DeviceItem.connected] 或
  /// [BleController.connected]；后两者可能是刷新前的缓存，或仅表示连着另一台设备。
  bool isDeviceActuallyConnected(String deviceId) {
    final device = _deviceByIdOrNull(deviceId);
    return device != null && _sessionMatches(device);
  }

  /// 入口门禁专用：先尽力把这条记录的稳定身份补齐，再判是否就是当前 BLE 会话。
  ///
  /// [isDeviceActuallyConnected] 是纯同步判断，只认记录当下带着的完整 6 字节 ID。
  /// 但详情接口（`getUserProductDetail`）并不保证下发 `deviceId`，绑定刚完成时也可能没有——
  /// 此时身份缺失会让判断一律为 false，于是**明明连着这台设备，点「轮播设置」却提示
  /// 「请先连接设备」**（用户反馈第 7 项）。
  ///
  /// 这里补的是小程序 `activeDevice.inheritStableIdentity` 那一步：查身份登记表把完整 ID
  /// 填回记录，再重判一次。登记表只收 0x01 验过身的完整 ID（见 [DeviceIdentityRegistry]），
  /// 因此不会把「短 ID 兜底」升格成身份，也就不会串台。
  Future<bool> resolveDeviceConnected(String deviceId) async {
    if (isDeviceActuallyConnected(deviceId)) {
      return true;
    }
    final device = _deviceByIdOrNull(deviceId);
    // 记录本身已带完整 ID 却判不通过 = 真的连着别台（或没连），补身份也救不回来。
    if (device == null || device.isPlaceholder || device.serialNumber.isNotEmpty) {
      return false;
    }
    final remembered = await DeviceIdentityRegistry.instance.recall(deviceId);
    if (remembered.isEmpty) {
      return false;
    }
    device.serialNumber = remembered;
    final live = _sessionMatches(device);
    if (device.connected != live) {
      device.connected = live;
      notifyListeners();
    }
    return live;
  }

  /// 用真实 BLE 会话对账各设备的「已连接」显示（回前台连接体检后调用，
  /// 对齐小程序 app.onShow → reconcileConnections 落到 UI 的那一步）。
  void reconcileConnectionFlags() {
    var changed = false;
    String? connectedDeviceId;
    for (final device in _devices) {
      final live = _sessionMatches(device);
      if (device.connected != live) {
        device.connected = live;
        changed = true;
      }
      if (live) {
        connectedDeviceId = device.id;
      }
    }
    if (changed) {
      notifyListeners();
    }
    if (connectedDeviceId != null) {
      unawaited(_refreshDeviceBattery(connectedDeviceId));
    }
  }

  /// 重新读取当前选中设备的真机内存/索引并合并回本地（对齐小程序 detail.js onShow→loadDetail→readDeviceInfo）。
  /// 设备详情页每次打开/重入时调用：上传/删除/清空等改变设备索引的操作后，
  /// 内存展示才不会停留在连接时（connectDevice）读到的旧值（Bug13）。未连接或读失败则保持原样。
  Future<void> refreshSelectedDeviceMemory() async {
    if (_selectedDeviceId.isEmpty) {
      return;
    }
    await refreshConnectedDeviceInfo(_selectedDeviceId);
  }

  /// 用身份登记表补齐 / 登记设备记录的完整 6 字节 ID（见 [DeviceIdentityRegistry]）。
  ///
  /// 两个方向：记录缺 ID 就查表补上；记录带着后端下发的完整 ID 就登记下来。
  /// 登记表永不反向覆盖后端最新值——只在记录自身与本地上一版都拿不出 ID 时才被采纳。
  Future<void> _completeDeviceIdentities(List<DeviceItem> devices) async {
    final registry = DeviceIdentityRegistry.instance;
    for (final device in devices) {
      if (device.isPlaceholder) {
        continue;
      }
      if (device.serialNumber.isEmpty) {
        final remembered = await registry.recall(device.id);
        if (remembered.isNotEmpty) {
          device.serialNumber = remembered;
        }
      } else {
        await registry.remember(device.id, device.serialNumber);
      }
    }
  }

  /// 按 id 在当前列表里找设备；找不到返回 null（区别于 [_findDevice] 的占位兜底）。
  DeviceItem? _deviceByIdOrNull(String deviceId) {
    for (final item in _devices) {
      if (item.id == deviceId) {
        return item;
      }
    }
    return null;
  }

  /// 按设备 id 回读真机内存/索引。投屏完成页调用时不改变当前选中的设备。
  Future<void> refreshConnectedDeviceInfo(String deviceId) async {
    final device = _deviceByIdOrNull(deviceId);
    if (device == null) {
      return;
    }
    // 只有当前 BLE 会话就是这台设备时才读；否则保持未连接的 -- 显示，不误连别台。
    if (!_sessionMatches(device)) {
      return;
    }
    final trace = DeviceInteractionTrace('refresh-device-core-info');
    try {
      // 内存/索引刷新只需要 0x01；固件版本 0x03 在连接/OTA 场景读取。
      // 避免旧固件不支持 0x03 时，每次页面重入都额外等满 6 秒。
      final info = await trace.measure(
        'read-core-info-0x01',
        BleController.instance.client.readTransferInfo,
      );
      // 读 0x01 期间（100~500ms）若有并发的 refreshDevices 完成，_devices 已被整体换过，
      // 上面捕获的 device 就成了游离对象——写进去 UI 永远读不到（connectDevice 早有同款
      // 保护，见其 await 后的重新查找）。这里按 id 重新定位一次。
      final target = _deviceByIdOrNull(deviceId) ?? device;
      _applyConnectedInfo(target, info);
      target.connected = true;
      notifyListeners();
      trace.finish(success: true);
    } catch (_) {
      // 读失败静默（与小程序 loadDetail 的 catch 一致），保持旧值。
      trace.finish(success: false);
    } finally {
      // 电量使用独立 0x04 + 15 秒缓存；等 0x01 结束后再后台发起，避免两条设备
      // 指令并发交错。不阻塞页面返回，也不先清空旧值。
      unawaited(_refreshDeviceBattery(deviceId));
    }
  }

  /// 把上一份列表里同一台设备的**蓝牙专属字段**搬到新对象上。
  ///
  /// [refreshDevices] 是整体替换列表（后端为准），而电量 / 实时内存 / 当前索引 / 固件版本 /
  /// 轮播态这些字段后端根本不返回，新对象里是 0/null。不搬运的话，任何一次列表刷新都会
  /// 把 BLE 辛苦读回来的值清掉，而设备列表页自身**不做** BLE 回读，于是就一直显示 0%。
  ///
  /// 匹配优先按 id；id 变了（后端换主键/重复绑定折叠）时退回硬件序列号——与
  /// [_dedupeDevicesBySerial] 用同一套归一化规则。
  void _carryOverBleFields(DeviceItem fresh) {
    String norm(String s) => s.replaceAll(RegExp(r'[:\-\s]'), '').toUpperCase();
    final freshSerial = norm(fresh.serialNumber);
    DeviceItem? old;
    for (final item in _devices) {
      if (item.id == fresh.id) {
        old = item;
        break;
      }
      if (old == null &&
          freshSerial.isNotEmpty &&
          norm(item.serialNumber) == freshSerial) {
        old = item; // 序列号命中先记下，继续找 id 精确匹配
      }
    }
    if (old == null) {
      return; // 新绑定的设备：没有旧值可搬，等连接后 BLE 回填
    }
    if (!fresh.hasBatteryReading && old.hasBatteryReading) {
      fresh.batteryLevel = old.batteryLevel;
      fresh.batteryUpdatedAt = old.batteryUpdatedAt;
    }
    fresh.charging = old.charging;
    fresh.liveImageCount ??= old.liveImageCount;
    fresh.liveCapacity ??= old.liveCapacity;
    if (fresh.imageMask == 0) {
      fresh.imageMask = old.imageMask;
    }
    if (fresh.currentImageIndex < 0) {
      fresh.currentImageIndex = old.currentImageIndex;
    }
    if (fresh.firmwareVersion.isEmpty) {
      fresh.firmwareVersion = old.firmwareVersion;
    }
    // 稳定身份的第二档来源（顺序见 [DeviceIdentityRegistry]：记录自身 > 本地上一版 > 登记表）。
    // 后端这一行缺 deviceId 时，用上一版记录里已验证过的完整 ID 补上——**只补不覆盖**，
    // 后端下发的完整 ID 永远优先。不搬的话，后端一次抖动就会把身份丢掉，
    // 之后这台设备的每一次连接都会被身份闸拦在扫描之前。
    if (fresh.serialNumber.isEmpty && old.serialNumber.isNotEmpty) {
      fresh.serialNumber = old.serialNumber;
    }
    fresh.playbackMode = old.playbackMode;
    fresh.carouselEnabled = old.carouselEnabled;
    // 间隔要跟默认值比、不能跟 0 比：列表接口不下发 carouselInterval，_deviceFromJson
    // 一律填默认 2h，用 `<= 0` 判就永远不生效——真机读回来的间隔会被 2h 覆盖，
    // 用户下次开关轮播时还会把这个 2h 写回设备。
    if (fresh.carouselIntervalSeconds ==
            FrameProtocolConfig.defaultCarouselIntervalSeconds &&
        old.carouselIntervalSeconds > 0) {
      fresh.carouselIntervalSeconds = old.carouselIntervalSeconds;
    }
  }

  /// 把真机 0x01 读到的 [FrameDeviceInfo] 合并进本地 [device]。
  ///
  /// 电量不在这里处理：页面电量统一由 [_refreshDeviceBattery] 通过 0x04 获取，
  /// 以免 0x01 与 15 秒缓存形成两个互相覆盖的数据源。
  /// 调用方负责 notifyListeners()。[info] 为空（读取失败）时不改动，页面按 connected=false 显示 --。
  void _applyConnectedInfo(DeviceItem device, FrameDeviceInfo? info) {
    if (info == null) {
      return;
    }
    // 0x01 验身通过的完整 6 字节 ID 是**最权威的一手身份来源**（两处调用点都已确认
    // 当前 BLE 会话就是这台设备）。登记进身份表，并在记录自身缺 ID 时就地补上。
    //
    // 少了这一步，后端列表接口任何一次没下发 deviceId，身份就会当场丢失
    //（`_carryOverBleFields` 搬电量/固件却不搬 serialNumber），之后
    // `connectBoundDevice` 第一行的身份闸会把这台好设备**一直拦在扫描之前**，
    // 报「请删除后重新绑定」。见 [DeviceIdentityRegistry] 与小程序同款修复。
    final verified = canonicalDeviceSerial(info.deviceId);
    if (verified.isNotEmpty && !device.isPlaceholder) {
      if (device.serialNumber.isEmpty) {
        device.serialNumber = verified;
      }
      unawaited(DeviceIdentityRegistry.instance.remember(device.id, verified));
    }
    // 真机内存（真机容量最多 95 槽，超出 int 掩码范围，直接采用上报计数/容量）。
    // 这里**不能**像电量/容量那样加 `> 0` 守卫：0 张是合法状态（设备被清空），
    // 加了守卫清空后就会一直显示旧张数。
    device.liveImageCount = info.imgCount;
    if (info.capacity > 0) {
      device.liveCapacity = info.capacity;
    }
    device.currentImageIndex = info.curImgIndex;
    device.playbackMode = _playbackModeFromWire(info.playMode);
    device.carouselEnabled = info.playMode != 'manual';
    // 间隔以真机为准（供轮播设置 setPlayback 复用，避免用 24h 默认值覆盖设备现有间隔）。
    if (info.intervalSeconds > 0) {
      device.carouselIntervalSeconds = info.intervalSeconds;
    }
    if (info.firmwareVersion.isNotEmpty) {
      device.firmwareVersion = info.firmwareVersion;
    }
  }

  /// 按物理设备完整 ID 获取电量：15 秒内复用，过期后台读 0x04，并发调用共享一次读取。
  ///
  /// 主动操作前取一次电量，供低电量提醒使用（2026-08-21 同步小程序）。
  ///
  /// 走的就是 [_refreshDeviceBattery] 那一套：15 秒内复用最近一次 0x04，超窗才真读，
  /// 读失败保留旧值——所以「点一下弹一次提醒」不会变成「点一下多发一条 BLE 指令」。
  /// 从未读到过电量时返回 null，调用方据此**不弹**（没有判据就不报警）。
  Future<int?> batteryForActionTip(String deviceId) async {
    await _refreshDeviceBattery(deviceId);
    final device = _deviceByIdOrNull(deviceId);
    if (device == null || !device.hasBatteryReading) {
      return null;
    }
    return device.batteryLevel;
  }

  /// 读取失败/非法值保持最近一次有效值；从未成功读取时保持未知，由页面显示 `--`。
  Future<void> _refreshDeviceBattery(
    String deviceId, {
    bool force = false,
  }) async {
    final device = _deviceByIdOrNull(deviceId);
    if (device == null || !_sessionMatches(device)) {
      return;
    }
    final serialKey = normalizeSerial(device.serialNumber);
    if (!isCompleteDeviceSerial(serialKey)) {
      return;
    }
    final fallback = device.hasBatteryReading
        ? DeviceBatteryReading(
            value: device.batteryLevel,
            updatedAt: device.batteryUpdatedAt!,
          )
        : null;
    final reading = await _batteryCache.readLatest(
      key: serialKey,
      read: BleController.instance.client.readBattery,
      fallback: fallback,
      force: force,
    );
    if (reading == null) {
      return;
    }

    // BLE await 期间设备列表可能被接口刷新整体替换，也可能已切换到另一台会话。
    final target = _deviceByIdOrNull(deviceId);
    if (target == null ||
        !_sessionMatches(target) ||
        normalizeSerial(target.serialNumber) != serialKey) {
      return;
    }
    final changed =
        !target.hasBatteryReading ||
        target.batteryLevel != reading.value ||
        target.batteryUpdatedAt != reading.updatedAt;
    target.batteryLevel = reading.value;
    target.batteryUpdatedAt = reading.updatedAt;
    if (changed) {
      notifyListeners();
    }
  }

  /// 按硬件序列号去重设备列表（对齐小程序 `list.js dedupeDevices`）：序列号归一化
  /// （大写、去 `:`/`-`/空白）为 key，无序列号时退回 `id:`；冲突保留首个，但当前选中项优先。
  List<DeviceItem> _dedupeDevicesBySerial(List<DeviceItem> devices) {
    String norm(String s) => s.replaceAll(RegExp(r'[:\-\s]'), '').toUpperCase();
    final map = <String, DeviceItem>{};
    final order = <String>[];
    for (final device in devices) {
      final serial = norm(device.serialNumber);
      final key = serial.isNotEmpty ? 'sn:$serial' : 'id:${device.id}';
      if (!map.containsKey(key)) {
        map[key] = device;
        order.add(key);
      } else if (_selectedDeviceId.isNotEmpty &&
          device.id == _selectedDeviceId) {
        map[key] = device;
      }
    }
    return [for (final key in order) map[key]!];
  }

  /// 线协播放模式字符串(order/random/manual) → [FramePlaybackMode] 枚举。
  FramePlaybackMode _playbackModeFromWire(String playMode) {
    switch (playMode) {
      case 'random':
        return FramePlaybackMode.random;
      case 'manual':
        return FramePlaybackMode.manual;
      default: // 'order'
        return FramePlaybackMode.sequence;
    }
  }

  /// 邮箱密码登录入口。
  ///
  /// 调用 `/Client/User/userLogin`，成功后把返回的 userToken 与 jwtToken 写入
  /// [ApiSession]（后续接口会带上业务公共参数与 Authentication 头）。
  Future<ActionFeedback> loginWithPassword(
    String email,
    String password,
  ) async {
    final target = email.trim();
    if (!_isValidEmail(target)) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '邮箱格式不正确。',
          en: 'Invalid email format.',
          ja: 'メール形式が正しくありません。',
        ),
      );
    }
    if (password.trim().isEmpty) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '密码不能为空。',
          en: 'Password cannot be empty.',
          ja: 'パスワードは必須です。',
        ),
      );
    }

    try {
      final data = await BoltFoxApi.userLogin(
        email: target,
        password: password,
      );
      final token = _readToken(data);
      final jwtToken = _readJwtToken(data);
      // 登录成功必须同时拿到两种会话凭证。原来 token 缺失时仍把本地状态切成
      // “已登录”，首页随即并发请求设备列表并收到 401/406，再触发回登录页与
      // BLE 清理；在真机上表现为刚进首页就退出/崩溃。与微信登录保持同一门槛。
      if (token == null ||
          token.isEmpty ||
          jwtToken == null ||
          jwtToken.isEmpty) {
        return ActionFeedback(
          success: false,
          message: tr(
            zh: '登录响应缺少 userToken 或 jwtToken，请稍后重试。',
            en: 'The login response did not contain all required credentials.',
            ja: 'ログイン応答に必要な認証情報がありません。',
          ),
        );
      }
      ApiSession.instance.setTokens(userToken: token, jwtToken: jwtToken);
      _sessionEpoch++; // 新会话开始，作废上一会话的在途响应
      _isLoggedIn = true;
      _currentUser.email = target;
      // 登录响应就是完整的用户信息（swagger: `UserInfoDetailApiOut` = UserInfoApiOut + userToken，
      // 含 userNo/nickName/avatar/userEmail/imgCount/productCount），直接用它回填，
      // 不必再多打一次 getUserInfo；即便那个接口失败，昵称头像也已经就位。
      _applyUserInfo(data);
      _userLoaded = true;
      notifyListeners();
      return ActionFeedback(
        success: true,
        message: tr(
          zh: '登录成功，已同步到个人资料。',
          en: 'Login succeeded and profile updated.',
          ja: 'ログインに成功し、プロフィールに反映しました。',
        ),
      );
    } catch (error) {
      return _apiFailure(error);
    }
  }

  /// 已提交过的微信 code（FIFO，只留最近几条）。
  ///
  /// 微信 code 是一次性凭证：后端拿它换过一次 access_token 后，同一个 code 再换必被微信判
  /// 40163。网络层已对该接口关掉全部自动重试，这里挡的是业务层复用——失败提示上连点重试、
  /// 页面重建后拿旧 code 再调等。挡不住的话用户看到的是「微信登录失败」，排查方向全跑偏。
  final Set<String> _consumedWeChatCodes = <String>{};

  /// 微信开放平台「移动应用微信登录」入口。
  ///
  /// [code] 由移动端微信 SDK 返回，只能使用一次；服务端负责用 AppSecret 换取微信身份并返回
  /// BoltStar 的 userToken 与 jwtToken。客户端绝不保存微信 access_token /
  /// refresh_token / AppSecret。
  Future<ActionFeedback> loginWithWeChatCode(String code) async {
    final authorizationCode = code.trim();
    if (authorizationCode.isEmpty) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '微信授权凭证无效，请重新登录。',
          en: 'Invalid WeChat authorization code. Please try again.',
          ja: 'WeChat の認証コードが無効です。もう一度お試しください。',
        ),
      );
    }
    // 提交即视为已消费（成功与否都不能再发第二次），登记失败说明这个 code 已经发过了。
    if (!_consumedWeChatCodes.add(authorizationCode)) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '微信授权凭证已使用，请重新发起微信登录。',
          en: 'This WeChat authorization has already been used. Please sign in with WeChat again.',
          ja: 'この WeChat 認証は使用済みです。もう一度 WeChat でログインしてください。',
        ),
      );
    }
    if (_consumedWeChatCodes.length > 8) {
      _consumedWeChatCodes.remove(_consumedWeChatCodes.first);
    }

    try {
      final data = await BoltFoxApi.weChatMobileLogin(code: authorizationCode);
      final token = _readToken(data);
      final jwtToken = _readJwtToken(data);
      if (token == null ||
          token.isEmpty ||
          jwtToken == null ||
          jwtToken.isEmpty) {
        return ActionFeedback(
          success: false,
          message: tr(
            zh: '微信登录响应缺少 userToken 或 jwtToken，请稍后重试。',
            en: 'The WeChat login response did not contain all required credentials.',
            ja: 'WeChat ログイン応答に必要な認証情報がありません。',
          ),
        );
      }

      ApiSession.instance.setTokens(userToken: token, jwtToken: jwtToken);
      _sessionEpoch++; // 新会话开始，作废上一会话的在途响应
      _isLoggedIn = true;
      _applyUserInfo(data);
      _userLoaded = true;
      notifyListeners();
      return ActionFeedback(
        success: true,
        message: tr(
          zh: '微信登录成功。',
          en: 'Signed in with WeChat.',
          ja: 'WeChat でログインしました。',
        ),
      );
    } on ApiException catch (error) {
      // ⚠️ 登录接口**自己**返回 401/406 不是「本地会话过期」：用户此刻就在登录页，
      // 没有会话可过期。走 _apiFailure 会把后端的 retMsg「请重新登录！」原样弹出
      // （经 AppL10n 重译成「请重新登录」）——这条提示既没有信息量，还把排查方向
      // 全带到微信 SDK / 签名 / AppID 上去，而微信侧其实已经成功返回 code 了。
      //
      // 2026-08-04 实测（curl 直打生产）：不带 userToken 调
      // `/Client/User/setWechatAuthorizLogin` 恒返回 `retCode 406 请重新登录！`，
      // 换 terminal、置空/乱填 userToken、省略 code 一律同一结果，即请求根本没
      // 进业务逻辑；同样不带 token 的 `userLogin` / `userRegister` / `setWechatAppLogin`
      // 都正常进业务逻辑（分别回 "Email does not exist" / 邮箱格式错误 / 微信 40029）。
      // 结论：该接口没进后端的免登录白名单，**要后端放行**，客户端改不了。
      if (error.isAuthError) {
        return ActionFeedback(
          success: false,
          message: tr(
            zh: '微信登录被服务端拒绝（retCode ${error.code}：${error.message}）：'
                '微信授权本身已成功，是后端接口未放行未登录调用。',
            en:
                'The server rejected WeChat sign-in (retCode ${error.code}: ${error.message}). '
                'WeChat authorization itself succeeded; the endpoint refuses unauthenticated calls.',
            ja:
                'サーバーが WeChat ログインを拒否しました（retCode ${error.code}：${error.message}）。'
                'WeChat 認証自体は成功しています。',
          ),
          // ⚠️ 临时（2026-08-05）：后端要拿客户端实际发出的参数复现，这里把请求现场
          // 带给 UI 弹到 toast 上。接口放行后连同 describeWeChatMobileLogin 一起删。
          diagnostics: BoltFoxApi.describeWeChatMobileLogin(
            code: authorizationCode,
          ),
        );
      }
      return _apiFailure(error);
    } catch (error) {
      return _apiFailure(error);
    }
  }

  /// 发送邮箱验证码。[sendType]：1=注册、2=找回/改密、3=改邮箱。
  /// 统一走 `/Client/Basic/sendEmail`（对齐小程序，见账号#1）；[loggedIn] 仅用于放宽格式校验
  /// （已登录改邮箱等场景由页面自行校验新邮箱）。
  Future<ActionFeedback> sendEmailCode({
    required String email,
    required int sendType,
    bool loggedIn = false,
  }) async {
    final target = email.trim();
    if (!loggedIn && !_isValidEmail(target)) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '邮箱格式不正确。',
          en: 'Invalid email format.',
          ja: 'メール形式が正しくありません。',
        ),
      );
    }
    try {
      // 对齐小程序：绑定/换邮箱/改密的验证码也统一走 `/Client/Basic/sendEmail`
      // （auth:false），小程序从不调用 sendEmailToken。见 app-vs-miniprogram-sync 账号#1。
      await BoltFoxApi.sendEmail(userEmail: target, sendType: sendType);
      return ActionFeedback(
        success: true,
        message: tr(
          zh: '验证码已发送。',
          en: 'Verification code sent.',
          ja: '認証コードを送信しました。',
        ),
      );
    } catch (error) {
      return _apiFailure(error);
    }
  }

  /// 邮箱验证码注册。成功后由调用方引导回登录页（不自动登录）。
  Future<ActionFeedback> registerWithEmail({
    required String email,
    required String password,
    required String emailCode,
  }) async {
    final target = email.trim();
    if (!_isValidEmail(target)) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '邮箱格式不正确。',
          en: 'Invalid email format.',
          ja: 'メール形式が正しくありません。',
        ),
      );
    }
    if (password.isEmpty) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '密码不能为空。',
          en: 'Password cannot be empty.',
          ja: 'パスワードは必須です。',
        ),
      );
    }
    if (emailCode.trim().isEmpty) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '请输入验证码。',
          en: 'Enter the verification code.',
          ja: '認証コードを入力してください。',
        ),
      );
    }
    try {
      // 注册接口（UserRegisterApiIn）无 nickName 字段；昵称注册后经 changeNickName 修改。
      await BoltFoxApi.userRegister(
        email: target,
        password: password,
        emailCode: emailCode.trim(),
      );
      return ActionFeedback(
        success: true,
        message: tr(zh: '注册成功。', en: 'Registered.', ja: '登録しました。'),
      );
    } catch (error) {
      return _apiFailure(error);
    }
  }

  /// 忘记密码 / 通过验证码重置密码。
  Future<ActionFeedback> resetPasswordByEmail({
    required String email,
    required String password,
    required String emailCode,
  }) async {
    final target = email.trim();
    if (!_isValidEmail(target)) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '邮箱格式不正确。',
          en: 'Invalid email format.',
          ja: 'メール形式が正しくありません。',
        ),
      );
    }
    if (password.isEmpty) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '密码不能为空。',
          en: 'Password cannot be empty.',
          ja: 'パスワードは必須です。',
        ),
      );
    }
    if (emailCode.trim().isEmpty) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '请输入验证码。',
          en: 'Enter the verification code.',
          ja: '認証コードを入力してください。',
        ),
      );
    }
    try {
      await BoltFoxApi.resetPassword(
        email: target,
        password: password,
        emailCode: emailCode.trim(),
      );
      return ActionFeedback(
        success: true,
        message: tr(zh: '密码已重置。', en: 'Password reset.', ja: 'パスワードを再設定しました。'),
      );
    } catch (error) {
      return _apiFailure(error);
    }
  }

  /// 修改密码（**已登录**）：走 `/Client/User/changePassword`，后端按 userToken 定位
  /// 账号，无需（也没有）邮箱字段；验证码须先经 sendEmail(sendType:2) 发到账号绑定邮箱。
  /// 未登录的忘记密码请用 [resetPasswordByEmail]。
  Future<ActionFeedback> changePasswordLoggedIn({
    required String password,
    required String emailCode,
  }) async {
    if (password.isEmpty) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '密码不能为空。',
          en: 'Password cannot be empty.',
          ja: 'パスワードは必須です。',
        ),
      );
    }
    if (emailCode.trim().isEmpty) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '请输入验证码。',
          en: 'Enter the verification code.',
          ja: '認証コードを入力してください。',
        ),
      );
    }
    try {
      await BoltFoxApi.changePassword(
        password: password,
        emailCode: emailCode.trim(),
      );
      return ActionFeedback(
        success: true,
        message: tr(zh: '密码已修改。', en: 'Password changed.', ja: 'パスワードを変更しました。'),
      );
    } catch (error) {
      return _apiFailure(error);
    }
  }

  /// 绑定 / 修改已登录用户的邮箱。
  Future<ActionFeedback> changeBoundEmail({
    required String email,
    required String emailCode,
    String? password,
  }) async {
    final target = email.trim();
    if (!_isValidEmail(target)) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '邮箱格式不正确。',
          en: 'Invalid email format.',
          ja: 'メール形式が正しくありません。',
        ),
      );
    }
    if (emailCode.trim().isEmpty) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '请输入验证码。',
          en: 'Enter the verification code.',
          ja: '認証コードを入力してください。',
        ),
      );
    }
    try {
      await BoltFoxApi.changeUserEmail(
        email: target,
        emailCode: emailCode.trim(),
        password: password,
      );
      _currentUser.email = target;
      notifyListeners();
      return ActionFeedback(
        success: true,
        message: tr(zh: '邮箱已更新。', en: 'Email updated.', ja: 'メールを更新しました。'),
      );
    } catch (error) {
      return _apiFailure(error);
    }
  }

  /// 检查 App 版本更新（对齐小程序 `app.js` 里的 TODO：`getLastVersion` + `getAndroidDownload`）。
  ///
  /// 读当前版本 → 调 `getLastVersion(appVersionNo: 当前)` → 解析是否有新版/下载地址/更新说明；
  /// 地址缺失时回退 `getAndroidDownload()`。后端响应字段名未在小程序侧落地过，这里做**防御式**
  /// 多字段兼容，真实字段需以后端为准（见字段候选列表）。
  Future<AppVersionInfo> checkAppVersion() async {
    final pkg = await PackageInfo.fromPlatform();
    final current = pkg.version;
    final data = await BoltFoxApi.getLastVersion(appVersionNo: current);

    // 字段名以 swagger `AppVersionConApiOutput` 为准：
    // `appVersionNo`(最新版本号) / `isUpdate`(1=有更新) / `downloadPath`(更新包地址) /
    // `upgradeTips`(更新说明) / `compulsory`(1=强制升级 2=强提示 3=弱提示 4=不提示)。
    // 原实现读的 versionNo / content / downloadUrl 等键后端都不存在——版本号和更新说明永远是空。
    String latest = '';
    String url = '';
    String desc = '';
    bool hasUpdate = false;
    int compulsory = 0;
    if (data is Map) {
      final m = data.map((k, v) => MapEntry(k.toString(), v));
      latest = (m['appVersionNo'] ?? '').toString();
      url = (m['downloadPath'] ?? '').toString();
      desc = (m['upgradeTips'] ?? '').toString();
      hasUpdate = _asInt(m['isUpdate']) == 1;
      compulsory = _asInt(m['compulsory']);
    } else if (data is String) {
      latest = data.trim();
      hasUpdate = _versionGreater(latest, current);
    }

    if (hasUpdate && url.isEmpty) {
      try {
        url = _extractUploadedUrl(await BoltFoxApi.getAndroidDownload());
      } catch (_) {
        // 下载地址兜底接口失败不阻断：仍提示有新版本，只是无法直达下载。
      }
    }

    return AppVersionInfo(
      hasUpdate: hasUpdate,
      currentVersion: current,
      latestVersion: latest.isEmpty ? current : latest,
      downloadUrl: url,
      description: desc,
      compulsory: compulsory,
    );
  }

  /// 点分版本号比较：[a] 是否严格大于 [b]（如 1.2.0 > 1.1.9）。非数字段按 0 处理。
  bool _versionGreater(String a, String b) {
    List<int> parts(String v) => v
        .split('.')
        .map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final pa = parts(a);
    final pb = parts(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) {
        return x > y;
      }
    }
    return false;
  }

  /// 更换头像（对齐小程序 `home.js onChooseAvatar` / `profile.js`）：选好的本地图片先
  /// [BoltFoxApi.setFileUpload] 上传取地址，再 [BoltFoxApi.changeAvatar] 落库，成功后即时
  /// 更新本地 `currentUser.avatarUrl` 并通知刷新（首页/我的/资料页头像同步）。
  Future<ActionFeedback> updateAvatar(String filePath) async {
    try {
      final uploaded = await BoltFoxApi.setFileUpload([filePath]);
      final url = _extractUploadedUrl(uploaded);
      if (url.isEmpty) {
        return ActionFeedback(
          success: false,
          message: tr(
            zh: '头像上传失败，请重试。',
            en: 'Avatar upload failed, please retry.',
            ja: 'アバターのアップロードに失敗しました。',
          ),
        );
      }
      await BoltFoxApi.changeAvatar(url);
      _currentUser.avatarUrl = url;
      // 落库后回读一次用户信息：以后端最终存储的头像地址为准。上传接口返回的
      // 地址可能是相对路径/中转地址，直接拿来展示可能加载不出（“保存成功后
      // 头像不出来”的一类根源）；回读失败时保留上传地址作显示兜底，不影响结果。
      try {
        _applyUserInfo(await BoltFoxApi.getUserInfo());
      } catch (_) {}
      notifyListeners();
      return ActionFeedback(
        success: true,
        message: tr(zh: '头像已更新。', en: 'Avatar updated.', ja: 'アバターを更新しました。'),
      );
    } catch (error) {
      return _apiFailure(error);
    }
  }

  /// 从 setFileUpload 的 retData 提取上传后的文件地址：兼容直接返回 URL 字符串、
  /// 数组（取首个）、或对象（url / fileUrl / path 等常见字段）。
  String _extractUploadedUrl(dynamic data) {
    if (data is String) {
      return data.trim();
    }
    if (data is List && data.isNotEmpty) {
      return _extractUploadedUrl(data.first);
    }
    if (data is Map) {
      final url =
          data['url'] ??
          data['fileUrl'] ??
          data['filePath'] ??
          data['path'] ??
          data['fileParam'] ??
          data['src'];
      if (url is String) {
        return url.trim();
      }
    }
    return '';
  }

  /// 保存个人资料。昵称走 `/Client/User/changeNickName`（1-10 字）。
  Future<ActionFeedback> updateProfile({
    required String nickname,
    required String email,
    required String signature,
    required Color avatarColor,
  }) async {
    final nick = nickname.trim();
    if (nick.isEmpty) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '昵称不能为空。',
          en: 'Nickname cannot be empty.',
          ja: 'ニックネームは必須です。',
        ),
      );
    }
    if (nick.runes.length > 10) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '昵称最多 10 个字。',
          en: 'Nickname must be at most 10 characters.',
          ja: 'ニックネームは10文字以内です。',
        ),
      );
    }
    if (email.isNotEmpty && !_isValidEmail(email)) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '邮箱格式不正确。',
          en: 'Invalid email format.',
          ja: 'メール形式が正しくありません。',
        ),
      );
    }
    try {
      await BoltFoxApi.changeNickName(nick);
      _currentUser.nickname = nick;
      _currentUser.email = email.trim();
      _currentUser.signature = signature.trim();
      _currentUser.avatarColor = avatarColor;
      notifyListeners();
      return ActionFeedback(
        success: true,
        message: tr(
          zh: '个人信息已更新。',
          en: 'Profile updated.',
          ja: 'プロフィールを更新しました。',
        ),
      );
    } catch (error) {
      return _apiFailure(error);
    }
  }

  // 2026-08-17 删除：`refreshAlbum`（拉 `getUserProductImgList` 铺 `_albumPhotos`）。
  // 「我的相册」的数据源只剩设备列表([refreshDevices])与投屏成功记录([refreshCastRecords])；
  // 图库列表原来只喂两处（再次投屏取原图、默认设备「第一台有照片的」），两处都已改掉。
  // 它还带过一个失败模式：与 getDevices 并列在首屏 Promise.all 里，一个用不上的接口
  // 有权把整页打成「加载失败」。

  /// 查询设备一键清除状态（对齐小程序 `getUserProductClearImg`）：`true`=已清除、`false`=未清除、
  /// `null`=查询失败（接口层 showError:false 静默，下次进入/切换设备会再查）。
  ///
  /// 设备在别处被执行过清空时（设备上的照片已被清掉），「我的相册」据此弹「请重新上传图片」提醒。
  /// ⚠️ 2026-08-17 图库列表接口整体下线后，这一条仍**明确保留**：它查的是 UserProduct 侧的
  /// 设备状态，不属于图库列表链路，也是用户唯一能感知到「设备在别处被清空过」的入口。
  Future<bool?> fetchDeviceClearImgStatus(String userProductId) async {
    if (userProductId.isEmpty) {
      return null;
    }
    try {
      final data = await BoltFoxApi.getUserProductClearImg(userProductId);
      // retData 通常就是 0/1，兼容后端包一层对象返回 { isClearImg } 的情况。
      final cleared = data is Map ? data['isClearImg'] : data;
      return _asInt(cleared) == 1;
    } catch (_) {
      return null;
    }
  }

  /// 复位设备一键清除标记（对齐小程序 `editUserProduct({userProductId, isClearImg:0})`）：
  /// 用户确认「重新上传」提醒后置 0，后端不再返回「已清除」，避免每次进入图库都弹。静默失败。
  Future<void> resetDeviceClearImgFlag(String userProductId) async {
    if (userProductId.isEmpty) {
      return;
    }
    try {
      await BoltFoxApi.editUserProduct(
        userProductId: userProductId,
        isClearImg: 0,
      );
    } catch (_) {
      // 复位失败静默（下次进入图库会再次提醒）。
    }
  }

  /// 选中的投屏记录 → 待删设备槽位（对齐小程序 `album/list.js resolveDeleteTargets`）。
  ///
  /// 只认**这条投屏记录自己的 `imgIndex`**：网格本就是按投屏成功记录铺的，记录里的这份索引
  /// 正是投屏成功时 `editUserProductImgRecord` 写进去的那个设备物理位置。
  /// 任意一条缺索引/非法（含越界，IMG_MASK 只有 12 字节 96 位）就返回 null，由调用方**整批终止**——
  /// 刻意不按设备掩码或列表顺序推算，也不在 0x12 报错后改删别的槽位，那只会删掉别人的图。
  ///
  /// ⚠️ 0 是合法槽位（相框第一个位置），判空一律用 `< 0`，绝不能用真假值。
  /// （2026-08-10 起索引改取投屏记录这份；2026-08-17 图库列表下线后它成了唯一来源。）
  static List<int>? resolveDeleteSlots(Iterable<CastRecord> records) {
    final slots = <int>[];
    for (final record in records) {
      final slot = record.imageIndex;
      if (slot == null || slot < 0 || slot >= 96) {
        return null;
      }
      if (!slots.contains(slot)) {
        slots.add(slot);
      }
    }
    return slots.isEmpty ? null : slots;
  }

  /// 删除「我的相册」选中照片的**设备侧那一半**：删设备固件对应槽位(CMD 0x12)，
  /// 若删到「屏幕当前正显示的图片」再刷屏(0x24)切到最近的有图槽位。
  ///
  /// [deviceId] = 这些记录所属设备（列表本就是按它向后端筛出来的）；
  /// [slots] = [resolveDeleteSlots] 解析出的槽位（缺索引整批终止发生在调用方，进到这里的都合法）。
  /// 未连接会自动扫连（对齐小程序 `ensureConnectedForAction`），连不上即中止、不动后端。
  ///
  /// ⚠️ 2026-08-20 口径变更（同步小程序 `album/list.js confirmDeleteSelected` 第 4 步）：
  /// **设备侧与记录侧互不阻断**——除了「前置条件不满足」（没选照片 / 设备不存在 / 连不上）之外，
  /// 设备侧无论成功、失败还是根本没应答，都把原因记进 [DevicePhotoDeleteOutcome.deviceError]
  /// 返回给调用方，由调用方**照常**去删投屏记录；反过来记录接口失败也不回滚设备。
  /// 改前是「非良性结果码直接判失败」：设备忙(0x0B)/Flash 写失败(0x04)/断连超时时整批中止，
  /// 记录一条都不删，用户回到相册看见照片还在、再点一次还是同样的报错。
  ///
  /// 代价（产品已确认接受）：设备真的没删掉时记录先没了 → 相框上那张图成了「相册里看不到、
  /// 端上也没有它 imgIndex」的幽灵图，只能靠「一键清空」清理。
  ///
  /// ⚠️ 2026-08-17：这里**不再删任何后端图片记录**（原先第 2 步的 `delUserProductImg` 已随
  /// 整套「我的图库」接口下线）。端上删除 = 删设备槽位(0x12) + 删来源投屏记录
  /// （后者由调用方 [deleteCastRecords] 做，允许部分失败），图库照片的清理归后端。
  Future<DevicePhotoDeleteOutcome> deleteDevicePhotoSlots({
    required String deviceId,
    required List<int> slots,
  }) async {
    if (slots.isEmpty) {
      return DevicePhotoDeleteOutcome(
        blockedMessage: tr(
          zh: '请先选择要删除的照片。',
          en: 'Select photos to delete first.',
          ja: '削除する写真を選択してください。',
        ),
      );
    }
    final targetMatches = _devices
        .where((device) => device.id == deviceId)
        .toList();
    if (targetMatches.isEmpty) {
      return DevicePhotoDeleteOutcome(
        blockedMessage: tr(
          zh: '电子纸设备不存在。',
          en: 'E-paper device not found.',
          ja: '電子ペーパーが見つかりません。',
        ),
      );
    }
    // 未连接到「照片所属设备」则自动扫连（对齐小程序 ensureConnectedForAction），连不上中止、不动后端。
    //
    // ⚠️ 这道连接前置在 2026-08-20 的「两半互不阻断」里**刻意保留**（小程序侧同样保留）：
    // 连不上设备时端上一条 0x12 都没发出去，照删记录等于用户完全没碰到设备就丢了记录。
    // 「连不上设备时要不要也照删记录」是另一个待定的决定。
    if (!_sessionMatches(targetMatches.first)) {
      final connectFeedback = await connectDevice(deviceId);
      if (!connectFeedback.success) {
        return DevicePhotoDeleteOutcome(
          blockedMessage: connectFeedback.message,
        );
      }
    }
    final client = BleController.instance.client;
    if (!client.connected) {
      return DevicePhotoDeleteOutcome(
        blockedMessage: tr(
          zh: '请先连接电子纸设备',
          en: 'Please connect the e-paper device first.',
          ja: '先に電子ペーパーを接続してください。',
        ),
      );
    }
    String refreshWarn = '';
    String deviceError = '';
    // 1) 先读一次设备当前 IMG_MASK(0x01)，把待删槽位分成「设备上还在的」和「已经不在的」两拨。
    //
    //    为什么要读：同一台设备可能被两部手机连过。另一部手机删掉了 A，设备上只剩 B、C，
    //    而本机列表是按后端记录铺的，A 那条还在 → 相册里仍是 A/B/C 三张。这时把 A 的空槽位
    //    一起塞进 0x12 的掩码，固件回 0x07，**整批**删除被打回，B、C 也跟着删不掉。
    //
    //    口径（2026-08-10 产品确认）：删除以「从我的相册里消失」为准，设备侧尽力而为——
    //      · 槽位在设备上已空 → 跳过设备侧，来源记录照删，不影响同批其它张；
    //      · 槽位上现在躺着另一端后传的别的图 → 仍按索引删掉，不做内容比对（产品明确接受：
    //        索引是我们唯一的定位手段，根治要靠后端的 imgIndex 唯一性规则）；
    //      · 回读失败（设备忙 / 刚断连 / 应答超时）→ **不拦**，按记录里的真实 imgIndex 原样下发，
    //        交给 0x12 的良性结果码兜底（2026-08-20：设备忙原本在这里直接中止，与「两半互不阻断」
    //        冲突——回读只是一次辅助优化，它失败不该连记录也一起删不掉）。
    FrameDeviceInfo? info;
    try {
      info = await client.readTransferInfo();
    } catch (e) {
      debugPrint('[相册删除] 回读设备掩码(0x01)失败，按选中槽位原样下发：$e');
      info = null;
    }
    // 掩码读不到时 occupied 为 null——**一张都不能判「已不在」**，否则弱网/刚断连时会退化成
    // 「记录全删了、图还留在设备上」。注意与「设备真的一张图都没有」区分：后者是 12 个 0 的
    // 合法掩码，全判 gone 正是对的。
    final occupied = info == null
        ? null
        : FrameProtocol.maskToIndexes(info.imgMask);
    final split = splitSlotsByDeviceMask(slots, occupied);

    // 2) 设备上还在的那些槽位交给 0x12；一张都不剩就整条指令都不发，直接交回调用方删记录。
    if (split.onDevice.isNotEmpty) {
      try {
        final newMask = await client.deleteImage(split.onDevice);
        // 只在删到「屏幕当前显示的图片」时才刷屏：切到删除后最近的有图槽位；
        // 设备已无图片则不主动刷屏——固件在清空后会自动刷成空屏（无单独清屏指令）。
        if (info != null && split.onDevice.contains(info.curImgIndex)) {
          final remaining = FrameProtocol.maskToIndexes(newMask);
          if (remaining.isNotEmpty) {
            try {
              await client.refreshScreen(remaining.first);
            } catch (_) {
              // 刷屏失败不抛出——设备侧已删成功，抛出会中止记录删除造成两边不一致。
              refreshWarn = tr(
                zh: '已删除，但屏幕刷新失败，请稍后手动刷新屏幕。',
                en: 'Deleted, but screen refresh failed. Please refresh manually later.',
                ja: '削除しましたが画面更新に失敗しました。後で手動で更新してください。',
              );
            }
          }
        }
      } catch (e) {
        // 「图片不存在(0x05) / 掩码不一致(0x07)」：要删的图设备上本来就没有——上一步的掩码回读
        // 与真正下发之间，另一端仍可能再删一张，所以这里还要兜一次。这类结果码按已删继续删记录。
        if (FrameBleException.isSkippableDelete(e)) {
          debugPrint('[相册删除] 0x12 回了「图片不存在/掩码不一致」，按设备侧已无此图继续删记录：$e');
        } else if (FrameProtocol.isBusyMessage(e.toString())) {
          // 设备忙(0x0B)：设备答得上话、只是暂时在忙，别归成通用「设备删除失败」。
          deviceError = tr(
            zh: '当前电子纸设备繁忙，请稍后重试',
            en: 'The e-paper device is busy, please try again later.',
            ja: '電子ペーパーが処理中です。しばらくしてから再試行してください。',
          );
          debugPrint('[相册删除] 设备删除(0x12)遇到设备忙，不影响后续记录删除：$e');
        } else {
          // Flash 写失败(0x04)、传输中断(0x09)、断连/应答超时：设备侧「可能真的没删掉」。
          // 只记下来，不再中止——记录侧照删（2026-08-20 口径）。
          deviceError = tr(
            zh: '电子纸设备删除失败，请检查电子纸设备连接后重试。',
            en: 'Failed to delete from the e-paper device. Check the connection and retry.',
            ja: '電子ペーパーからの削除に失敗しました。接続を確認して再試行してください。',
          );
          debugPrint('[相册删除] 设备删除(0x12)失败，不影响后续记录删除：$e');
        }
      }
    } else {
      debugPrint('[相册删除] 选中照片在设备上都已不存在，跳过 0x12，直接删后端记录');
    }
    return DevicePhotoDeleteOutcome(
      deviceError: deviceError,
      refreshWarn: refreshWarn,
    );
  }

  /// 把待删槽位按设备真实 IMG_MASK 分成两拨（2026-08-10，对齐小程序 album/list.js
  /// `splitSlotsByDeviceMask`）：
  ///
  /// - [DeleteSlotSplit.onDevice]：掩码里有这一位 → 设备上确实还有图，照常发 `0x12`
  ///   （哪怕现在躺在这个位置的是另一端后传的另一张图，也按索引删，产品口径）；
  /// - [DeleteSlotSplit.gone]：掩码里没有这一位 → 另一端已经删过，设备侧跳过，只删后端记录。
  ///
  /// ⚠️ [occupied] 为 null（掩码读不到）时**一张都不能判 gone**，整体按 onDevice 返回，
  /// 交给 `0x12` 的良性结果码兜底；否则会变成「记录全删了、图还留在设备上」。
  /// 空列表是**合法掩码**（设备真的一张图都没有），此时全判 gone 才是对的——两者不可混同。
  static DeleteSlotSplit splitSlotsByDeviceMask(
    List<int> slots,
    List<int>? occupied,
  ) {
    if (occupied == null) {
      return DeleteSlotSplit(onDevice: List<int>.of(slots), gone: const []);
    }
    return DeleteSlotSplit(
      onDevice: slots.where(occupied.contains).toList(),
      gone: slots.where((slot) => !occupied.contains(slot)).toList(),
    );
  }

  // 2026-08-17 一并删除（都以图库账本 `_albumPhotos` 为输入，账本没了它们也无从成立）：
  //   · `devicePhotoAbnormalMessage`「照片在此电子纸设备异常，请删除重新上传」——旧删除链路里
  //     「记录没给 imgIndex、又推算不出位置」时的提示。新口径下缺索引在页面侧就整批终止了
  //     （见 [resolveDeleteSlots]），到不了这一步。设备在别处被一键清空的提醒是另一条链路，
  //     走 `getUserProductClearImg`（[fetchDeviceClearImgStatus]），**保留**。
  //   · `refreshGalleryPhotoOnScreen`（手动「刷新屏幕」0x24）——2026-08-04 页面合并后就没有调用方
  //     （底部第一枚圆钮改成了「再次投屏」），文案 `galRefreshScreen` / `galRefreshing` 同步删除。
  //     删除时删到屏显图的**自动补刷屏**不受影响，仍在 [deleteDevicePhotoSlots] 里。
  //   · `_resolveDeviceImageIndex` / `_inferDeviceImageIndex`（按上传先后推算槽位的回退）——
  //     推算的输入是「同一台设备在库照片的排队顺序」，而唯一的索引来源已收敛成投屏记录自己的
  //     `imgIndex`，缺了就整批终止，刻意不再推算。

  /// 投屏记录列表：`/Client/UserProduct/getUserProductImgRecordList`。
  ///
  /// 映射为 [CastRecord]，仅在后端返回非空时替换本地列表（失败保留当前数据）。
  /// [deviceUploadState] 传 1=只取成功 / 0=只取失败（对齐小程序 records.js 按 tab 传 filter，
  /// 后端按状态过滤），缺省不传取全部。分状态拉取避免 >100 条时本地切片丢行。
  Future<ActionFeedback> refreshCastRecords({
    String? userProductId,
    int? deviceUploadState,
  }) async {
    final epoch = _sessionEpoch;
    try {
      final data = await BoltFoxApi.getUserProductImgRecordList({
        'pageIndex': 1,
        'pageSize': 100,
        'userProductId': ?userProductId,
        'deviceUploadState': ?deviceUploadState,
      });
      if (epoch != _sessionEpoch) {
        // 会话代际已变（登出/换号）：丢弃旧会话的在途响应，防跨账号串屏。
        return ActionFeedback(success: true, message: '');
      }
      final rows = extractApiRows(data);
      // 后端为准：即使返回空也覆盖本地（无记录时应显示空态，不保留旧数据）。
      final mapped = <CastRecord>[];
      for (var i = 0; i < rows.length; i++) {
        mapped.add(_castRecordFromJson(rows[i], i));
      }
      _castRecords
        ..clear()
        ..addAll(mapped);
      _castRecordsLoaded = true;
      _castRecordsLoadError = false;
      notifyListeners();
      return ActionFeedback(
        success: true,
        message: tr(
          zh: '投屏记录已更新。',
          en: 'Records refreshed.',
          ja: '投映履歴を更新しました。',
        ),
      );
    } catch (error) {
      // 失败也结束首屏 loading，并记失败标记（对齐小程序 catch 里的 `setData({loading:false})`）。
      _castRecordsLoaded = true;
      _castRecordsLoadError = true;
      notifyListeners();
      return _apiFailure(error);
    }
  }

  /// 「我的」页「我的相册」卡片的张数：**全部设备**的投屏成功记录条数（写入 [minePhotoCount]）。
  ///
  /// 与「我的相册」列表同口径（`deviceUploadState:1` + 本地按状态兜底），只是不带
  /// `userProductId`——卡片统计的是全部设备的合计，不是当前选中的那台。
  ///
  /// **不写 [castRecords]**：那份列表是图库页/投屏管理页按各自的设备与状态条件拉的，
  /// 被这里的全量结果覆盖会串页（对齐小程序 `api.getProjectionSuccessCount` 只回数字）。
  ///
  /// 只要数字不要数据，所以尽量少打请求：
  /// - 后端认 `deviceUploadState` 时（整页都是成功记录），直接用分页元数据 `recordCount`，
  ///   一次请求就拿到真实总数，超过一页也不会被截断；
  /// - 后端忽略它时 `recordCount` 是「成功+失败」的合计，不能当成功数用，只能逐页翻并按状态数。
  ///   判停优先看 `pageCount`/`recordCount`，不拿「回包条数 < pageSize」当依据
  ///   （后端可能无视 pageSize 按默认值分页，见 [refreshFaq] 的同款坑）。
  Future<ActionFeedback> refreshMineCastSuccessCount() async {
    const pageSize = 100;
    // 安全上限：后端分页字段异常时不至于把请求打成死循环（同 refreshFaq）。
    const maxPages = 20;
    final epoch = _sessionEpoch;
    try {
      var pageIndex = 1;
      var scanned = 0;
      var counted = 0;
      var total = -1; // ≥0 = 后端过滤成立，直接采信 recordCount
      while (true) {
        final data = await BoltFoxApi.getUserProductImgRecordList({
          'pageIndex': pageIndex,
          'pageSize': pageSize,
          'deviceUploadState': 1,
        });
        if (epoch != _sessionEpoch) {
          // 会话代际已变（登出/换号）：丢弃旧会话的在途响应，防跨账号串数。
          return ActionFeedback(success: true, message: '');
        }
        final rows = extractApiRows(data);
        final success = rows
            .where((row) => _castStatusFromJson(row) == CastStatus.success)
            .length;
        scanned += rows.length;
        counted += success;

        final pageCount = data is Map ? _asInt(data['pageCount']) : 0;
        final recordCount = data is Map ? _asInt(data['recordCount']) : 0;

        // 整页都是成功记录 → 后端确实过滤了，recordCount 即成功总数，不必再翻页。
        if (recordCount > 0 && rows.isNotEmpty && success == rows.length) {
          total = recordCount;
          break;
        }
        // 空页 = 没有更多了。
        if (rows.isEmpty || pageIndex >= maxPages) {
          break;
        }
        if (pageCount > 0 && pageIndex >= pageCount) {
          break;
        }
        if (pageCount == 0 && recordCount > 0 && scanned >= recordCount) {
          break;
        }
        // 两个元数据都没有时，才退回按「不满一页即最后一页」判断。
        if (pageCount == 0 && recordCount == 0 && rows.length < pageSize) {
          break;
        }
        pageIndex++;
      }

      _mineCastSuccessCount = total >= 0 ? total : counted;
      _mineCastSuccessLoaded = true;
      notifyListeners();
      return ActionFeedback(success: true, message: '');
    } catch (error) {
      // 失败保留上次成功值（弱网进「我的」把张数清零，用户会以为照片没了）；
      // 首屏加载态照样结束，否则数字永远停在占位 `--`。
      _mineCastSuccessLoaded = true;
      notifyListeners();
      return _apiFailure(error);
    }
  }

  /// 批量删除投屏记录（「我的相册」删照片时连同来源记录一并删，否则删掉的照片还会留在列表里）。
  ///
  /// 后端没有批量接口，这里串行逐条调用；**允许部分失败**——设备槽位与相册记录此时已经删掉，
  /// 不能因为记录没删干净就整体报错回滚（对齐小程序 `api.deleteProjectionRecords`）。
  /// 返回 `(total, failed)` 由调用方决定提示文案。
  Future<({int total, int failed})> deleteCastRecords(
    Iterable<String> recordIds,
  ) async {
    final ids = recordIds.where((id) => id.isNotEmpty).toSet().toList();
    var failed = 0;
    for (final id in ids) {
      try {
        await BoltFoxApi.delUserProductImgRecord(id);
        _castRecords.removeWhere((record) => record.id == id);
      } catch (_) {
        failed += 1;
      }
    }
    if (ids.isNotEmpty) {
      notifyListeners();
    }
    return (total: ids.length, failed: failed);
  }

  /// 删除投屏记录：先调用 `/Client/UserProduct/delUserProductImgRecord`，成功后移除本地。
  Future<ActionFeedback> deleteCastRecord(String recordId) async {
    try {
      await BoltFoxApi.delUserProductImgRecord(recordId);
    } catch (error) {
      return _apiFailure(error);
    }
    _castRecords.removeWhere((record) => record.id == recordId);
    notifyListeners();
    return ActionFeedback(
      success: true,
      message: tr(zh: '记录已删除。', en: 'Record deleted.', ja: '履歴を削除しました。'),
    );
  }

  /// 重命名设备：调用 `/Client/UserProduct/editUserProduct`，成功后更新本地名称。
  Future<ActionFeedback> renameDevice(String deviceId, String name) async {
    final value = name.trim();
    if (value.isEmpty) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '设备名称不能为空。',
          en: 'Device name cannot be empty.',
          ja: '端末名は必須です。',
        ),
      );
    }
    // 对齐小程序 utils/device-name.js：按 Unicode 码点计数，最多 20 个字符。
    // 使用 runes，emoji / 生僻字不会被 UTF-16 代理对误算成两个字符。
    if (value.runes.length > 20) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '设备名称最多20个字符',
          en: 'Device name must be at most 20 characters.',
          ja: '端末名は20文字以内です。',
        ),
      );
    }
    try {
      await BoltFoxApi.editUserProduct(
        userProductId: deviceId,
        productName: value,
      );
      _findDevice(deviceId).name = value;
      notifyListeners();
      return ActionFeedback(
        success: true,
        message: tr(zh: '设备名称已更新。', en: 'Device renamed.', ja: '端末名を更新しました。'),
      );
    } catch (error) {
      return _apiFailure(error);
    }
  }

  /// 切换当前查看 / 操作的设备（不改变蓝牙连接态）。
  void selectDevice(String deviceId) {
    if (_selectedDeviceId == deviceId) {
      return;
    }
    _selectedDeviceId = deviceId;
    notifyListeners();
  }

  /// 拉取设备列表：`/Client/UserProduct/getUserProductList`，映射为 [DeviceItem]。
  ///
  /// 蓝牙相关字段（电量 / IMG_MASK / 连接态）后端不下发，先给默认值，连接后由 BLE 更新。
  /// 后端返回为准整体替换本地列表（含空列表）；请求失败保留当前列表。
  Future<ActionFeedback> refreshDevices() async {
    final epoch = _sessionEpoch;
    try {
      final data = await BoltFoxApi.getUserProductList({
        'pageIndex': 1,
        'pageSize': 100, // 对齐小程序 getDevices({pageSize:100})
      });
      if (epoch != _sessionEpoch) {
        // 会话代际已变（登出/换号）：丢弃旧会话的在途响应，防跨账号串屏。
        return ActionFeedback(success: true, message: '');
      }
      final rows = extractApiRows(data);
      // 后端为准：即使返回空也覆盖本地（删到 0 台时应显示空态，不保留旧数据）。
      // 同一实体相框被重复绑定时，按硬件序列号折叠成一行（对齐小程序 dedupeDevices）。
      final mapped = _dedupeDevicesBySerial(rows.map(_deviceFromJson).toList());
      // 已连接回填：后端不存连接态/BLE 会话，若一律 connected:false 替换，
      // 正连着的设备会被错显示成「未连接」（改名后刷新列表时尤其明显）。
      // 按序列号与活动会话容错交叉匹配回填（与小程序 loadHomeState/loadDevices 同规则）。
      for (final device in mapped) {
        // 蓝牙字段回填：后端**不下发**电量/内存/索引/固件等，_deviceFromJson 一律给 0/null。
        // 若整体替换而不回填，每次进首页/设备列表（都会调本方法）都会把 BLE 读到的
        // 电量抹成 0%、内存抹成 0/32——正是「切换页面后电量变 0%」的根因。
        // 小程序同样是合并而非覆盖（home.js:424 / device/list.js:86 的 `?? cached`）。
        _carryOverBleFields(device);
      }
      // 稳定身份的第三档来源：登记表（顺序见 [DeviceIdentityRegistry]）。
      // 前两档都没给出完整 ID 时才查表兜底；反过来，后端这次下发了完整 ID 的记录顺手登记，
      // 供以后接口没下发时使用。整条补齐链只为一件事：别让身份闸把好设备拦在扫描之前。
      await _completeDeviceIdentities(mapped);
      // 已连接回填：后端不存连接态/BLE 会话，若一律 connected:false 替换，
      // 正连着的设备会被错显示成「未连接」（改名后刷新列表时尤其明显）。
      // 按序列号与活动会话容错交叉匹配回填（与小程序 loadHomeState/loadDevices 同规则）。
      //
      // ⚠️ 必须排在**身份补齐之后**：`_sessionMatches` 只认完整 6 字节 ID，
      // 后端这一行没下发 deviceId 时，身份要靠 `_carryOverBleFields`（本地上一版）与
      // `_completeDeviceIdentities`（登记表）补。原来这行排在两者之前，补齐还没发生就先判了，
      // 于是刷新一次列表，正连着的设备就整体掉成「未连接」——「明明连着却提示请先连接设备」
      // （轮播设置/一键清空等入口门禁）正是从这里来的。
      for (final device in mapped) {
        device.connected = _sessionMatches(device);
      }
      if (epoch != _sessionEpoch) {
        return ActionFeedback(success: true, message: '');
      }
      _devices
        ..clear()
        ..addAll(mapped);
      if (!_devices.any((device) => device.id == _selectedDeviceId)) {
        // 选中项已不在最新列表（另一端解绑 / 接口偶发返回不全）：**置空，而不是静默切到
        // 第一台**。刷新可能在详情/清空/删除页停留期间由其它页面并发触发，静默换台会让
        // 这些页面上的破坏性操作（一键清空、删除设备）落到另一台设备。置空对首页无影响
        // （_activeDevice 自带「选中→已连接→第一台」推导），详情页由 _findDevice 的
        // 占位设备兜底渲染。
        _selectedDeviceId = '';
      }
      _devicesLoaded = true;
      _devicesLoadError = false;
      notifyListeners();
      return ActionFeedback(
        success: true,
        message: tr(
          zh: '设备列表已更新。',
          en: 'Devices refreshed.',
          ja: '端末一覧を更新しました。',
        ),
      );
    } catch (error) {
      // 失败也结束首屏 loading，并记失败标记（对齐小程序 catch 里的 `setData({loading:false})`）。
      _devicesLoaded = true;
      _devicesLoadError = true;
      notifyListeners();
      return _apiFailure(error);
    }
  }

  /// 拉取单台设备详情（含 OTA 固件字段）：`/Client/UserProduct/getUserProductDetail`。
  ///
  /// 对齐小程序 `ota.js` 的 `api.getDeviceDetail`：把后端下发的
  /// `isUpdate/newVersionNo/downloadPath` 合并到本地 [DeviceItem]，供 OTA 页判定是否可升级。
  /// 成功返回更新后的 [DeviceItem]（本地已存在则原地更新并 [notifyListeners]），失败返回 null。
  ///
  /// **必须带上设备当前固件版本号**：swagger 里 `productVersionNo`(设备当前版本号) 是入参，
  /// 后端拿它跟最新版本比对，才能算出 `isUpdate` / `newVersionNo`。不传的话后端无从比较，
  /// 「检查更新」永远得不到正确结果。版本号来自连接后 BLE 0x01 读到的固件版本（后端不存）。
  Future<DeviceItem?> fetchDeviceFirmwareInfo(String deviceId) async {
    try {
      String? currentVersion;
      try {
        final local = _findDevice(deviceId);
        if (local.firmwareVersion.isNotEmpty) {
          currentVersion = local.firmwareVersion;
        }
      } catch (_) {
        // 本地没这台设备（如刚绑定还没入列表）时不带版本号，由后端自行判断。
      }
      final data = await BoltFoxApi.getUserProductDetail(
        userProductId: deviceId,
        productVersionNo: currentVersion,
      );
      Map<String, dynamic>? row;
      if (data is Map) {
        row = (data).map((k, v) => MapEntry(k.toString(), v));
      } else {
        final rows = extractApiRows(data);
        if (rows.isNotEmpty) row = rows.first;
      }
      if (row == null) return null;
      row.putIfAbsent('userProductId', () => deviceId);
      final detail = _deviceFromJson(row);

      DeviceItem? device;
      try {
        device = _findDevice(deviceId);
      } catch (_) {
        device = null;
      }
      if (device != null) {
        device.isUpdate = detail.isUpdate;
        device.newVersionNo = detail.newVersionNo;
        device.downloadPath = detail.downloadPath;
        device.firmwareSize = detail.firmwareSize;
        if (detail.firmwareVersion.isNotEmpty) {
          device.firmwareVersion = detail.firmwareVersion;
        }
        notifyListeners();
        return device;
      }
      return detail;
    } catch (_) {
      return null;
    }
  }

  /// 绑定设备：`/Client/UserProduct/addUserProduct`，成功后重新拉取列表取服务端 id。
  ///
  /// productId 对齐小程序 `api.js bindDevice`：蓝牙扫描到的设备本身不带 productId，绑定前先拉产品列表，
  /// 用扫描到的设备(型号 [model] / 屏幕 [screen] / 名称 [scanName])逐条打分匹配出对应产品的 productId
  ///（[_resolveProductId]）。匹配不到 / 拉列表失败都中止绑定并明确提示，绝不缺 productId 硬往后端发请求。
  Future<ActionFeedback> bindDevice({
    required String productName,
    required String productSerialNo,
    String model = '',
    String screen = '',
    String scanName = '',
  }) async {
    final completeSerial = canonicalDeviceSerial(productSerialNo);
    if (completeSerial.isEmpty) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '绑定失败：未读取到完整的6字节电子纸设备ID，请重新连接后再试。',
          en: 'Binding failed because the complete 6-byte e-paper device ID was not read. Reconnect and try again.',
          ja: '完全な6バイトの電子ペーパーIDを取得できなかったため追加できません。再接続してお試しください。',
        ),
      );
    }
    final resolved = await _resolveProductId(
      model: model,
      screen: screen,
      scanName: scanName,
    );
    if (resolved.productId == null) {
      return ActionFeedback(success: false, message: resolved.error!);
    }
    try {
      final saved = await BoltFoxApi.addUserProduct(
        productId: resolved.productId!,
        productName: productName,
        productSerialNo: completeSerial,
      );
      // 2026-08-12（同步小程序）：**重新绑定一台曾经解绑过的设备**时，后端会把它上次保存的
      // 名字原样带回来（`ClientUserProductDetailApiOut.productName`）。绑定成功后的命名弹窗
      // 要带出这个名字，而不是又给一个默认名 —— 所以这里**以后端回带的为准**，
      // 不能让本地拼的默认名盖在它后面（小程序当初正是栽在这个覆盖顺序上）。
      final backendName = _backendProductName(saved);
      await refreshDevices();
      if (backendName.isNotEmpty) {
        for (final device in devices) {
          if (verifiedDeviceSerialMatch(device.serialNumber, completeSerial)) {
            device.name = backendName;
            notifyListeners();
            break;
          }
        }
      }
      return ActionFeedback(
        success: true,
        message: tr(
          zh: '电子纸设备已绑定。',
          en: 'E-paper device bound.',
          ja: '電子ペーパーをバインドしました。',
        ),
      );
    } catch (error) {
      return _apiFailure(error);
    }
  }

  /// 从 `addUserProduct` 出参里取后端回带的设备名（首次绑定时它就是我们刚提交的那个，
  /// 重新绑定曾解绑过的设备时是它上次保存的旧名）。取不到返回空串。
  String _backendProductName(dynamic data) {
    Map<String, dynamic>? row;
    if (data is Map) {
      row = data.map((k, v) => MapEntry(k.toString(), v));
    } else {
      final rows = extractApiRows(data);
      if (rows.isNotEmpty) {
        row = rows.first;
      }
    }
    final name = row?['productName'];
    return name is String ? decodeDisplayText(name).trim() : '';
  }

  /// 解析 addUserProduct 必传的 productId（对齐小程序 `api.js` 的 `bindDevice` + `productScore`）。
  ///
  /// 拉「全部产品列表」，用扫描到的设备(型号/屏幕/名称)与每个产品的
  /// (productName/model/screen/width/height) 拼成的文本做子串命中打分，取匹配度最高的一条的 productId。
  /// 与小程序一致：即便全 0 分也取排在最前的产品（productId 存在即可）；拉列表失败或选中产品无
  /// productId → 返回错误信息（productId 为 null），由 [bindDevice] 据此中止绑定。
  Future<({int? productId, String? error})> _resolveProductId({
    required String model,
    required String screen,
    required String scanName,
  }) async {
    List<Map<String, dynamic>> products;
    try {
      final data = await BoltFoxApi.getProductList({
        'pageIndex': 1,
        'pageSize': 100,
      });
      products = extractApiRows(data);
    } catch (_) {
      return (
        productId: null,
        error: tr(
          zh: '获取产品列表失败，无法确定产品，请稍后重试。',
          en: 'Failed to load the product list; cannot determine the product. Please retry.',
          ja: '製品リストの取得に失敗し、製品を特定できません。後で再試行してください。',
        ),
      );
    }
    final terms = [
      model,
      screen,
      scanName,
    ].map((s) => s.trim().toLowerCase()).where((s) => s.isNotEmpty).toList();
    int scoreOf(Map<String, dynamic> product) {
      final text = [
        product['productName'],
        product['model'],
        product['screen'],
        product['width'],
        product['height'],
      ].map((v) => (v ?? '').toString()).join(' ').toLowerCase();
      return terms.fold(
        0,
        (score, term) => score + (text.contains(term) ? 1 : 0),
      );
    }

    Map<String, dynamic>? best;
    var bestScore = -1;
    for (final product in products) {
      final score = scoreOf(product);
      if (score > bestScore) {
        bestScore = score;
        best = product;
      }
    }
    final productId = best == null ? 0 : _asInt(best['productId']);
    if (productId == 0) {
      return (
        productId: null,
        error: tr(
          zh: '未匹配到对应产品，请确认该电子纸设备在产品列表中存在。',
          en: 'No matching product found. Please confirm the e-paper device exists in the product list.',
          ja: '対応する製品が見つかりません。製品リストに存在するか確認してください。',
        ),
      );
    }
    return (productId: productId, error: null);
  }

  /// 删除 / 解绑设备：`/Client/UserProduct/delUserProduct`，成功后清理本地设备与相关数据。
  ///
  /// 删除前先断开该设备占用的 BLE 会话（对齐小程序 detail.js/list.js「删除前 disconnect」）：
  /// 否则删了记录但单连接还占着，设备不再广播，也无法被重新搜索/绑定。
  Future<ActionFeedback> deleteDevice(String deviceId) async {
    final trace = DeviceInteractionTrace('delete-device');
    try {
      DeviceItem? target;
      try {
        target = _findDevice(deviceId);
      } catch (_) {
        target = null;
      }
      final tasks = <Future<void>>[];
      if (target != null && _sessionMatches(target)) {
        // BLE 释放与后端解绑互不依赖，并行执行，避免两段耗时串行叠加。
        tasks.add(() async {
          try {
            await trace.measure('ble-disconnect', () async {
              await BleController.instance.disconnect();
            });
          } catch (_) {
            // 后端解绑成功后记录已不存在；BLE 释放失败不应把整体误报为删除失败。
            trace.mark('ble-disconnect-ignored');
          } finally {
            target!.connected = false;
          }
        }());
      }
      tasks.add(
        trace.measure('backend-delete', () async {
          await BoltFoxApi.delUserProduct(deviceId);
        }),
      );
      await Future.wait(tasks);
      // 直连缓存按 6 字节设备 ID 存 remoteId：记录都删了，句柄不该继续留在本机
      //（留着不会串台——重连前仍要 0x01 验身——但没有任何用处）。
      if (target != null) {
        unawaited(
          BleDirectConnectCache.instance.remove(target.serialNumber),
        );
      }
      // 身份登记表按后端记录主键存：记录都删了就得清掉这一条，
      // 否则后端复用 userProductId 时会把上一台的完整 ID 带回给新设备（用缓存制造串台）。
      unawaited(DeviceIdentityRegistry.instance.forget(deviceId));
      // 「最近绑定」若指向这台已解绑的设备就一并清掉，避免主键复用时把排序优先级
      // 错给另一台设备（见 [RecentlyBoundDevice]）。
      if (RecentlyBoundDevice.instance.value == deviceId) {
        unawaited(RecentlyBoundDevice.instance.clear());
      }
      _devices.removeWhere((device) => device.id == deviceId);
      _castRecords.removeWhere((record) => record.deviceId == deviceId);
      if (_selectedDeviceId == deviceId) {
        _selectedDeviceId = _devices.isEmpty ? '' : _devices.first.id;
      }
      notifyListeners();
      trace.mark('local-state-sync');
      trace.finish(success: true);
      return ActionFeedback(
        success: true,
        message: tr(
          zh: '电子纸设备已删除。',
          en: 'E-paper device deleted.',
          ja: '電子ペーパーを削除しました。',
        ),
      );
    } catch (error) {
      trace.finish(success: false);
      return _apiFailure(error);
    }
  }

  void updateDeviceSerial(String deviceId, String serialNumber) {
    final value = serialNumber.trim();
    if (value.isEmpty) {
      return;
    }
    _findDevice(deviceId).serialNumber = value;
    notifyListeners();
  }

  void setDeviceRole(String deviceId, DeviceRole role) {
    _findDevice(deviceId).role = role;
    notifyListeners();
  }

  void toggleCarousel(String deviceId, bool enabled) {
    final device = _findDevice(deviceId);
    device.carouselEnabled = enabled;
    device.playbackMode = enabled
        ? FramePlaybackMode.sequence
        : FramePlaybackMode.manual;
    device.carouselIntervalSeconds =
        FrameProtocolConfig.defaultCarouselIntervalSeconds;
    notifyListeners();
  }

  /// 设置设备轮播（对齐小程序 `slideshow.js applyPlayback`）：操作前确保目标设备已连接，再走 BLE
  /// `setPlayback` 下发播放模式(顺序 order / 随机 random / 关闭 manual) + 间隔秒，成功后更新本地。
  /// 未连接或活动会话属于其他设备时自动扫连目标设备；蓝牙失败统一返回连接错误并由页面还原开关。
  ///
  /// [enabled] 为 false 时下发 manual（关闭轮播）；为 true 时用 [mode]（manual 会被纠正为 sequence）。
  Future<ActionFeedback> setDeviceCarousel(
    String deviceId, {
    required bool enabled,
    FramePlaybackMode mode = FramePlaybackMode.sequence,
  }) async {
    final device = _findDevice(deviceId);
    final client = BleController.instance.client;
    if (!client.connected || !_sessionMatches(device)) {
      final connected = await connectDevice(deviceId);
      if (!connected.success) {
        return connected;
      }
    }
    final targetMode = !enabled
        ? FramePlaybackMode.manual
        : (mode == FramePlaybackMode.manual
              ? FramePlaybackMode.sequence
              : mode);
    final modeStr = targetMode == FramePlaybackMode.random
        ? 'random'
        : (targetMode == FramePlaybackMode.manual ? 'manual' : 'order');
    final intervalSeconds = device.carouselIntervalSeconds > 0
        ? device.carouselIntervalSeconds
        : FrameProtocolConfig.defaultCarouselIntervalSeconds;
    try {
      await client.setPlayback(modeStr, intervalSeconds);
      device.playbackMode = targetMode;
      device.carouselEnabled = enabled;
      device.carouselIntervalSeconds = intervalSeconds;
      notifyListeners();
      return ActionFeedback(
        success: true,
        message: tr(
          zh: '轮播设置已保存。',
          en: 'Slideshow setting saved.',
          ja: 'スライドショー設定を保存しました。',
        ),
      );
    } catch (_) {
      // 蓝牙链路失败（断联/超时等）统一友好提示，不把底层错误码抛给用户（对齐小程序）。
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '电子纸设备暂时无法连接',
          en: 'The e-paper device is temporarily unavailable.',
          ja: '電子ペーパーに一時的に接続できません。',
        ),
      );
    }
  }

  /// 一键清空设备：与固件交互删除设备物理内存中的全部照片，成功后再清后端记录并同步本地相册。
  /// 对齐小程序 detail.js confirmClearCopies：
  /// - 未连接不自动重连，直接提示「请先连接设备」；
  /// - 清空中途设备断联 / 连不上 / 应答超时 / 设备没删干净等蓝牙链路问题，统一提示「设备暂时无法连接」，
  ///   不把底层设备错误码抛给用户；后端接口类错误仍如实提示（避免误报成设备连不上）。
  Future<ActionFeedback> clearDeviceMemory(String deviceId) async {
    final trace = DeviceInteractionTrace('clear-device');
    final device = _findDevice(deviceId);
    final client = BleController.instance.client;

    // 清空需与固件交互：未连接不自动重连，直接提示先连接（对齐小程序 clearCopies 前置拦截）。
    //
    // `_sessionMatches(device)` 不可省：`client.connected` 只说明「App 连着某台设备」，
    // 不说明连的就是 `deviceId` 这台。0x12 删除全部照片是不可逆操作，另外三处与固件交互的
    // 入口（删图 :1525 / 刷屏 :1647 / 轮播 :2189）都有这道守卫，唯独这里漏了——
    // 「连着 B、详情页停在 A 点一键清空」就会把 B 的照片全删光。
    if (!client.connected || !_sessionMatches(device)) {
      trace.finish(success: false, stage: 'not-connected');
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '请先连接电子纸设备',
          en: 'Please connect the e-paper device first.',
          ja: '先に電子ペーパーを接続してください。',
        ),
      );
    }

    // 1) 设备优先：读设备信息(0x01)拿到已占槽位，一条 0x12 删除全部图片。
    //    固件清空后会自动刷成空屏（无单独清屏指令），不主动刷屏。
    //    任一蓝牙链路失败（断联 / 应答超时 / 未连接）或删完仍有残留 → 都视为设备侧未清成功。
    var deviceCleared = false;
    Object? clearError;
    // 清空前设备上的真实张数（0x01 的 IMG_MASK 占位数），成功提示里报给用户。
    // 2026-08-17：原先数的是图库账本 `_albumPhotos` 里这台设备的在库照片，账本已下线；
    // 设备掩码本就是更准的那一份（另一端删过的照片不会被算进来）。
    var clearedCount = 0;
    try {
      // 清空只依赖 0x01 的 IMG_MASK；不要附带读取固件版本 0x03。
      final info = await trace.measure(
        'read-core-info-0x01',
        client.readTransferInfo,
      );
      final indexes = FrameProtocol.maskToIndexes(info.imgMask);
      clearedCount = indexes.length;
      if (indexes.isEmpty) {
        deviceCleared = true;
        trace.mark('delete-images-0x12-skipped');
      } else {
        try {
          // deleteImage 应答等待已按张数放宽（每张 2s、下限 6s、上限 180s，见 device_ble.deleteImage），
          // 一次删几十张也不会一超 6s 就误判超时。返回删除后最新 IMG_MASK：仍有占用=没删干净。
          final newMask = await trace.measure(
            'delete-images-0x12',
            () => client.deleteImage(indexes),
          );
          deviceCleared = FrameProtocol.maskToIndexes(newMask).isEmpty;
        } catch (deleteError) {
          // 0x12 应答超时/断连——但不少固件其实已把图删干净了，只是应答异常/迟到
          //（设备逐张擦 flash 全删完才回一次应答，慢一点就顶到超时）。设备忙(0x0B)先短路交给下方 busy 分支。
          clearError = deleteError;
          if (FrameBleException.isSkippableDelete(deleteError)) {
            // 「图片不存在(0x05) / 掩码不一致(0x07)」这类结果码：要删的图设备上本来就没有，
            // 对「清空」而言已经达成，不该中断流程（2026-08-01 产品要求）。
            // 2026-08-10 起判据与「我的相册」删除**同一份实现**（协议层按结果码放行，
            // 不再各写一套中文文案匹配），对齐小程序 detail.js isBenignDeleteError 委托协议层。
            // 连回读核对都免了，直接按成功继续。
            deviceCleared = true;
            trace.mark('delete-images-0x12-benign-error');
          } else if (!FrameProtocol.isBusyMessage(deleteError.toString())) {
            // 回读校验（最多 3 次、每次间隔 4s）：设备可能还在擦除、此刻回不了 0x01，给它删完的时间；
            // 任一次读到空掩码就按成功，全部失败/仍有残留才判失败——治「一键清空 60 张误报设备无法连接」。
            FrameDeviceInfo? after;
            for (var attempt = 1; attempt <= 3 && after == null; attempt++) {
              if (attempt > 1) {
                await Future<void>.delayed(const Duration(seconds: 4));
              }
              try {
                after = await trace.measure(
                  'verify-core-info-0x01-attempt-$attempt',
                  client.readTransferInfo,
                );
              } catch (_) {
                after = null;
              }
            }
            if (after != null) {
              deviceCleared = FrameProtocol.maskToIndexes(
                after.imgMask,
              ).isEmpty;
            }
          }
        }
      }
    } catch (e) {
      clearError = e;
      deviceCleared = false;
    }
    // 设备忙(0x0B)：设备答得上话、只是暂时在忙，别归成「设备暂时无法连接」，原样提示稍后重试。
    if (!deviceCleared && FrameProtocol.isBusyMessage(clearError?.toString())) {
      trace.finish(success: false, stage: 'device-busy');
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '当前电子纸设备繁忙，请稍后重试',
          en: 'The e-paper device is busy, please try again later.',
          ja: '電子ペーパーが処理中です。しばらくしてから再試行してください。',
        ),
      );
    }
    if (!deviceCleared) {
      // 设备侧未清成功一律统一提示「设备暂时无法连接」，不把底层设备错误码抛给用户。
      trace.finish(success: false, stage: 'device-clear-failed');
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '电子纸设备暂时无法连接',
          en: 'The e-paper device is temporarily unavailable, please try again.',
          ja: '電子ペーパーに一時的に接続できません。',
        ),
      );
    }

    // 2) 设备清空成功后再清后端记录；接口类错误如实提示，不误报成设备连不上。
    try {
      await trace.measure('backend-clear', () async {
        await BoltFoxApi.clearUserProductImg(deviceId);
      });
    } catch (error) {
      trace.finish(success: false, stage: 'backend-clear-failed');
      return _apiFailure(error);
    }

    // 3) 同步本地：设备已无图（IMG_MASK 清零 / 当前索引复位）。
    //    「我的相册」渲染的是投屏成功记录，让它变空的是后端 clearUserProductImg 的级联删记录
    //    （2026-08-10 确认），本地不再另行标记——详情页返回后各页自会重拉。
    device.imageMask = 0;
    device.currentImageIndex = 0;
    // 实时张数也要归零：imageCount 优先读 liveImageCount，不清的话详情页会一直显示
    // 清空前的旧张数，直到下一次 0x01 回读落地。
    device.liveImageCount = 0;
    // 此处不再阻塞等待成功后的设备回读。确认页会先关闭 loading、提示成功并返回详情页，
    // 详情页 didPopNext 再以后台方式调用 refreshSelectedDeviceMemory（且仅读 0x01）。
    notifyListeners();
    trace.mark('local-state-sync');
    trace.finish(success: true);
    return ActionFeedback(
      success: true,
      message: tr(
        zh: '已清空电子纸设备照片，共移除 $clearedCount 张。',
        en: 'E-paper device photos cleared. Removed $clearedCount photos.',
        ja: '電子ペーパーの写真をクリアし、$clearedCount 枚を削除しました。',
      ),
    );
  }

  void switchLanguage(AppLanguage nextLanguage) {
    if (_language == nextLanguage) {
      return;
    }
    _language = nextLanguage;
    // 同步更新请求头 `language` 取值，保证后端按当前语言返回文案。
    ApiSession.instance.setLanguage(nextLanguage);
    notifyListeners();
  }

  /// 退出登录：调用 `/Client/User/loginOut` 并清除本地登录态。
  /// 接口失败也照常清除本地态，保证用户能回到登录页。
  Future<void> logout() async {
    try {
      await BleController.instance.disconnect();
    } catch (_) {
      // Local account cleanup must continue even if the platform BLE stack is
      // already unavailable.
    }
    try {
      await BoltFoxApi.loginOut();
    } catch (_) {
      // 退出登录接口失败时仍清除本地态。
    }
    // 必须在 currentUser 被清理前按当前用户 ID 删除 AI 协议同意记录；
    // 下次登录（即使还是同一账号）也需要重新确认。
    await AiServiceConsent.clear(_currentUser.id);
    // AI「上次停在哪一页」的记忆属于上一个用户，换账号后必须清掉（只在内存里）
    AiLastSession.clear();
    ApiSession.instance.clear();
    _sessionEpoch++; // 作废本会话在途请求的响应（见 _sessionEpoch 注释）
    // 清空列表还不够：照片本体还在内存/磁盘两层图片缓存里（见 ImageCacheCleanup）。
    ImageCacheCleanup.clearAll();
    // 退出登录同样清空上个账号的列表与首屏加载态，避免换账号后先看到上一个人的数据/空态。
    // 身份登记表按 userProductId 存，换账号后与新用户无关，必须整表清空。
    unawaited(DeviceIdentityRegistry.instance.clear());
    unawaited(RecentlyBoundDevice.instance.clear());
    _batteryCache.clear();
    _devices.clear();
    _castRecords.clear();
    _selectedDeviceId = '';
    _devicesLoaded = false;
    _castRecordsLoaded = false;
    _devicesLoadError = false;
    _castRecordsLoadError = false;
    _userLoaded = false;
    // 「我的相册」张数跟随账号：不清会让下一个登录的账号先看到上一个人的数字
    _mineCastSuccessCount = 0;
    _mineCastSuccessLoaded = false;
    _isLoggedIn = false;
    _currentUser.email = '';
    // 选图上限白名单跟随账号：不清会让下一个登录的账号继承上一个人的放宽额度
    CastUploadLimit.currentUserNo = '';
    notifyListeners();
  }

  /// 用户注销：调用 `/Client/User/userOff`，**成功后**才清除本地登录态与本地资产。
  ///
  /// 对齐小程序 `settings/index.js`：`userOff` 抛错则不 `clearSession`（账号仍有效、用户留在原页），
  /// 由调用方据返回的 [ActionFeedback] 决定是否跳登录页；不再无条件本地登出。
  Future<ActionFeedback> deleteAccount() async {
    try {
      await BoltFoxApi.userOff();
    } catch (error) {
      return _apiFailure(error);
    }
    try {
      await BleController.instance.disconnect();
    } catch (_) {
      // The backend account has already been deleted; continue local cleanup.
    }
    await AiServiceConsent.clear(_currentUser.id);
    // AI「上次停在哪一页」的记忆属于上一个用户，换账号后必须清掉（只在内存里）
    AiLastSession.clear();
    ApiSession.instance.clear();
    _sessionEpoch++; // 作废本会话在途请求的响应（见 _sessionEpoch 注释）
    // 账号已在服务端删除，本地缓存的照片本体更不该留（见 ImageCacheCleanup）。
    ImageCacheCleanup.clearAll();
    // 注销后清空全部本地资产（不按 ownerUserId 挑：后端已按 userToken 隔离，
    // 用户 id 到位的时机比列表回包晚，按它筛会把本人数据也筛掉），
    // 并把首屏加载态复位，下个账号进来才会重新走一次 loading 而不是直接看到上个账号的空态。
    unawaited(DeviceIdentityRegistry.instance.clear());
    unawaited(RecentlyBoundDevice.instance.clear());
    _batteryCache.clear();
    _castRecords.clear();
    _devices.clear();
    _selectedDeviceId = '';
    _devicesLoaded = false;
    _castRecordsLoaded = false;
    _devicesLoadError = false;
    _castRecordsLoadError = false;
    _userLoaded = false;
    // 「我的相册」张数跟随账号：不清会让下一个登录的账号先看到上一个人的数字
    _mineCastSuccessCount = 0;
    _mineCastSuccessLoaded = false;
    _isLoggedIn = false;
    // 选图上限白名单跟随账号：注销后必须清，否则下一个登录的账号会继承放宽额度
    CastUploadLimit.currentUserNo = '';
    _currentUser = UserProfile(
      id: 'USR-GUEST',
      nickname: tr(zh: '访客', en: 'Guest', ja: 'ゲスト'),
      email: '',
      avatarColor: const Color(0xFF6C757D),
      signature: tr(
        zh: '未登录状态，暂不保留用户资产。',
        en: 'Guest mode. User assets are not retained.',
        ja: '未ログイン状態のため、資産は保持されません。',
      ),
    );
    notifyListeners();
    return ActionFeedback(
      success: true,
      message: tr(zh: '账号已注销。', en: 'Account deleted.', ja: 'アカウントを削除しました。'),
    );
  }

  DeviceItem _findDevice(String deviceId) {
    final matches = _devices.where((device) => device.id == deviceId);
    if (matches.isNotEmpty) {
      return matches.first;
    }
    // 容错：id 可能已不在列表——删除/解绑设备后 notifyListeners 会让仍停留在
    // 详情页的那一帧先重建（selectedDevice），投屏记录也可能反查已删除的设备
    // （deviceById）。原来 firstWhere 无 orElse 直接抛 StateError 崩整帧；
    // 返回一个带 isPlaceholder 标记的「未连接占位设备」让这一帧安全渲染。
    return DeviceItem(
      isPlaceholder: true,
      id: deviceId,
      name: '',
      kind: '',
      screenType: FrameScreenType.inch589,
      batteryLevel: 0,
      charging: false,
      connected: false,
      role: DeviceRole.owner,
      serialNumber: '',
      hardwareVersion: '',
      firmwareVersion: '',
      imageMask: 0,
      currentImageIndex: -1,
      playbackMode: FramePlaybackMode.sequence,
      carouselIntervalSeconds:
          FrameProtocolConfig.defaultCarouselIntervalSeconds,
      carouselEnabled: false,
    );
  }

  /// 内置常见问题（接口失败 / 离线时的兜底文案，与小程序 guide 一致）。
  static List<FaqArticle> _seedFaqArticles() => [
    FaqArticle(
      id: 'faq-bind',
      question: '如何绑定设备?',
      answer:
          '1.确保电子纸设备已开机，并打开手机蓝牙。\n'
          '2.进入首页点击绑定设备，或「我的设备」。\n'
          '3.在设备列表中选择要连接的电子纸设备。\n'
          '4.点击「立即绑定」完成连接。\n'
          '若未搜索到电子纸设备，请确认电子纸设备在附近并重新搜索。',
    ),
    FaqArticle(
      id: 'faq-cast',
      question: '如何进行照片投屏?',
      answer: '进入首页，选择拍照或相册，确认照片后发送到已连接的电子纸设备。',
    ),
    FaqArticle(
      id: 'faq-album',
      question: '如何管理我的相册?',
      answer: '进入我的图库，可查看、删除和重新投屏已上传的照片。',
    ),
    FaqArticle(
      id: 'faq-cleared',
      question: '设备照片被清空怎么办?',
      answer: '请在我的图库中重新选择照片投屏，或检查电子纸设备存储状态。',
    ),
    FaqArticle(
      id: 'faq-full',
      question: '相框空间已满怎么办?',
      answer:
          '电子纸设备空间已满时，新的照片将无法继续投屏。您可以前往「我的相册」删除部分照片，'
          '或执行一键清空。清理完成后，再重新选择照片进行投屏即可。',
    ),
  ];

  /// 从登录接口 retData 中提取登录 token。
  ///
  /// retData 可能直接是 token 字符串，也可能是包含 token 字段的对象，
  /// 兼容 `userToken` / `token` / `accessToken` 等常见命名。
  String? _readToken(dynamic data) {
    if (data is String) {
      return data;
    }
    if (data is Map) {
      for (final key in const [
        'userToken',
        'token',
        'accessToken',
        'access_token',
        'Authorization',
      ]) {
        final value = data[key];
        if (value is String && value.isNotEmpty) {
          return value;
        }
      }
    }
    return null;
  }

  /// 从登录接口 retData 中提取 JWT。该凭证与业务 userToken 分开保存，
  /// 仅用于 `Authentication: Bearer <jwtToken>`。
  String? _readJwtToken(dynamic data) {
    if (data is Map) {
      for (final key in const ['jwtToken', 'jwt_token', 'JwtToken']) {
        final value = data[key];
        if (value is String && value.isNotEmpty) {
          return value;
        }
      }
    }
    return null;
  }

  /// 冷启动恢复本地持久化的登录态（进程被系统回收后重启的场景）。
  ///
  /// 恢复出 token 即先进已登录首页（资料后台刷新补齐），不让用户重新登录；
  /// 若 token 已在服务端失效，[_refreshUserInfo] 收到 401/406 会走
  /// [_handleSessionExpired] 清态回登录页——即「先乐观进门，失效再请出去」。
  /// 返回是否恢复出了登录态；无持久化 token 时不产生任何副作用。
  Future<bool> restoreSession() async {
    final restored = await ApiSession.instance.restore();
    if (!restored) {
      return false;
    }
    _isLoggedIn = true;
    notifyListeners();
    unawaited(refreshCurrentUser());
    return true;
  }

  /// 供页面主动刷新一次用户资料（对齐小程序 `mine.onShow` / `home.loadUserAvatar`）。
  /// 未登录直接跳过；成功后 `notifyListeners` 让「我的」等页面同步真实昵称/头像。
  Future<void> refreshCurrentUser() async {
    if (!_isLoggedIn) {
      // 未登录不拉接口，但首屏加载态照样要结束：否则 userLoaded 永远是 false，
      // 页面若单独依赖它（不像现在这样跟 devicesLoaded 或起来用）就会永久卡在占位/loading。
      _userLoaded = true;
      notifyListeners();
      return;
    }
    await _refreshUserInfo();
    notifyListeners();
  }

  /// 登录后尽力拉取一次用户信息，失败不阻断登录流程。
  Future<void> _refreshUserInfo() async {
    final epoch = _sessionEpoch;
    try {
      final data = await BoltFoxApi.getUserInfo();
      if (epoch != _sessionEpoch) {
        return; // 会话代际已变（登出/换号）：丢弃旧会话的在途响应
      }
      _applyUserInfo(data);
    } catch (error) {
      // 鉴权失效必须立刻清态回登录页：冷启动 restoreSession 恢复出过期 token 时，
      // 这里是第一个发现者——吞掉的话用户会停留在一个每个接口都报错的「假登录」壳里。
      if (error is ApiException && error.isAuthError) {
        _handleSessionExpired();
      }
      // 其余失败（网络抖动等）保留本地占位资料。
    } finally {
      // 成功/失败都结束首屏加载态：「我的」页据此从占位 `--` 切到真实统计。
      _userLoaded = true;
    }
  }

  /// 用后端用户信息覆盖本地展示字段（id / 昵称 / 邮箱 / 头像）。
  /// 相册/记录的 ownerUserId 映射时同样取 `_currentUser.id`，故 id 前后一致、过滤不会错乱。
  /// 字段名以后端 swagger `UserInfoApiOut` / `UserInfoDetailApiOut` 为准：
  /// `userNo`(用户编号) / `nickName` / `avatar` / `userEmail` / `userMobile` /
  /// `imgCount`(我的图片数) / `productCount`(我的设备数)。
  /// 后端**不下发** `id` / `avatarUrl` / `email` —— 之前把这些排在首位纯属猜测，
  /// 只是靠后面的兜底键侥幸命中；imgCount / productCount 更是完全没读，
  /// 「我的」页的照片数/设备数只能退回本地列表长度。
  void _applyUserInfo(dynamic data) {
    if (data is! Map) {
      return;
    }
    final id = data['userNo'];
    if (id != null && '$id'.isNotEmpty) {
      _currentUser.id = '$id';
      // 选图上限按 userNo 放宽（2026-08-01）：CastPhotoPicker 是静态入口、拿不到状态对象，
      // 在这里把 userNo 单向同步过去（退出登录时由 logout 清空）。
      CastUploadLimit.currentUserNo = _currentUser.id;
    }
    final nick = data['nickName'];
    if (nick is String && nick.isNotEmpty) {
      _currentUser.nickname = decodeDisplayText(nick);
    }
    final email = data['userEmail'];
    if (email is String && email.isNotEmpty) {
      _currentUser.email = email;
    }
    final avatar = data['avatar'];
    if (avatar is String) {
      _currentUser.avatarUrl = avatar;
    }
    _currentUser.imgCount = _asInt(data['imgCount']);
    _currentUser.productCount = _asInt(data['productCount']);
    // 2026-08-11（同步小程序）：登录/用户信息出参新增 `availableToken`。
    // 缺字段就保持 null（不要 _asInt 兜成 0），页面才分得清「没下发」和「余额是 0」。
    final availableToken = data['availableToken'];
    if (availableToken != null && '$availableToken'.trim().isNotEmpty) {
      final parsed = num.tryParse('$availableToken'.trim());
      _currentUser.availableToken = parsed == null
          ? null
          : (parsed < 0 ? 0 : parsed.toInt());
    }
    AiToken.cacheBalance(_currentUser.availableToken);
  }

  /// 把后端设备记录映射为 [DeviceItem]；蓝牙字段给安全默认值，连接后再由 BLE 更新。
  ///
  /// 字段名以后端 swagger 为准。
  /// 列表 `ClientUserProductApiOut`：`userProductId` / `productName` / `productImg` /
  /// `deviceId`(硬件序列号) / `width` / `height` / `shapeType`。
  /// 详情 `ClientUserProductDetailApiOut` 另有：`carouselInterval`(轮播间隔，单位**小时**) /
  /// `isUpdate` / `newVersionNo` / `downloadPath` / `compulsory` / `isClearImg` / `productId`。
  /// 注意：两个接口都**不下发**固件版本号与固件包大小（`productVersionNo`/`firmwareSize` 不存在），
  /// 固件版本只能连接后由 BLE 0x01 读取。
  DeviceItem _deviceFromJson(Map<String, dynamic> data) {
    final id = (data['userProductId'] ?? _nextId('dev')).toString();
    final name = (data['productName'] ?? '相框').toString();
    // 后端稳定身份只接收完整 6 字节 Device_ID；历史短 ID/占位值归为空，
    // 页面会明确提示删除记录后重新绑定，不再让短 ID 参与会话认领。
    final serial = canonicalDeviceSerial(data['deviceId']);
    final isUpdate = _asInt(data['isUpdate']);
    final newVersionNo = (data['newVersionNo'] ?? '').toString();
    final downloadPath = (data['downloadPath'] ?? '').toString();
    // 轮播间隔：后端单位是小时，本地统一存秒。未下发（列表接口）时用默认值。
    final carouselHours = _asInt(data['carouselInterval']);
    return DeviceItem(
      id: id,
      name: name,
      kind: '',
      // 由后端下发的屏幕像素宽高推断真实屏型（原来一律写死 589，3.7寸也被当 589）。
      // 连接复用 / 扫描匹配时据此按型号一票否决，防跨型号串台；只影响记录与该防护，
      // 图传尺寸走的是连上后读到的 info.screenType，不受此处影响。
      screenType: _screenTypeFromSize(data['width'], data['height']),
      // 原始宽高另存一份：屏型是「归一化后的枚举」，未下发时会回落 589，不能拿来展示分辨率。
      screenWidth: _asInt(data['width']),
      screenHeight: _asInt(data['height']),
      // 竖向导出旋转角（2026-08-04 新增字段）。_asInt 对缺失/非法值返回 0，
      // 正好等于产品要求的「没有这个参数就不旋转」，不需要额外兜底。
      // 兼容名只是大小写/后缀差异，后端定稿后可删。
      verticalRotation: _asInt(
        data['verticalRotation'] ??
            data['verticalRotationDegree'] ??
            data['verticalrotation'],
      ),
      batteryLevel: 0,
      charging: false,
      connected: false,
      role: DeviceRole.owner,
      serialNumber: serial,
      hardwareVersion: 'HW-1.0',
      // 后端不下发固件版本号，连接后由 BLE 0x01 readDeviceInfo 回填。
      firmwareVersion: '',
      imageMask: 0,
      currentImageIndex: -1,
      playbackMode: FramePlaybackMode.sequence,
      carouselIntervalSeconds: carouselHours > 0
          ? carouselHours * 3600
          : FrameProtocolConfig.defaultCarouselIntervalSeconds,
      carouselEnabled: false,
      isUpdate: isUpdate,
      newVersionNo: newVersionNo,
      downloadPath: downloadPath,
      // 后端不下发固件包大小，下载后按实际字节数确认。
      firmwareSize: 0,
    );
  }

  /// 由后端下发的屏幕像素宽高推断屏型（对齐小程序 SCREEN_TYPES：3.7寸 480×720 / 5.89寸 680×960）。
  /// 用于「跨型号串台」防护：设备记录带上真实屏型，连接复用 / 扫描匹配才能按型号一票否决。
  /// 无法识别（后端没下发宽高或未知尺寸）时回落 5.89 寸，与旧默认一致、不制造回归。
  static FrameScreenType _screenTypeFromSize(dynamic w, dynamic h) {
    final width = _asInt(w);
    final height = _asInt(h);
    final lo = width < height ? width : height;
    final hi = width < height ? height : width;
    if (lo == 480 && hi == 720) return FrameScreenType.inch37;
    if (lo == 680 && hi == 960) return FrameScreenType.inch589;
    return FrameScreenType.inch589;
  }

  /// 宽松整数解析：兼容 int / num / 数字字符串，非法回落 0。
  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  /// 占位色板：后端不下发色块时按序号取色，保证列表视觉稳定。
  static const List<Color> _palette = <Color>[
    Color(0xFF7F5539),
    Color(0xFF588157),
    Color(0xFF355070),
    Color(0xFF6D597A),
    Color(0xFFCB997E),
    Color(0xFF3D5A80),
  ];

  Color _paletteColor(int seed) => _palette[seed % _palette.length];

  /// 解析后端时间字段（ISO 字符串或时间戳），**解析不出来时返回 null**。
  ///
  /// 曾经还有一个回退成 `DateTime.now()` 的 `_parseDate`，已删除：那种回退值
  /// 绝不能拿来当排序键——每次刷新都是新值，正是列表位置乱跳的根因。
  /// 需要非空时由调用方自己 `?? DateTime.now()`，让「这里用了一个假时间」显式可见。
  DateTime? _tryParseDate(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    // 0 / 负数不是「1970 年」，是「后端没填」——当成无时间，否则它会排到
    // 无时间回退基准（2000 年）之后，比真正没有时间的记录还靠后。
    if (value is int && value > 0) {
      // 13 位按毫秒、10 位按秒处理。
      final millis = value > 1000000000000 ? value : value * 1000;
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    return null;
  }

  /// 依次尝试多个时间字段，返回第一个**能解析出来**的。
  /// 不能用 `a ?? b`：`upTime` 存在但格式不合（后端偶尔给 `2026/07/19 12:00`
  /// 这种 `DateTime.parse` 不认的写法）时，`??` 早就选中了它，`joinTime` 再也轮不上。
  DateTime? _firstParsableDate(List<dynamic> values) {
    for (final value in values) {
      final parsed = _tryParseDate(value);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  /// 常见问题列表：`/Client/Product/getProductFaqList`，映射为 [FaqArticle]。
  ///
  /// 几条定死的规则：
  /// - **全量读取**：按 `pageCount` / `recordCount` 一直翻到取完，不是只取第一页。
  ///   后端 `pageSize` 可能被忽略或封顶（默认才 10），只发一页会漏条目。
  /// - **不按设备过滤**：Client 侧 swagger 里 `getProductFaqList` 根本没有
  ///   productId 参数，这里也不加任何设备/产品条件，取的就是全局常见问题。
  /// - **不做客户端排序**：权重 `grade` 只存在于后台 `ProductFaqApiOut`，
  ///   Client 侧 DTO 拿不到，所以顺序完全以后端返回为准，原样保留。
  /// - 结果按语种缓存（见 [faqNeedsRefresh]）。**成功即以后端为准**——哪怕返回空，
  ///   也要清掉旧语种的残留，否则切到日文后会继续显示上一次的中文列表；
  ///   只有请求抛错才保留现有/内置文案。
  Future<ActionFeedback> refreshFaq() async {
    // 单页条数取 50：后端 pageSize 上限未知，取太大有被截断的风险，
    // 翻页逻辑本身能兜住，宁可多翻一次。
    const pageSize = 50;
    // 安全上限：后端分页字段异常时不至于把请求打成死循环。
    const maxPages = 20;
    // 语种在请求开始时就固定下来：翻页要花好几个 RTT，期间用户可能又切了语种，
    // 拿结束时的 _language 打标会把旧语种的内容标成新语种（页面就不会再补拉了）。
    final requestedLanguage = _language;
    try {
      final collected = <FaqArticle>[];
      final seenIds = <String>{};
      var pageIndex = 1;
      var truncated = false;
      while (true) {
        final data = await BoltFoxApi.getProductFaqList({
          'pageIndex': pageIndex,
          'pageSize': pageSize,
        });
        final rows = extractApiRows(data);
        for (final row in rows) {
          final article = _faqFromJson(row);
          // 翻页之间后端顺序可能有变动，按 id 去重，避免同一条重复出现。
          if (seenIds.add(article.id)) {
            collected.add(article);
          }
        }

        // 空页 = 没有更多了。
        if (rows.isEmpty) {
          break;
        }

        // 停止条件**优先用后端的分页元数据**，不能拿「返回条数 < 请求的 pageSize」
        // 当依据：后端可能无视 pageSize、按自己的默认值（swagger 写的是 10）分页，
        // 那样第一页就 10 < 50 直接停了，只能拿到 10 条——正是「只显示几条」的成因。
        final pageCount = data is Map ? _asInt(data['pageCount']) : 0;
        final recordCount = data is Map ? _asInt(data['recordCount']) : 0;
        if (recordCount > 0 && collected.length >= recordCount) {
          break;
        }
        if (pageCount > 0 && pageIndex >= pageCount) {
          break;
        }
        // 两个元数据都没有时，才退回按「不满一页即最后一页」判断。
        if (pageCount == 0 && recordCount == 0 && rows.length < pageSize) {
          break;
        }
        pageIndex++;
        if (pageIndex > maxPages) {
          truncated = true;
          break;
        }
      }
      if (truncated) {
        debugPrint(
          'refreshFaq: 已达 $maxPages 页上限仍未取完，共 ${collected.length} 条，'
          '请检查后端分页字段（pageCount/recordCount）。',
        );
      }

      _faqArticles
        ..clear()
        ..addAll(collected);
      _faqLanguage = requestedLanguage;
      notifyListeners();
      return ActionFeedback(
        success: true,
        message: tr(
          zh: '帮助文档已更新。',
          en: 'Help docs refreshed.',
          ja: 'ヘルプを更新しました。',
        ),
      );
    } catch (error) {
      return _apiFailure(error);
    }
  }

  /// 常见问题详情：`/Client/Product/getProductFaqDetail`，懒加载并回填 [FaqArticle.answer]。
  Future<void> loadFaqDetail(String id) async {
    if (!_faqArticles.any((faq) => faq.id == id)) {
      return;
    }
    try {
      final data = await BoltFoxApi.getProductFaqDetail(id);
      String? answer;
      if (data is Map) {
        // swagger `ClientProductFaqDetailApiOut`：faqContent。
        answer = data['faqContent']?.toString();
      } else if (data is String) {
        answer = data;
      }
      if (answer != null && answer.isNotEmpty) {
        // await 期间 refreshFaq 可能已重建/重排列表：按 id 重查，
        // 不能沿用 await 前的下标（会越界或把答案写进别的条目）。
        final index = _faqArticles.indexWhere((faq) => faq.id == id);
        if (index >= 0) {
          _faqArticles[index].answer = answer;
          notifyListeners();
        }
      }
    } catch (_) {
      // 详情拉取失败时保留列表已有文案。
    }
  }

  /// 字段名以 swagger `ClientProductFaqApiOut` 为准：`faqId` / `faqTitle` / `faqContent`。
  FaqArticle _faqFromJson(Map<String, dynamic> data) {
    return FaqArticle(
      id: (data['faqId'] ?? _nextId('faq')).toString(),
      question: (data['faqTitle'] ?? '').toString(),
      answer: (data['faqContent'] ?? '').toString(),
    );
  }

  /// 后端记录的设备槽位索引(`imgIndex`, String) → 数字；无索引/非法值统一返回 **-1**。
  ///
  /// ⚠️ 0 是合法槽位（相框第一个位置），所以判空只能判 null/空串，绝不能用真假值——
  /// 否则第一个位置上的照片永远删不掉、刷不到（见 docs/图片索引-imgIndex方案.md 问题 E）。
  ///
  /// 这里**不做容量校验**：容量是真机上报的（[DeviceItem.capacity]，常量 maxImages 只是未连接
  /// 时的回退值），拿它当上限会把大容量设备上的合法高位槽位误判成「无索引」。
  /// 删除链路的越界保护在 [PhotoFrameState.resolveDeleteSlots]（IMG_MASK 只有 96 位）与
  /// [splitSlotsByDeviceMask]（只有出现在设备真实掩码里的槽位才会真的下发 0x12）。
  int _parseImgIndex(Object? value) {
    if (value == null) return -1;
    final index = int.tryParse(value.toString().trim());
    return (index == null || index < 0) ? -1 : index;
  }

  /// 把后端投屏记录映射为 [CastRecord]。
  ///
  /// 字段名以后端 swagger `UserProductImgRecordApiOut` 为准：
  /// `upirId` / `img`(投屏图片) / `imgBle`(设备帧 .bin) / `productName`(设备名) /
  /// `userProductId` / `deviceUploadState`(0=失败,1=成功) /
  /// `deviceUploadStateMsg`(状态中文文案) / `upTime`(最近修改时间) / `joinTime`(添加时间)。
  ///
  /// 原实现读的 `createTime` / `remark` / `failReason` 等键后端根本不存在：
  /// 时间永远回落 `DateTime.now()`（每条记录都显示「刚刚」），message 永远是空串。
  CastRecord _castRecordFromJson(Map<String, dynamic> data, int index) {
    final id = (data['upirId'] ?? _nextId('record')).toString();
    final deviceId = (data['userProductId'] ?? '').toString();
    final deviceName = (data['productName'] ?? '').toString();
    final url = (data['img'] ?? '').toString();
    // 缩略图优先取后端新字段 imgThumb，旧数据回退 img（对齐小程序 normalizeProjectionRecord 的 imgThumb）。
    final thumb = (data['imgThumb'] ?? data['img'] ?? '').toString();
    // 设备帧文件地址：再次投屏直传设备用（不走后端转码）。
    final imgBle = (data['imgBle'] ?? '').toString();
    final status = _castStatusFromJson(data);
    // 设备槽位（后端 String，可能缺失）：-1 表无索引，CastRecord 用 null 表达。
    final slot = _parseImgIndex(data['imgIndex']);
    return CastRecord(
      id: id,
      title: deviceName.isNotEmpty ? deviceName : '投屏记录',
      deviceId: deviceId,
      deviceName: deviceName,
      ownerUserId: _currentUser.id,
      status: status,
      source: ImageSourceType.album,
      color: _paletteColor(index),
      width: 0,
      height: 0,
      // 后端已把状态转成中文（deviceUploadStateMsg），直接用；缺省时按状态兜底。
      message: (data['deviceUploadStateMsg'] ?? '').toString().isNotEmpty
          ? data['deviceUploadStateMsg'].toString()
          : (status == CastStatus.success ? '投屏成功' : '投屏失败'),
      // upTime=最近修改时间，joinTime=添加时间（小程序 normalizeProjectionRecord 同序）。
      // 逐个字段试解析，不用 `a ?? b`：upTime 存在但格式不合时 `??` 已经选中了它，
      // joinTime 再也轮不上，结果整列记录都回退成「现在」（见 _firstParsableDate）。
      createdAt:
          _firstParsableDate([data['upTime'], data['joinTime']]) ??
          DateTime.now(),
      // 这条记录当次投屏占用的设备槽位。记录页本身不读它——再次/重新投屏都是重新找空位；
      // 保留透传是为了排查时能和设备实际位置对上（对齐小程序 normalizeProjectionRecord）。
      imageIndex: slot < 0 ? null : slot,
      imageUrl: url.isEmpty ? null : url,
      thumbUrl: thumb.isEmpty ? null : thumb,
      imgBle: imgBle.isEmpty ? null : imgBle,
    );
  }

  /// 由 `deviceUploadState` 判定投屏成功/失败（swagger: 0=失败, 1=成功）。
  ///
  /// 这是后端唯一的状态字段——原实现把 `uploadState`/`state`/`status`/`isSuccess`
  /// 排在它前面，那几个键后端都不下发；且字段缺失时默认「成功」，会把失败记录显示成成功。
  /// 现在缺失一律按失败处理（记录本就是「上传到设备」的结果，没有成功证据就不算成功）。
  CastStatus _castStatusFromJson(Map<String, dynamic> data) {
    return _asInt(data['deviceUploadState']) == 1
        ? CastStatus.success
        : CastStatus.failed;
  }

  /// 把接口异常映射为页面可展示的 [ActionFeedback]，优先透传后端 `retMsg`。
  ActionFeedback _apiFailure(Object error) {
    if (error is ApiException) {
      // 登录失效（后端 401/406）：ApiClient 已经清掉了 token，但本地 _isLoggedIn 还是 true，
      // 用户会继续留在业务页面，每个接口都报错。这里同步清掉登录态，
      // 根节点的强制登录门控会把人送回登录页（见 bolt_star_app.dart）。
      if (error.isAuthError) {
        _handleSessionExpired();
      }
      return ActionFeedback(success: false, message: error.message);
    }
    return ActionFeedback(
      success: false,
      message: tr(
        zh: '网络连接失败，请稍后重试。',
        en: 'Network error, please try again.',
        ja: 'ネットワークエラーです。後でお試しください。',
      ),
    );
  }

  /// 登录态失效：清空本地登录态与上个账号的数据，并复位首屏加载态。
  /// 幂等——多个并发接口同时收到 401 时只会真正处理一次。
  void _handleSessionExpired() {
    if (!_isLoggedIn) {
      return;
    }
    unawaited(BleController.instance.disconnect());
    // 登录态失效与主动退出同等处理；先捕获当前用户 ID，再异步清掉其协议缓存。
    unawaited(AiServiceConsent.clear(_currentUser.id));
    AiLastSession.clear();
    ApiSession.instance.clear();
    _sessionEpoch++; // 作废本会话在途请求的响应（见 _sessionEpoch 注释）
    // 与 logout 同等对待：会话已失效，上个账号的照片不该留在本机（见 ImageCacheCleanup）。
    ImageCacheCleanup.clearAll();
    unawaited(DeviceIdentityRegistry.instance.clear());
    unawaited(RecentlyBoundDevice.instance.clear());
    _batteryCache.clear();
    _devices.clear();
    _castRecords.clear();
    _selectedDeviceId = '';
    _devicesLoaded = false;
    _castRecordsLoaded = false;
    _devicesLoadError = false;
    _castRecordsLoadError = false;
    _userLoaded = false;
    // 「我的相册」张数跟随账号：不清会让下一个登录的账号先看到上一个人的数字
    _mineCastSuccessCount = 0;
    _mineCastSuccessLoaded = false;
    _isLoggedIn = false;
    notifyListeners();
  }

  String _nextId(String prefix) {
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
  }

  bool _isValidEmail(String email) {
    final trimmed = email.trim();
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(trimmed);
  }
}
