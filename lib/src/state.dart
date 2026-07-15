import 'package:flutter/material.dart';

import 'device/ble_controller.dart';
import 'device/ble/frame_protocol.dart';
import 'device/frame_device_protocol.dart';
import 'network/api_exception.dart';
import 'network/api_rows.dart';
import 'network/api_session.dart';
import 'network/boltfox_api.dart';
import 'package:package_info_plus/package_info_plus.dart';

enum AppLanguage { zh, en, ja }

enum PermissionKind { location, bluetooth, album, camera }

enum DeviceRole { owner, user }

enum ImageSourceType { camera, album }

enum CastStatus { success, failed }

class ActionFeedback {
  const ActionFeedback({required this.success, required this.message});

  final bool success;
  final String message;
}

class CastAttemptResult extends ActionFeedback {
  const CastAttemptResult({
    required super.success,
    required super.message,
    this.deviceFull = false,
  });

  final bool deviceFull;
}

/// App 版本检查结果（见 [PhotoFrameState.checkAppVersion]）。
class AppVersionInfo {
  const AppVersionInfo({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
    required this.description,
  });

  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final String downloadUrl;
  final String description;
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
    this.isUpdate = 0,
    this.newVersionNo = '',
    this.downloadPath = '',
    this.firmwareSize = 0,
  });

  final String id;
  String name;
  String kind;
  FrameScreenType screenType;
  int batteryLevel;
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
  bool get hasFirmwareUpdate =>
      isUpdate == 1 &&
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

class DraftPhoto {
  const DraftPhoto({
    required this.id,
    required this.title,
    required this.source,
    required this.width,
    required this.height,
    required this.color,
    required this.note,
  });

  final String id;
  final String title;
  final ImageSourceType source;
  final double width;
  final double height;
  final Color color;
  final String note;
}

class AlbumPhoto {
  AlbumPhoto({
    required this.id,
    required this.title,
    required this.source,
    required this.deviceId,
    required this.ownerUserId,
    required this.imageIndex,
    required this.imageMaskBit,
    required this.width,
    required this.height,
    required this.targetWidth,
    required this.targetHeight,
    required this.transferBytes,
    required this.crc32,
    required this.color,
    required this.note,
    required this.uploadedAt,
    this.isOnDevice = true,
    this.imageUrl,
    this.deviceName = '',
    this.imgBle,
  });

  final String id;
  final String title;
  final ImageSourceType source;
  final String deviceId;
  final String ownerUserId;
  final int imageIndex;
  final int imageMaskBit;
  final double width;
  final double height;
  final int targetWidth;
  final int targetHeight;
  final int transferBytes;
  final int crc32;
  final Color color;
  final String note;
  final DateTime uploadedAt;
  bool isOnDevice;

  /// 后端图片地址（来自 `getUserProductImgList.img`）；为空时回退占位色块。
  final String? imageUrl;

  /// 所属设备名（`getUserProductImgList.productName`）。后端逐行下发，
  /// 不必反查设备列表——设备列表还没加载时也能正确显示。
  final String deviceName;

  /// 设备帧文件地址（`getUserProductImgList.imgBle`，.bin）；再次投屏可直传设备。
  final String? imgBle;
}

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
    this.photoId,
    this.imageUrl,
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
  final String? photoId;

  /// 后端投屏图片地址（来自 `getUserProductImgRecordList`）；为空时回退占位色块。
  final String? imageUrl;

  /// 后端转换好的设备帧文件地址(.bin，来自 `getUserProductImgRecordList` 的 imgBle)。
  /// 再次/重新投屏时直接下载它走 BLE 图传，不再走后端上传/转码；为空则该记录无法直接再次投屏。
  final String? imgBle;

  /// 投屏目标设备名（`getUserProductImgRecordList.productName`）。后端逐行下发，
  /// 记录页直接用它（对齐小程序 records.wxml 的 `item.deviceName`），
  /// 不再按 deviceId 反查设备列表——设备列表未加载时会退化成显示原始 id。
  final String deviceName;
}

class GuideArticle {
  const GuideArticle({
    required this.category,
    required this.titleZh,
    required this.titleEn,
    required this.titleJa,
    required this.summaryZh,
    required this.summaryEn,
    required this.summaryJa,
  });

  final String category;
  final String titleZh;
  final String titleEn;
  final String titleJa;
  final List<String> summaryZh;
  final List<String> summaryEn;
  final List<String> summaryJa;
}

/// 常见问题（操作指南）条目。[answer] 可懒加载（列表只给标题、展开时再取详情）。
class FaqArticle {
  FaqArticle({required this.id, required this.question, this.answer = ''});

  final String id;
  final String question;
  String answer;
}

/// 应用级演示状态容器。
///
/// 页面只通过这个对象读取和触发业务动作；设备、相册、投屏记录、权限和登录态都在这里统一维护。
/// 后续接入真实接口时，建议优先替换这些 action 方法内部实现，而不是让页面直接操作数据列表。
class PhotoFrameState extends ChangeNotifier {
  PhotoFrameState.seeded()
    : _language = AppLanguage.zh,
      _cameraCounter = 0,
      _isLoggedIn = false,
      _isOffline = false,
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
      _draftLibrary = const [],
      _albumPhotos = [],
      _castRecords = [];

  AppLanguage _language;
  int _cameraCounter;
  bool _isLoggedIn;
  bool _isOffline;
  UserProfile _currentUser;
  final Map<PermissionKind, bool> _permissions;
  final List<DeviceItem> _devices;
  final List<DraftPhoto> _draftLibrary;
  final List<AlbumPhoto> _albumPhotos;
  final List<CastRecord> _castRecords;
  final List<FaqArticle> _faqArticles = _seedFaqArticles();
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
  bool _albumLoaded = false;
  bool _castRecordsLoaded = false;
  bool _userLoaded = false;

  /// 设备列表首屏是否已出结果（false=仍在首次加载，页面应显示 loading 而非「未绑定」空态）。
  bool get devicesLoaded => _devicesLoaded;

  /// 相册/图库首屏是否已出结果。
  bool get albumLoaded => _albumLoaded;

  /// 投屏记录首屏是否已出结果。
  bool get castRecordsLoaded => _castRecordsLoaded;

  /// 用户资料首屏是否已出结果（「我的」页据此决定显示真实统计还是占位 `--`）。
  bool get userLoaded => _userLoaded;

  AppLanguage get language => _language;

  bool get isLoggedIn => _isLoggedIn;

  /// 是否处于离线模式。接入真实网络监测后，在网络异常时调用 [setOffline]。
  bool get isOffline => _isOffline;

  UserProfile get currentUser => _currentUser;

  List<DeviceItem> get devices => List.unmodifiable(_devices);

  List<DraftPhoto> get draftLibrary => List.unmodifiable(_draftLibrary);

  List<AlbumPhoto> get myAlbum {
    // 不再按 ownerUserId 过滤：后端 getUserProductImgList 已按 userToken 只返回本人图片，
    // 再过滤一次纯属自伤——照片映射时写入的 ownerUserId 取自当时的 _currentUser.id，
    // 若 refreshAlbum 与 refreshCurrentUser 并发（「我的」页就是这么调的），用户 id 由 '' 变成真实值后
    // 全部照片都会被这个条件筛掉，图库直接空白。小程序也不做这层过滤，直接渲染后端返回的数据。
    final items = _albumPhotos.where((photo) => photo.isOnDevice).toList();
    items.sort((left, right) => right.uploadedAt.compareTo(left.uploadedAt));
    return items;
  }

  List<CastRecord> get castRecords => List.unmodifiable(_castRecords);

  List<FaqArticle> get faqArticles => List.unmodifiable(_faqArticles);

  Map<PermissionKind, bool> get permissions => Map.unmodifiable(_permissions);

  DeviceItem get selectedDevice => _findDevice(_selectedDeviceId);

  /// 当前选中设备的 id（可能为空串 / 不在列表中；[selectedDevice] 找不到会抛异常，
  /// 只想知道「选了哪台」时用这个，不要用 `selectedDevice.id`）。
  String get selectedDeviceId => _selectedDeviceId;

  String tr({required String zh, String? en, String? ja}) {
    switch (_language) {
      case AppLanguage.zh:
        return zh;
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
    if (_language == AppLanguage.ja) {
      return '${value.year}/$month/$day $hour:$minute';
    }
    return '${value.year}-$month-$day $hour:$minute';
  }

  int deviceUsage(String deviceId) {
    return _findDevice(deviceId).imageCount;
  }

  int? nextImageIndex(String deviceId) {
    return FrameDeviceProtocol.firstFreeIndex(_findDevice(deviceId).imageMask);
  }

  String deviceMaskLabel(String deviceId) => _findDevice(deviceId).maskLabel;

  String formatBytes(int value) {
    if (value >= 1024 * 1024) {
      return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (value >= 1024) {
      return '${(value / 1024).toStringAsFixed(1)} KB';
    }
    return '$value B';
  }

  String formatCommand(int? command) {
    if (command == null) {
      return '-';
    }
    return '0x${command.toRadixString(16).padLeft(2, '0').toUpperCase()}';
  }

  int get totalPhotoCount => myAlbum.length;

  /// 「我的」页的照片数 / 设备数：优先后端统计（getUserInfo 的 `imgCount` / `productCount`），
  /// 未下发（0）时回退本地列表长度——对齐小程序 mine.js
  /// `photoCount: Number(userInfo.imgCount) || photos.length`。
  int get minePhotoCount =>
      _currentUser.imgCount > 0 ? _currentUser.imgCount : myAlbum.length;

  int get mineDeviceCount => _currentUser.productCount > 0
      ? _currentUser.productCount
      : _devices.length;

  int get successCount {
    return _castRecords
        .where((record) => record.status == CastStatus.success)
        .length;
  }

  int get failureCount {
    return _castRecords
        .where((record) => record.status == CastStatus.failed)
        .length;
  }

  int get activePermissionCount {
    return _permissions.values.where((enabled) => enabled).length;
  }

  int get totalPermissionCount => PermissionKind.values.length;

  double get successRate {
    if (_castRecords.isEmpty) {
      return 0;
    }
    return successCount / _castRecords.length;
  }

  DeviceItem deviceById(String deviceId) => _findDevice(deviceId);

  String deviceName(String deviceId) {
    // 容错：后端相册/投屏记录的 deviceId 可能未在当前设备列表中，避免反查抛异常。
    final matches = _devices.where((device) => device.id == deviceId);
    return matches.isEmpty ? deviceId : matches.first.name;
  }

  DraftPhoto createCameraDraft() {
    final palette = <Color>[
      const Color(0xFFBC6C25),
      const Color(0xFF588157),
      const Color(0xFF3D5A80),
      const Color(0xFF9C6644),
      const Color(0xFF6D597A),
    ];
    final titles = <String>['门口剪影', '雨后露台', '下午茶桌', '沙发角落', '阳台花影'];
    final index = _cameraCounter % palette.length;
    _cameraCounter += 1;
    return DraftPhoto(
      id: _nextId('draft-camera'),
      title: titles[index],
      source: ImageSourceType.camera,
      width: index.isEven ? 3024 : 2160,
      height: index.isEven ? 4032 : 2160,
      color: palette[index],
      note: tr(
        zh: '已完成自动裁剪与锐化预处理',
        en: 'Auto cropped and sharpened before casting',
        ja: '自動トリミングとシャープ処理済み',
      ),
    );
  }

  DraftPhoto createAlbumDraft({
    required String title,
    required double width,
    required double height,
    required String uri,
  }) {
    final palette = <Color>[
      const Color(0xFF3D5A80),
      const Color(0xFF6B705C),
      const Color(0xFFD97757),
      const Color(0xFF7F5539),
      const Color(0xFF5E548E),
    ];
    final index = DateTime.now().millisecondsSinceEpoch % palette.length;
    return DraftPhoto(
      id: _nextId('draft-album'),
      title: title.trim().isEmpty ? '相册图片' : title.trim(),
      source: ImageSourceType.album,
      width: width,
      height: height,
      color: palette[index],
      note: tr(
        zh: '来自系统相册，已获得本次读取授权',
        en: 'Selected from system album with read access granted.',
        ja: 'システムアルバムから選択され、読み取り権限を取得済みです。',
      ),
    );
  }

  DraftPhoto draftFromAlbumPhoto(AlbumPhoto photo) {
    return DraftPhoto(
      id: _nextId('draft-recast'),
      title: photo.title,
      source: photo.source,
      width: photo.width,
      height: photo.height,
      color: photo.color,
      note: photo.note,
    );
  }

  void setPermission(PermissionKind kind, bool enabled) {
    _permissions[kind] = enabled;
    notifyListeners();
  }

  void setOffline(bool value) {
    if (_isOffline == value) {
      return;
    }
    _isOffline = value;
    notifyListeners();
  }

  /// 连接设备（真实 BLE，移植小程序「按需手动连接」模型）：先设为当前选中设备，
  /// 再经 [BleController.connectBoundDevice] 复用活动会话或扫描匹配连接。
  /// 连接已绑定设备只按硬件序列号容错匹配（广播 4 字节 vs 后端 6 字节互为子串
  /// 也算同一台），与设备名无关——改名不影响连接、也不影响「已连接」显示。
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
        message: tr(zh: '设备不存在。', en: 'Device not found.', ja: '端末が見つかりません。'),
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
    if (error != null) {
      device.connected = false;
      notifyListeners();
      return ActionFeedback(success: false, message: error);
    }
    for (final item in _devices) {
      item.connected = identical(item, device);
    }
    // 连接后把真机 0x01(readDeviceInfo) 的全部字段回填到本地设备，对齐小程序
    // detail.js/list.js 的 applyConnectedDevice（电量/内存/播放模式/间隔/固件/当前张）。
    // 之前只同步电量，导致详情页内存恒显 0、播放模式/固件为默认、且 setPlayback 用错间隔。
    _applyConnectedInfo(device, ble.info);
    notifyListeners();
    return ActionFeedback(
      success: true,
      message: tr(zh: '已连接设备。', en: 'Device connected.', ja: '端末に接続しました。'),
    );
  }

  /// 断开设备的 BLE 连接（对齐小程序设备列表「断开」按钮）。
  Future<ActionFeedback> disconnectDevice(String deviceId) async {
    final ble = BleController.instance;
    for (final device in _devices) {
      if (device.id != deviceId) {
        continue;
      }
      // 单连接模型：这台设备确实占着活动会话（序列号交叉匹配）或页面显示已连接时才真正断开。
      if (device.connected ||
          ble.sessionMatchesSerial(
            device.serialNumber,
            screenCode: device.screenType.code,
          )) {
        await ble.disconnect();
      }
      device.connected = false;
      notifyListeners();
      return ActionFeedback(
        success: true,
        message: tr(zh: '已断开。', en: 'Disconnected.', ja: '切断しました。'),
      );
    }
    return ActionFeedback(
      success: false,
      message: tr(zh: '设备不存在。', en: 'Device not found.', ja: '端末が見つかりません。'),
    );
  }

  /// 这台设备是否正占着当前 BLE 活动会话（序列号容错交叉匹配）。
  bool _sessionMatches(DeviceItem device) =>
      BleController.instance.sessionMatchesSerial(
        device.serialNumber,
        screenCode: device.screenType.code,
      );

  /// 用真实 BLE 会话对账各设备的「已连接」显示（回前台连接体检后调用，
  /// 对齐小程序 app.onShow → reconcileConnections 落到 UI 的那一步）。
  void reconcileConnectionFlags() {
    var changed = false;
    for (final device in _devices) {
      final live = _sessionMatches(device);
      if (device.connected != live) {
        device.connected = live;
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
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

  /// 按设备 id 回读真机内存/索引。投屏完成页调用时不改变当前选中的设备。
  Future<void> refreshConnectedDeviceInfo(String deviceId) async {
    DeviceItem? device;
    for (final item in _devices) {
      if (item.id == deviceId) {
        device = item;
        break;
      }
    }
    if (device == null) {
      return;
    }
    // 只有当前 BLE 会话就是这台设备时才读；否则保持未连接的 -- 显示，不误连别台。
    if (!_sessionMatches(device)) {
      return;
    }
    try {
      final info = await BleController.instance.client.readDeviceInfo();
      _applyConnectedInfo(device, info);
      device.connected = true;
      notifyListeners();
    } catch (_) {
      // 读失败静默（与小程序 loadDetail 的 catch 一致），保持旧值。
    }
  }

  /// 把真机 0x01 读到的 [FrameDeviceInfo] 合并进本地 [device]（对齐小程序 applyConnectedDevice）。
  /// 调用方负责 notifyListeners()。[info] 为空（读取失败）时不改动，页面按 connected=false 显示 --。
  void _applyConnectedInfo(DeviceItem device, FrameDeviceInfo? info) {
    if (info == null) {
      return;
    }
    if (info.battery > 0) {
      device.batteryLevel = info.battery;
    }
    // 真机内存（真机容量最多 95 槽，超出 int 掩码范围，直接采用上报计数/容量）。
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
  /// 调用 `/Client/User/userLogin`，成功后把返回的登录 token 写入
  /// [ApiSession]（后续接口才会带上 `userToken` header），并尽力拉取一次用户信息。
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
      if (token != null && token.isNotEmpty) {
        ApiSession.instance.setToken(token);
      }
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

  /// 微信开放平台「移动应用微信登录」入口。
  ///
  /// [code] 由移动端微信 SDK 返回，只能使用一次；服务端负责用 AppSecret 换取微信身份并返回
  /// BoltStar 的 userToken。客户端绝不保存微信 access_token / refresh_token / AppSecret。
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

    try {
      final data = await BoltFoxApi.weChatMobileLogin(code: authorizationCode);
      final token = _readToken(data);
      if (token == null || token.isEmpty) {
        return ActionFeedback(
          success: false,
          message: tr(
            zh: '微信登录响应缺少登录凭证，请稍后重试。',
            en: 'The WeChat login response did not contain a session token.',
            ja: 'WeChat ログイン応答にセッショントークンがありません。',
          ),
        );
      }

      ApiSession.instance.setToken(token);
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
    String? nickName,
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
      await BoltFoxApi.userRegister(
        email: target,
        password: password,
        emailCode: emailCode.trim(),
        nickName: nickName?.trim().isEmpty ?? true ? null : nickName!.trim(),
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
    if (data is Map) {
      final m = data.map((k, v) => MapEntry(k.toString(), v));
      latest = (m['appVersionNo'] ?? '').toString();
      url = (m['downloadPath'] ?? '').toString();
      desc = (m['upgradeTips'] ?? '').toString();
      hasUpdate = _asInt(m['isUpdate']) == 1;
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

  /// 将一张草稿照片投屏到指定设备。
  ///
  /// 方法内部串联权限校验、容量校验、传输计划模拟、相册写入和记录生成；
  /// 页面层不要拆开复用这些步骤，否则容易造成记录和设备状态不一致。
  CastAttemptResult castDraft({
    required DraftPhoto draft,
    required String deviceId,
  }) {
    if (!_isLoggedIn) {
      return CastAttemptResult(
        success: false,
        message: tr(
          zh: '请先完成邮箱登录。',
          en: 'Sign in with email first.',
          ja: '先にメールでログインしてください。',
        ),
      );
    }
    if (!_permissions[PermissionKind.bluetooth]!) {
      return CastAttemptResult(
        success: false,
        message: tr(
          zh: '蓝牙权限未开启，无法连接设备。',
          en: 'Bluetooth permission is required.',
          ja: 'Bluetooth 権限が必要です。',
        ),
      );
    }
    if (!_permissions[PermissionKind.location]!) {
      return CastAttemptResult(
        success: false,
        message: tr(
          zh: '位置权限未开启，蓝牙搜索不可用。',
          en: 'Location permission is required for device discovery.',
          ja: 'デバイス探索には位置情報権限が必要です。',
        ),
      );
    }
    if (draft.source == ImageSourceType.camera &&
        !_permissions[PermissionKind.camera]!) {
      return CastAttemptResult(
        success: false,
        message: tr(
          zh: '相机权限未开启，请先授权后再拍照投屏。',
          en: 'Camera permission is required for camera casting.',
          ja: '撮影投映にはカメラ権限が必要です。',
        ),
      );
    }
    final device = _findDevice(deviceId);
    final snapshot = device.toSnapshot();
    final imageIndex = FrameDeviceProtocol.firstFreeIndex(snapshot.imageMask);
    if (imageIndex == null) {
      final message = tr(
        zh: '设备内存已满，请清理相框照片或联系设备所有者。',
        en: 'Device storage is full. Clear photos or contact the owner.',
        ja: '端末の容量がいっぱいです。写真整理かオーナーへの連絡が必要です。',
      );
      _castRecords.insert(
        0,
        CastRecord(
          id: _nextId('record'),
          title: draft.title,
          deviceId: deviceId,
          ownerUserId: _currentUser.id,
          status: CastStatus.failed,
          source: draft.source,
          color: draft.color,
          width: draft.width,
          height: draft.height,
          message: message,
          createdAt: DateTime.now(),
          command: FrameCommand.startTransfer,
          resultCode: FrameProtocolResultCode.storageFull,
          imageMask: snapshot.imageMask,
        ),
      );
      notifyListeners();
      return CastAttemptResult(
        success: false,
        message: message,
        deviceFull: true,
      );
    }
    final plan = FrameDeviceProtocol.buildTransferPlan(
      imageIndex: imageIndex,
      sourceWidth: draft.width,
      sourceHeight: draft.height,
      screenType: snapshot.screenType,
    );
    final transfer = FrameDeviceProtocol.simulateImageTransfer(
      imageMask: snapshot.imageMask,
      screenType: snapshot.screenType,
      plan: plan,
    );
    if (!transfer.success) {
      final message = tr(
        zh: '投屏失败：${transfer.resultCode.labelZh}。',
        en: 'Casting failed: ${transfer.resultCode.labelZh}.',
        ja: '投映に失敗しました: ${transfer.resultCode.labelZh}。',
      );
      _castRecords.insert(
        0,
        CastRecord(
          id: _nextId('record'),
          title: draft.title,
          deviceId: deviceId,
          ownerUserId: _currentUser.id,
          status: CastStatus.failed,
          source: draft.source,
          color: draft.color,
          width: draft.width,
          height: draft.height,
          message: message,
          createdAt: DateTime.now(),
          imageIndex: imageIndex,
          command: FrameCommand.finishTransfer,
          resultCode: transfer.resultCode,
          imageMask: transfer.imageMask,
        ),
      );
      notifyListeners();
      return CastAttemptResult(
        success: false,
        message: message,
        deviceFull: transfer.resultCode == FrameProtocolResultCode.storageFull,
      );
    }
    device.imageMask = transfer.imageMask;
    device.currentImageIndex = transfer.currentImageIndex;
    device.batteryLevel = (device.batteryLevel - 1).clamp(0, 100);
    final photo = AlbumPhoto(
      id: _nextId('photo'),
      title: draft.title,
      source: draft.source,
      deviceId: deviceId,
      ownerUserId: _currentUser.id,
      imageIndex: imageIndex,
      imageMaskBit: FrameDeviceProtocol.bitForIndex(imageIndex),
      width: draft.width,
      height: draft.height,
      targetWidth: plan.targetWidth,
      targetHeight: plan.targetHeight,
      transferBytes: plan.dataSize,
      crc32: plan.crc32,
      color: draft.color,
      note:
          '${draft.note}；写入槽位 $imageIndex，${plan.targetWidth}×${plan.targetHeight}，${plan.packetCount} 个 BLE 分包。',
      uploadedAt: DateTime.now(),
    );
    _albumPhotos.insert(0, photo);
    _castRecords.insert(
      0,
      CastRecord(
        id: _nextId('record'),
        title: draft.title,
        deviceId: deviceId,
        ownerUserId: _currentUser.id,
        status: CastStatus.success,
        source: draft.source,
        color: draft.color,
        width: draft.width,
        height: draft.height,
        message: tr(
          zh: '投屏成功，写入 ${device.name} 槽位 $imageIndex，IMG_MASK=${device.maskLabel}。',
          en: 'Casting succeeded on ${device.name}, slot $imageIndex, IMG_MASK=${device.maskLabel}.',
          ja: '${device.name} のスロット $imageIndex に投映しました。IMG_MASK=${device.maskLabel}。',
        ),
        createdAt: DateTime.now(),
        imageIndex: imageIndex,
        command: FrameCommand.finishTransfer,
        resultCode: transfer.resultCode,
        imageMask: transfer.imageMask,
        photoId: photo.id,
      ),
    );
    notifyListeners();
    return CastAttemptResult(
      success: true,
      message: tr(
        zh: '投屏成功，已同步到我的相册。',
        en: 'Casting succeeded and synced to My Album.',
        ja: '投映に成功し、マイアルバムに同期しました。',
      ),
    );
  }

  /// 我的相册 / 图库列表：`/Client/UserProduct/getUserProductImgList`。
  ///
  /// 映射为 [AlbumPhoto]，仅在后端返回非空时替换本地列表（失败保留当前数据）。
  /// 同时把设备一并刷新，保证 [deviceName] 能解析到后端设备名。
  Future<ActionFeedback> refreshAlbum({String? userProductId}) async {
    try {
      final data = await BoltFoxApi.getUserProductImgList({
        'pageIndex': 1,
        'pageSize': 100,
        'userProductId': ?userProductId,
      });
      final rows = extractApiRows(data);
      // 后端为准：即使返回空也要覆盖本地（清空后相册应显示空态，不保留旧数据）。
      final mapped = <AlbumPhoto>[];
      for (var i = 0; i < rows.length; i++) {
        mapped.add(_albumPhotoFromJson(rows[i], i));
      }
      _albumPhotos
        ..clear()
        ..addAll(mapped);
      // 数据与首屏加载态同帧提交：先置 loaded 再 notify，页面不会出现「loading 已结束但列表还没写入」的空态中间帧。
      _albumLoaded = true;
      notifyListeners();
      return ActionFeedback(
        success: true,
        message: tr(zh: '相册已更新。', en: 'Album refreshed.', ja: 'アルバムを更新しました。'),
      );
    } catch (error) {
      // 失败也结束首屏 loading，落到空态（对齐小程序 catch 里的 `setData({loading:false})`；
      // 错误提示由调用方按返回的 ActionFeedback 弹，不在这里重复弹）。
      _albumLoaded = true;
      notifyListeners();
      return _apiFailure(error);
    }
  }

  /// 查询设备一键清除状态（对齐小程序 `getUserProductClearImg`）：`true`=已清除、`false`=未清除、
  /// `null`=查询失败（接口层 showError:false 静默，下次进入/切换设备会再查）。
  ///
  /// 设备在别处被执行过清空时（图库照片已不在设备上），图库页据此弹「请重新上传图片」提醒。
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

  /// 删除相册照片（支持多选）：设备优先——已连接时先删设备固件对应槽位(CMD 0x12)，
  /// 若删到「屏幕当前正显示的图片」再刷屏(0x24)切到最近的有图槽位；设备删成功后再删后端记录，
  /// 保证「列表 / 后端 / 设备」三处一致（对齐小程序 album/list.js confirmDeleteSelected +
  /// refreshAfterDeleteIfNeeded）。设备删除失败即中止、不动后端，避免相框还挂着已删图片。
  /// 未连接设备时跳过设备删除，仅删后端 + 本地软隐藏。
  Future<ActionFeedback> deleteAlbumPhotos(Set<String> photoIds) async {
    if (photoIds.isEmpty) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '请先选择要删除的照片。',
          en: 'Select photos to delete first.',
          ja: '削除する写真を選択してください。',
        ),
      );
    }
    final photos = _albumPhotos
        .where(
          // 同 myAlbum：不按 ownerUserId 过滤（后端已按 userToken 隔离），
          // 否则用户 id 到位的时机稍晚就会「选中了照片却提示没有可删除的照片」。
          (photo) => photoIds.contains(photo.id) && photo.isOnDevice,
        )
        .toList();
    if (photos.isEmpty) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '没有可删除的设备照片。',
          en: 'No device photos can be deleted.',
          ja: '削除できる端末写真がありません。',
        ),
      );
    }

    // 1) 设备优先：已连接则先读设备信息(0x01)拿到已占槽位 + 当前屏显图，把选中照片解析成设备槽位，
    //    一条 0x12 批量删除；删到当前屏显图再刷屏(0x24)。设备删除失败即中止、不动后端。
    // 目标设备 = 这些照片所属设备（单设备图库保证同一台）。跨设备批次会按同一掩码删错槽位(0x12)，防御拦截。
    final targetId = photos.first.deviceId;
    if (photos.any((photo) => photo.deviceId != targetId)) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '只能删除同一台设备的照片。',
          en: 'You can only delete photos from a single device.',
          ja: '同じ端末の写真のみ削除できます。',
        ),
      );
    }
    final targetMatches = _devices
        .where((device) => device.id == targetId)
        .toList();
    if (targetMatches.isEmpty) {
      return ActionFeedback(
        success: false,
        message: tr(zh: '设备不存在。', en: 'Device not found.', ja: '端末が見つかりません。'),
      );
    }
    // 未连接到「照片所属设备」则自动扫连（对齐小程序 ensureConnectedForAction），连不上中止、不动后端。
    if (!_sessionMatches(targetMatches.first)) {
      final connectFeedback = await connectDevice(targetId);
      if (!connectFeedback.success) {
        return connectFeedback;
      }
    }
    final client = BleController.instance.client;
    String refreshWarn = '';
    if (client.connected) {
      try {
        final info = await client.readDeviceInfo();
        final occupied = FrameProtocol.maskToIndexes(info.imgMask);
        final slotIndexes = <int>[];
        for (final photo in photos) {
          final slot = _resolveDeviceImageIndex(photo, occupied);
          if (slot >= 0 && !slotIndexes.contains(slot)) {
            slotIndexes.add(slot);
          }
        }
        if (slotIndexes.isNotEmpty) {
          final newMask = await client.deleteImage(slotIndexes);
          // 只在删到「屏幕当前显示的图片」时才刷屏：切到删除后最近的有图槽位；
          // 设备已无图片则不主动刷屏——固件在清空后会自动刷成空屏（无单独清屏指令）。
          if (slotIndexes.contains(info.curImgIndex)) {
            final remaining = FrameProtocol.maskToIndexes(newMask);
            if (remaining.isNotEmpty) {
              try {
                await client.refreshScreen(remaining.first);
              } catch (_) {
                // 刷屏失败不抛出——设备侧已删成功，抛出会中止后端删除造成两边不一致。
                refreshWarn = tr(
                  zh: '已删除，但屏幕刷新失败，请稍后手动刷新屏幕。',
                  en: 'Deleted, but screen refresh failed. Please refresh manually later.',
                  ja: '削除しましたが画面更新に失敗しました。後で手動で更新してください。',
                );
              }
            }
          }
        }
      } catch (e) {
        // 设备忙(0x0B)：设备只是暂时在忙，别归成通用「设备删除失败」，原样提示稍后重试。
        if (FrameProtocol.isBusyMessage(e.toString())) {
          return ActionFeedback(
            success: false,
            message: tr(
              zh: '当前设备繁忙，请稍后重试',
              en: 'Device is busy, please try again later.',
              ja: '端末が処理中です。しばらくしてから再試行してください。',
            ),
          );
        }
        // 设备没删成功就不动后端/本地，避免三处不一致。
        return ActionFeedback(
          success: false,
          message: tr(
            zh: '设备删除失败，请检查设备连接后重试。',
            en: 'Failed to delete from device. Check the connection and retry.',
            ja: '端末からの削除に失敗しました。接続を確認して再試行してください。',
          ),
        );
      }
    }

    // 2) 设备删成功（或未连接跳过）后再删后端记录。
    try {
      await BoltFoxApi.delUserProductImg(
        photos.map((photo) => photo.id as Object).toList(),
      );
    } catch (error) {
      return _apiFailure(error);
    }

    // 3) 本地软隐藏；设备真实掩码以下次 readDeviceInfo/刷新为准，这里不再本地模拟掩码。
    for (final photo in photos) {
      photo.isOnDevice = false;
    }
    notifyListeners();
    // 4) 回后端对账列表/计数（对齐小程序删除后 loadPhotos）；失败则保留上面的本地软隐藏。
    await refreshAlbum();
    return ActionFeedback(
      success: true,
      message: refreshWarn.isNotEmpty
          ? refreshWarn
          : tr(
              zh: '已删除所选照片。',
              en: 'Selected photos deleted.',
              ja: '選択した写真を削除しました。',
            ),
    );
  }

  /// 图库「刷新屏幕」：把选中的这张照片切到相框当前显示（对齐小程序 list.js:474-533 refreshScreen）。
  /// 需已连接设备；读设备信息 → 解析该照片槽位 → 0x24 切图。
  Future<ActionFeedback> refreshGalleryPhotoOnScreen(String photoId) async {
    AlbumPhoto? photo;
    try {
      // 同 myAlbum：不按 ownerUserId 过滤（后端已按 userToken 隔离）。
      photo = _albumPhotos.firstWhere((p) => p.id == photoId && p.isOnDevice);
    } catch (_) {
      photo = null;
    }
    if (photo == null) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '该照片不在设备上，无法刷新到屏幕。',
          en: 'This photo is not on the device.',
          ja: 'この写真は端末にありません。',
        ),
      );
    }
    // 未连接到照片所属设备则自动扫连（对齐小程序 ensureActiveDeviceConnection），连不上中止。
    final targetDeviceId = photo.deviceId; // photo 已判空
    final targetMatches = _devices
        .where((device) => device.id == targetDeviceId)
        .toList();
    if (targetMatches.isEmpty) {
      return ActionFeedback(
        success: false,
        message: tr(zh: '设备不存在。', en: 'Device not found.', ja: '端末が見つかりません。'),
      );
    }
    if (!_sessionMatches(targetMatches.first)) {
      final connectFeedback = await connectDevice(targetDeviceId);
      if (!connectFeedback.success) {
        return connectFeedback;
      }
    }
    final client = BleController.instance.client;
    try {
      final info = await client.readDeviceInfo();
      final occupied = FrameProtocol.maskToIndexes(info.imgMask);
      final slot = _resolveDeviceImageIndex(photo, occupied);
      if (slot < 0) {
        return ActionFeedback(
          success: false,
          message: tr(
            zh: '未能定位该照片在设备上的位置，请刷新图库后重试。',
            en: 'Could not locate this photo on the device.',
            ja: '端末上でこの写真の位置を特定できませんでした。',
          ),
        );
      }
      await client.refreshScreen(slot);
      return ActionFeedback(
        success: true,
        message: tr(
          zh: '已切换到该照片。',
          en: 'Switched to this photo.',
          ja: 'この写真に切り替えました。',
        ),
      );
    } catch (e) {
      if (FrameProtocol.isBusyMessage(e.toString())) {
        return ActionFeedback(
          success: false,
          message: tr(
            zh: '当前设备繁忙，请稍后重试',
            en: 'Device is busy, please try again later.',
            ja: '端末が処理中です。しばらくしてから再試行してください。',
          ),
        );
      }
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '刷新屏幕失败，请检查设备连接后重试。',
          en: 'Failed to refresh the screen. Check the connection and retry.',
          ja: '画面の更新に失敗しました。接続を確認して再試行してください。',
        ),
      );
    }
  }

  /// 选中照片 → 设备固件图片槽位索引（对齐小程序 album/list.js resolveDeviceImageIndex）。
  ///
  /// 固件已占用槽位 [occupied] 按索引升序；上传时用 firstFreeIndex 从最小空闲槽位起填，
  /// 即最早上传的图落在最小槽位。所以本设备在库照片要按「上传先后」升序排（主键 uProductImgId
  /// 越小越早，取不到时退回 uploadedAt），第 N 张才对应升序槽位 occupied[N]——直接按后端列表
  /// 顺序去对会刷错图。读不到掩码时回退到位置本身；照片不在本设备上返回 -1。
  int _resolveDeviceImageIndex(AlbumPhoto photo, List<int> occupied) {
    final devicePhotos =
        _albumPhotos
            .where((item) => item.isOnDevice && item.deviceId == photo.deviceId)
            .toList()
          ..sort((a, b) {
            final ai = int.tryParse(a.id);
            final bi = int.tryParse(b.id);
            if (ai != null && bi != null && ai != bi) {
              return ai.compareTo(bi);
            }
            return a.uploadedAt.compareTo(b.uploadedAt);
          });
    final pos = devicePhotos.indexWhere((item) => item.id == photo.id);
    if (pos < 0) {
      return -1;
    }
    if (occupied.isNotEmpty) {
      return pos < occupied.length ? occupied[pos] : -1;
    }
    return pos;
  }

  CastAttemptResult recastAlbumPhoto(String photoId, String deviceId) {
    final photo = _albumPhotos.firstWhere((item) => item.id == photoId);
    return castDraft(draft: draftFromAlbumPhoto(photo), deviceId: deviceId);
  }

  CastAttemptResult recastRecord(String recordId, String deviceId) {
    final record = _castRecords.firstWhere((item) => item.id == recordId);
    return castDraft(
      draft: DraftPhoto(
        id: _nextId('draft-record'),
        title: record.title,
        source: record.source,
        width: record.width,
        height: record.height,
        color: record.color,
        note: record.message,
      ),
      deviceId: deviceId,
    );
  }

  /// 投屏记录列表：`/Client/UserProduct/getUserProductImgRecordList`。
  ///
  /// 映射为 [CastRecord]，仅在后端返回非空时替换本地列表（失败保留当前数据）。
  /// [deviceUploadState] 传 1=只取成功 / 0=只取失败（对齐小程序 records.js 按 tab 传 filter，
  /// 后端按状态过滤），缺省不传取全部。分状态拉取避免 >100 条时本地切片丢行。
  Future<ActionFeedback> refreshCastRecords({
    String? userProductId,
    int? deviceUploadState,
  }) async {
    try {
      final data = await BoltFoxApi.getUserProductImgRecordList({
        'pageIndex': 1,
        'pageSize': 100,
        'userProductId': ?userProductId,
        'deviceUploadState': ?deviceUploadState,
      });
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
      // 失败也结束首屏 loading，落到空态（同 refreshAlbum）。
      _castRecordsLoaded = true;
      notifyListeners();
      return _apiFailure(error);
    }
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
    // 对齐小程序 utils/device-name.js：按 Unicode 码点计数，最多 6 个字符。
    // 使用 runes，emoji / 生僻字不会被 UTF-16 代理对误算成两个字符。
    if (value.runes.length > 6) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '设备名称最多6个字符',
          en: 'Device name must be at most 6 characters.',
          ja: '端末名は6文字以内です。',
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
  /// 仅当后端返回非空列表时替换本地列表，避免首页 [selectedDevice] 落空；失败保留当前列表。
  Future<ActionFeedback> refreshDevices() async {
    try {
      final data = await BoltFoxApi.getUserProductList({
        'pageIndex': 1,
        'pageSize': 100, // 对齐小程序 getDevices({pageSize:100})
      });
      final rows = extractApiRows(data);
      // 后端为准：即使返回空也覆盖本地（删到 0 台时应显示空态，不保留旧数据）。
      // 同一实体相框被重复绑定时，按硬件序列号折叠成一行（对齐小程序 dedupeDevices）。
      final mapped = _dedupeDevicesBySerial(rows.map(_deviceFromJson).toList());
      // 已连接回填：后端不存连接态/BLE 会话，若一律 connected:false 替换，
      // 正连着的设备会被错显示成「未连接」（改名后刷新列表时尤其明显）。
      // 按序列号与活动会话容错交叉匹配回填（与小程序 loadHomeState/loadDevices 同规则）。
      for (final device in mapped) {
        device.connected = _sessionMatches(device);
      }
      _devices
        ..clear()
        ..addAll(mapped);
      if (_devices.isEmpty) {
        _selectedDeviceId = '';
      } else if (!_devices.any((device) => device.id == _selectedDeviceId)) {
        _selectedDeviceId = _devices.first.id;
      }
      _devicesLoaded = true;
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
      // 失败也结束首屏 loading，落到空态（同 refreshAlbum）。
      _devicesLoaded = true;
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
    final resolved = await _resolveProductId(
      model: model,
      screen: screen,
      scanName: scanName,
    );
    if (resolved.productId == null) {
      return ActionFeedback(success: false, message: resolved.error!);
    }
    try {
      await BoltFoxApi.addUserProduct(
        productId: resolved.productId!,
        productName: productName,
        productSerialNo: productSerialNo,
      );
      await refreshDevices();
      return ActionFeedback(
        success: true,
        message: tr(zh: '设备已绑定。', en: 'Device bound.', ja: '端末をバインドしました。'),
      );
    } catch (error) {
      return _apiFailure(error);
    }
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
          zh: '未匹配到对应产品，请确认该设备在产品列表中存在。',
          en: 'No matching product found. Please confirm the device exists in the product list.',
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
    try {
      DeviceItem? target;
      try {
        target = _findDevice(deviceId);
      } catch (_) {
        target = null;
      }
      if (target != null && (target.connected || _sessionMatches(target))) {
        await BleController.instance.disconnect();
        target.connected = false;
      }
      await BoltFoxApi.delUserProduct(deviceId);
      _devices.removeWhere((device) => device.id == deviceId);
      _albumPhotos.removeWhere((photo) => photo.deviceId == deviceId);
      _castRecords.removeWhere((record) => record.deviceId == deviceId);
      if (_selectedDeviceId == deviceId && _devices.isNotEmpty) {
        _selectedDeviceId = _devices.first.id;
      }
      notifyListeners();
      return ActionFeedback(
        success: true,
        message: tr(zh: '设备已删除。', en: 'Device deleted.', ja: '端末を削除しました。'),
      );
    } catch (error) {
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
          zh: '设备暂时无法连接',
          en: 'The device is temporarily unavailable.',
          ja: '端末に一時的に接続できません。',
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
    final device = _findDevice(deviceId);
    final client = BleController.instance.client;

    // 清空需与固件交互：未连接不自动重连，直接提示先连接（对齐小程序 clearCopies 前置拦截）。
    if (!client.connected) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '请先连接设备',
          en: 'Please connect the device first.',
          ja: '先に端末を接続してください。',
        ),
      );
    }

    // 1) 设备优先：读设备信息(0x01)拿到已占槽位，一条 0x12 删除全部图片。
    //    固件清空后会自动刷成空屏（无单独清屏指令），不主动刷屏。
    //    任一蓝牙链路失败（断联 / 应答超时 / 未连接）或删完仍有残留 → 都视为设备侧未清成功。
    var deviceCleared = false;
    Object? clearError;
    try {
      final info = await client.readDeviceInfo();
      final indexes = FrameProtocol.maskToIndexes(info.imgMask);
      if (indexes.isEmpty) {
        deviceCleared = true;
      } else {
        try {
          // deleteImage 应答等待已按张数放宽（每张 2s、下限 6s、上限 180s，见 device_ble.deleteImage），
          // 一次删几十张也不会一超 6s 就误判超时。返回删除后最新 IMG_MASK：仍有占用=没删干净。
          final newMask = await client.deleteImage(indexes);
          deviceCleared = FrameProtocol.maskToIndexes(newMask).isEmpty;
        } catch (deleteError) {
          // 0x12 应答超时/断连——但不少固件其实已把图删干净了，只是应答异常/迟到
          //（设备逐张擦 flash 全删完才回一次应答，慢一点就顶到超时）。设备忙(0x0B)先短路交给下方 busy 分支。
          clearError = deleteError;
          if (!FrameProtocol.isBusyMessage(deleteError.toString())) {
            // 回读校验（最多 3 次、每次间隔 4s）：设备可能还在擦除、此刻回不了 0x01，给它删完的时间；
            // 任一次读到空掩码就按成功，全部失败/仍有残留才判失败——治「一键清空 60 张误报设备无法连接」。
            FrameDeviceInfo? after;
            for (var attempt = 1; attempt <= 3 && after == null; attempt++) {
              if (attempt > 1) {
                await Future<void>.delayed(const Duration(seconds: 4));
              }
              try {
                after = await client.readDeviceInfo();
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
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '当前设备繁忙，请稍后重试',
          en: 'Device is busy, please try again later.',
          ja: '端末が処理中です。しばらくしてから再試行してください。',
        ),
      );
    }
    if (!deviceCleared) {
      // 设备侧未清成功一律统一提示「设备暂时无法连接」，不把底层设备错误码抛给用户。
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '设备暂时无法连接',
          en: 'Device temporarily unavailable, please try again.',
          ja: '端末に一時的に接続できません。',
        ),
      );
    }

    // 2) 设备清空成功后再清后端记录；接口类错误如实提示，不误报成设备连不上。
    try {
      await BoltFoxApi.clearUserProductImg(deviceId);
    } catch (error) {
      return _apiFailure(error);
    }

    // 3) 同步本地：设备已无图（IMG_MASK 清零 / 当前索引复位），相册对应照片标记为不在设备上。
    device.imageMask = 0;
    device.currentImageIndex = 0;
    // 清空成功后即时回读设备信息(0x01)刷新内存/电量，不等下次列表/详情接口往返（对齐小程序 refreshDeviceMemoryFromBle）。
    // 读失败静默（设备刚擦完可能短暂无响应），随后 refreshDevices/详情会再同步；内存已随上面清零即时归位。
    try {
      final info = await client.readDeviceInfo();
      if (info.battery > 0) {
        device.batteryLevel = info.battery;
      }
      if (FrameProtocol.maskToIndexes(info.imgMask).isEmpty) {
        device.imageMask = 0;
        device.currentImageIndex = 0;
      }
    } catch (_) {
      // 回读失败不影响清空结果（已按成功处理）。
    }
    var clearedCount = 0;
    for (final photo in _albumPhotos.where(
      (item) => item.deviceId == deviceId && item.isOnDevice,
    )) {
      photo.isOnDevice = false;
      clearedCount += 1;
    }
    notifyListeners();
    return ActionFeedback(
      success: true,
      message: tr(
        zh: '已清空设备照片，共移除 $clearedCount 张。',
        en: 'Device photos cleared. Removed $clearedCount photos.',
        ja: '端末の写真をクリアし、$clearedCount 枚を削除しました。',
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
      await BoltFoxApi.loginOut();
    } catch (_) {
      // 退出登录接口失败时仍清除本地态。
    }
    ApiSession.instance.clear();
    // 退出登录同样清空上个账号的列表与首屏加载态，避免换账号后先看到上一个人的数据/空态。
    _devices.clear();
    _albumPhotos.clear();
    _castRecords.clear();
    _selectedDeviceId = '';
    _devicesLoaded = false;
    _albumLoaded = false;
    _castRecordsLoaded = false;
    _userLoaded = false;
    _isLoggedIn = false;
    _currentUser.email = '';
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
    ApiSession.instance.clear();
    // 注销后清空全部本地资产（不再按 ownerUserId 挑，见 myAlbum 注释），
    // 并把首屏加载态复位，下个账号进来才会重新走一次 loading 而不是直接看到上个账号的空态。
    _albumPhotos.clear();
    _castRecords.clear();
    _devices.clear();
    _selectedDeviceId = '';
    _devicesLoaded = false;
    _albumLoaded = false;
    _castRecordsLoaded = false;
    _userLoaded = false;
    _isLoggedIn = false;
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

  List<GuideArticle> buildGuideArticles() {
    return const [
      GuideArticle(
        category: 'Aurora S1',
        titleZh: '新设备绑定',
        titleEn: 'Bind a New Device',
        titleJa: '新しい端末のバインド',
        summaryZh: [
          '打开蓝牙和位置权限后，在首页或我的设备中发起蓝牙搜索。',
          '选中设备后可直接切换当前连接设备。',
          '输入 SN 码可重复绑定到不同账号，但所有者权限需要显式设置。',
        ],
        summaryEn: [
          'Enable Bluetooth and location, then start scanning from Home or My Devices.',
          'Select a device to switch the current active connection.',
          'SN codes can be reused, but owner permission must be explicitly assigned.',
        ],
        summaryJa: [
          'Bluetooth と位置情報を有効にし、ホームまたはマイデバイスから検索します。',
          '端末を選ぶと現在の接続先を切り替えられます。',
          'SN コードは再利用できますが、オーナー権限は明示的に設定します。',
        ],
      ),
      GuideArticle(
        category: 'Gallery Loop',
        titleZh: '投屏与容量管理',
        titleEn: 'Casting and Capacity',
        titleJa: '投映と容量管理',
        summaryZh: [
          '投屏前会预处理图片尺寸，并在预览页显示目标设备剩余容量。',
          '设备满载时会写入失败记录，并提示用户前往我的相册或联系所有者。',
          '我的相册只保留已成功写入设备的照片数据。',
        ],
        summaryEn: [
          'Images are preprocessed before casting and remaining capacity is shown in preview.',
          'If a device is full, a failed record is added and users are directed to My Album.',
          'My Album only shows photos successfully written to a device.',
        ],
        summaryJa: [
          '投映前に画像を前処理し、プレビューで残容量を表示します。',
          '容量不足の場合は失敗履歴を残し、マイアルバムまたはオーナー連絡を案内します。',
          'マイアルバムには端末への書き込み成功分のみ表示されます。',
        ],
      ),
      GuideArticle(
        category: 'Pocket Frame',
        titleZh: '轮播与清空',
        titleEn: 'Carousel and Clear',
        titleJa: 'スライド再生と全削除',
        summaryZh: [
          '所有者可以开启轮播模式，设备将按照当前展示图片的下一张进行切换。',
          '轮播切换按开启时间起算 24 小时后进入下一张。',
          '一键清空会删除设备物理内存中的照片，本工程默认不保留在我的相册中。',
        ],
        summaryEn: [
          'Owners can enable carousel mode to rotate to the next photo after the current one.',
          'Rotation advances every 24 hours from the moment carousel mode is enabled.',
          'One-tap clear removes physical device storage, and this demo removes those photos from My Album.',
        ],
        summaryJa: [
          'オーナーはスライド再生を有効化でき、現在の次の写真へ切り替わります。',
          '切り替えは有効化から 24 時間ごとに進みます。',
          '一括クリアは端末内の写真を削除し、このデモではマイアルバムからも外します。',
        ],
      ),
    ];
  }

  DeviceItem _findDevice(String deviceId) {
    return _devices.firstWhere((device) => device.id == deviceId);
  }

  /// 内置常见问题（接口失败 / 离线时的兜底文案，与小程序 guide 一致）。
  static List<FaqArticle> _seedFaqArticles() => [
    FaqArticle(
      id: 'faq-bind',
      question: '如何绑定设备?',
      answer:
          '1.确保相册设备已开机，并打开手机蓝牙。\n'
          '2.进入首页点击绑定设备，或「我的设备」。\n'
          '3.在设备列表中选择要连接的相册设备。\n'
          '4.点击「立即绑定」完成连接。\n'
          '若未搜索到设备，请确认设备在附近并重新搜索。',
    ),
    FaqArticle(
      id: 'faq-cast',
      question: '如何进行照片投屏?',
      answer: '进入首页，选择拍照或相册，确认照片后发送到已连接设备。',
    ),
    FaqArticle(
      id: 'faq-album',
      question: '如何管理我的相册?',
      answer: '进入我的图库，可查看、删除和重新投屏已上传的照片。',
    ),
    FaqArticle(
      id: 'faq-cleared',
      question: '设备照片被清空怎么办?',
      answer: '请在我的图库中重新选择照片投屏，或检查设备存储状态。',
    ),
    FaqArticle(
      id: 'faq-full',
      question: '相框空间已满怎么办?',
      answer:
          '设备空间已满时，新的照片将无法继续投屏。你可以前往「我的相册」删除部分照片，'
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

  /// 供页面主动刷新一次用户资料（对齐小程序 `mine.onShow` / `home.loadUserAvatar`）。
  /// 未登录直接跳过；成功后 `notifyListeners` 让「我的」等页面同步真实昵称/头像。
  Future<void> refreshCurrentUser() async {
    if (!_isLoggedIn) {
      // 未登录不拉接口，但首屏加载态照样要结束：否则 userLoaded 永远是 false，
      // 页面若单独依赖它（不像现在这样跟 albumLoaded 或起来用）就会永久卡在占位/loading。
      _userLoaded = true;
      notifyListeners();
      return;
    }
    await _refreshUserInfo();
    notifyListeners();
  }

  /// 登录后尽力拉取一次用户信息，失败不阻断登录流程。
  Future<void> _refreshUserInfo() async {
    try {
      final data = await BoltFoxApi.getUserInfo();
      _applyUserInfo(data);
    } catch (_) {
      // 用户信息拉取失败时保留本地占位资料。
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
    }
    final nick = data['nickName'];
    if (nick is String && nick.isNotEmpty) {
      _currentUser.nickname = nick;
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
    // 序列号（用于与广播 4 字节 / 固件 6 字节 Device_ID 交叉匹配）：后端字段就叫 deviceId，
    // 返回 6 字节 Device_ID（如 E9:48:C2:1E:D4:28）。取不到则连接复用 / 绑定判重都会失效。
    final serial = (data['deviceId'] ?? '').toString();
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

  /// 解析后端时间字段（ISO 字符串或时间戳），失败回退当前时间。
  DateTime _parseDate(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    if (value is int) {
      // 13 位按毫秒、10 位按秒处理。
      final millis = value > 1000000000000 ? value : value * 1000;
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    return DateTime.now();
  }

  /// 常见问题列表：`/Client/Product/getProductFaqList`，映射为 [FaqArticle]。
  /// 仅在后端返回非空时替换本地列表（失败保留内置 FAQ）。
  Future<ActionFeedback> refreshFaq() async {
    try {
      final data = await BoltFoxApi.getProductFaqList({
        'pageIndex': 1,
        'pageSize': 100,
      });
      final rows = extractApiRows(data);
      if (rows.isNotEmpty) {
        _faqArticles
          ..clear()
          ..addAll(rows.map(_faqFromJson));
        notifyListeners();
      }
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
    final index = _faqArticles.indexWhere((faq) => faq.id == id);
    if (index < 0) {
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
        _faqArticles[index].answer = answer;
        notifyListeners();
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

  /// 把后端相册图片记录映射为 [AlbumPhoto]；BLE 相关字段给默认值。
  ///
  /// 字段名以后端 swagger `ClientUserProductImgApiOut` 为准：
  /// `uProductImgId` / `img`(图片地址) / `imgBle`(设备帧 .bin) / `productName`(设备名) /
  /// `userProductId` / `deviceId`。该接口**不下发任何时间字段**，故 [AlbumPhoto.uploadedAt]
  /// 只用于本地排序，不要在 UI 上当成真实上传时间展示。
  /// 原实现读的 `imgName` / `createTime` 等键后端根本不存在——标题永远是「照片」、
  /// imgBle 整个丢掉（图库照片没法再次投屏）。
  AlbumPhoto _albumPhotoFromJson(Map<String, dynamic> data, int index) {
    final id =
        (data['uProductImgId'] ?? data['uproductImgId'] ?? _nextId('photo'))
            .toString();
    final deviceId = (data['userProductId'] ?? '').toString();
    final deviceName = (data['productName'] ?? '').toString();
    final url = (data['img'] ?? '').toString();
    final imgBle = (data['imgBle'] ?? '').toString();
    return AlbumPhoto(
      id: id,
      // 小程序 normalizePhoto 的 title 取 productName，没有则「照片 N」。
      title: deviceName.isNotEmpty ? deviceName : '照片 ${index + 1}',
      source: ImageSourceType.album,
      deviceId: deviceId,
      deviceName: deviceName,
      ownerUserId: _currentUser.id,
      imageIndex: 0,
      imageMaskBit: 0,
      width: 0,
      height: 0,
      targetWidth: 0,
      targetHeight: 0,
      transferBytes: 0,
      crc32: 0,
      color: _paletteColor(index),
      note: '',
      // 后端无时间字段：保持列表原序（后端已按时间倒序），故这里按下标构造递减时间戳，
      // 避免 myAlbum 里按 uploadedAt 排序时全部相等而打乱后端顺序。
      uploadedAt: DateTime.now().subtract(Duration(microseconds: index)),
      imageUrl: url.isEmpty ? null : url,
      imgBle: imgBle.isEmpty ? null : imgBle,
    );
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
    // 设备帧文件地址：再次投屏直传设备用（不走后端转码）。
    final imgBle = (data['imgBle'] ?? '').toString();
    final status = _castStatusFromJson(data);
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
      createdAt: _parseDate(data['upTime'] ?? data['joinTime']),
      imageUrl: url.isEmpty ? null : url,
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
    ApiSession.instance.clear();
    _devices.clear();
    _albumPhotos.clear();
    _castRecords.clear();
    _selectedDeviceId = '';
    _devicesLoaded = false;
    _albumLoaded = false;
    _castRecordsLoaded = false;
    _userLoaded = false;
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
