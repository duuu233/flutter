import 'package:flutter/material.dart';

import 'device/frame_device_protocol.dart';
import 'network/api_exception.dart';
import 'network/api_session.dart';
import 'network/boltfox_api.dart';

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

class UserProfile {
  UserProfile({
    required this.id,
    required this.nickname,
    required this.email,
    required this.avatarColor,
    required this.signature,
  });

  final String id;
  String nickname;
  String email;
  Color avatarColor;
  String signature;
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

  int get capacity => FrameProtocolConfig.maxImages;

  int get imageCount => FrameDeviceProtocol.countImages(imageMask);

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

  /// 后端图片地址（来自 `getUserProductImgList`）；为空时回退占位色块。
  final String? imageUrl;
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
      _cameraCounter = 4,
      _isLoggedIn = true,
      _isOffline = false,
      _currentUser = UserProfile(
        id: 'USR-2048',
        nickname: '林岚',
        email: 'linlan@example.com',
        avatarColor: const Color(0xFFBC6C25),
        signature: '把生活里的光，留给会发亮的相框。',
      ),
      _permissions = {
        PermissionKind.location: true,
        PermissionKind.bluetooth: true,
        PermissionKind.album: false,
        PermissionKind.camera: false,
      },
      _devices = [
        DeviceItem(
          id: 'dev-aurora',
          name: '房间相册',
          kind: '5.89寸六色墨水屏',
          screenType: FrameScreenType.inch589,
          batteryLevel: 30,
          charging: false,
          connected: false,
          role: DeviceRole.owner,
          serialNumber: 'SN-AUR-240018',
          hardwareVersion: 'HW-1.0',
          firmwareVersion: 'FW_V1.0.5_20260402',
          imageMask: 0x00000003,
          currentImageIndex: 1,
          playbackMode: FramePlaybackMode.sequence,
          carouselIntervalSeconds:
              FrameProtocolConfig.defaultCarouselIntervalSeconds,
          carouselEnabled: true,
        ),
        DeviceItem(
          id: 'dev-gallery',
          name: '卧室相框',
          kind: '7.3寸六色墨水屏',
          screenType: FrameScreenType.inch73,
          batteryLevel: 43,
          charging: true,
          connected: false,
          role: DeviceRole.user,
          serialNumber: 'SN-GAL-983602',
          hardwareVersion: 'HW-1.0',
          firmwareVersion: 'FW_V1.0.5_20260402',
          imageMask: 0x00000001,
          currentImageIndex: 0,
          playbackMode: FramePlaybackMode.manual,
          carouselIntervalSeconds:
              FrameProtocolConfig.defaultCarouselIntervalSeconds,
          carouselEnabled: false,
        ),
        DeviceItem(
          id: 'dev-pocket',
          name: '书房相框',
          kind: '3.7寸六色墨水屏',
          screenType: FrameScreenType.inch37,
          batteryLevel: 91,
          charging: false,
          connected: false,
          role: DeviceRole.user,
          serialNumber: 'SN-PKT-661245',
          hardwareVersion: 'HW-1.0',
          firmwareVersion: 'FW_V1.0.5_20260402',
          imageMask: 0x00000000,
          currentImageIndex: -1,
          playbackMode: FramePlaybackMode.sequence,
          carouselIntervalSeconds:
              FrameProtocolConfig.defaultCarouselIntervalSeconds,
          carouselEnabled: true,
        ),
      ],
      _selectedDeviceId = 'dev-aurora',
      _draftLibrary = const [
        DraftPhoto(
          id: 'draft-1',
          title: '玄关晨光',
          source: ImageSourceType.album,
          width: 3024,
          height: 4032,
          color: Color(0xFFE07A5F),
          note: '自动裁剪为 3:4，适合竖版相框',
        ),
        DraftPhoto(
          id: 'draft-2',
          title: '海风留白',
          source: ImageSourceType.album,
          width: 3840,
          height: 2160,
          color: Color(0xFF3D5A80),
          note: '横版照片，建议投放壁挂设备',
        ),
        DraftPhoto(
          id: 'draft-3',
          title: '窗边手作',
          source: ImageSourceType.album,
          width: 2400,
          height: 2400,
          color: Color(0xFF6B705C),
          note: '正方形构图，将保留完整边距',
        ),
        DraftPhoto(
          id: 'draft-4',
          title: '夜色吧台',
          source: ImageSourceType.album,
          width: 2592,
          height: 3872,
          color: Color(0xFF6D597A),
          note: '高对比度照片，适合深色边框',
        ),
        DraftPhoto(
          id: 'draft-5',
          title: '晚霞远山',
          source: ImageSourceType.album,
          width: 4080,
          height: 3072,
          color: Color(0xFFCB997E),
          note: '预处理后输出 1600px 长边',
        ),
      ],
      _albumPhotos = [
        AlbumPhoto(
          id: 'photo-1',
          title: '栖居午后',
          source: ImageSourceType.album,
          deviceId: 'dev-aurora',
          ownerUserId: 'USR-2048',
          imageIndex: 0,
          imageMaskBit: FrameDeviceProtocol.bitForIndex(0),
          width: 2400,
          height: 3200,
          targetWidth: FrameScreenType.inch589.width,
          targetHeight: FrameScreenType.inch589.height,
          transferBytes: FrameScreenType.inch589.frameBufferBytes,
          crc32: 0x1A2B3C40,
          color: const Color(0xFF7F5539),
          note: '已成功上传至 Aurora S1',
          uploadedAt: DateTime(2026, 4, 22, 10, 12),
        ),
        AlbumPhoto(
          id: 'photo-2',
          title: '山谷云层',
          source: ImageSourceType.camera,
          deviceId: 'dev-aurora',
          ownerUserId: 'USR-2048',
          imageIndex: 1,
          imageMaskBit: FrameDeviceProtocol.bitForIndex(1),
          width: 3024,
          height: 4032,
          targetWidth: FrameScreenType.inch589.width,
          targetHeight: FrameScreenType.inch589.height,
          transferBytes: FrameScreenType.inch589.frameBufferBytes,
          crc32: 0x1A2B3C41,
          color: const Color(0xFF588157),
          note: '由拍照流程上传',
          uploadedAt: DateTime(2026, 4, 22, 17, 40),
        ),
        AlbumPhoto(
          id: 'photo-3',
          title: '暮色灯塔',
          source: ImageSourceType.album,
          deviceId: 'dev-gallery',
          ownerUserId: 'USR-2048',
          imageIndex: 0,
          imageMaskBit: FrameDeviceProtocol.bitForIndex(0),
          width: 3840,
          height: 2160,
          targetWidth: FrameScreenType.inch73.width,
          targetHeight: FrameScreenType.inch73.height,
          transferBytes: FrameScreenType.inch73.frameBufferBytes,
          crc32: 0x1A2B3C42,
          color: const Color(0xFF355070),
          note: '横版样片，适配壁挂设备',
          uploadedAt: DateTime(2026, 4, 21, 20, 18),
        ),
      ],
      _castRecords = [
        CastRecord(
          id: 'record-1',
          title: '栖居午后',
          deviceId: 'dev-aurora',
          ownerUserId: 'USR-2048',
          status: CastStatus.success,
          source: ImageSourceType.album,
          color: const Color(0xFF7F5539),
          width: 2400,
          height: 3200,
          message: '投屏完成，已写入设备存储。',
          createdAt: DateTime(2026, 4, 22, 10, 13),
          imageIndex: 0,
          command: FrameCommand.finishTransfer,
          resultCode: FrameProtocolResultCode.success,
          imageMask: 0x00000003,
          photoId: 'photo-1',
        ),
        CastRecord(
          id: 'record-2',
          title: '山谷云层',
          deviceId: 'dev-aurora',
          ownerUserId: 'USR-2048',
          status: CastStatus.success,
          source: ImageSourceType.camera,
          color: const Color(0xFF588157),
          width: 3024,
          height: 4032,
          message: '拍照处理成功，已投放到当前设备。',
          createdAt: DateTime(2026, 4, 22, 17, 41),
          imageIndex: 1,
          command: FrameCommand.finishTransfer,
          resultCode: FrameProtocolResultCode.success,
          imageMask: 0x00000003,
          photoId: 'photo-2',
        ),
        CastRecord(
          id: 'record-3',
          title: '雨夜街口',
          deviceId: 'dev-gallery',
          ownerUserId: 'USR-2048',
          status: CastStatus.failed,
          source: ImageSourceType.album,
          color: const Color(0xFF9C6644),
          width: 3024,
          height: 4032,
          message: '设备内存已满，请清理相册或联系设备所有者。',
          createdAt: DateTime(2026, 4, 21, 22, 06),
          command: FrameCommand.startTransfer,
          resultCode: FrameProtocolResultCode.storageFull,
          imageMask: 0xFFFFFFFF,
        ),
      ];

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

  AppLanguage get language => _language;

  bool get isLoggedIn => _isLoggedIn;

  /// 是否处于离线模式。接入真实网络监测后，在网络异常时调用 [setOffline]。
  bool get isOffline => _isOffline;

  UserProfile get currentUser => _currentUser;

  List<DeviceItem> get devices => List.unmodifiable(_devices);

  List<DraftPhoto> get draftLibrary => List.unmodifiable(_draftLibrary);

  List<AlbumPhoto> get myAlbum {
    final items = _albumPhotos
        .where(
          (photo) => photo.ownerUserId == _currentUser.id && photo.isOnDevice,
        )
        .toList();
    items.sort((left, right) => right.uploadedAt.compareTo(left.uploadedAt));
    return items;
  }

  List<CastRecord> get castRecords => List.unmodifiable(_castRecords);

  List<FaqArticle> get faqArticles => List.unmodifiable(_faqArticles);

  Map<PermissionKind, bool> get permissions => Map.unmodifiable(_permissions);

  DeviceItem get selectedDevice => _findDevice(_selectedDeviceId);

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

  void connectDevice(String deviceId) {
    for (final device in _devices) {
      device.connected = device.id == deviceId;
    }
    _selectedDeviceId = deviceId;
    notifyListeners();
  }

  /// 邮箱密码登录入口。
  ///
  /// 调用 `/Client/User/userLogin`，成功后把返回的登录 token 写入
  /// [ApiSession]（后续接口才会带上 `userToken` header），并尽力拉取一次用户信息。
  Future<ActionFeedback> loginWithPassword(String email, String password) async {
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
      final data = await BoltFoxApi.userLogin(email: target, password: password);
      final token = _readToken(data);
      if (token != null && token.isNotEmpty) {
        ApiSession.instance.setToken(token);
      }
      _isLoggedIn = true;
      _currentUser.email = target;
      await _refreshUserInfo();
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

  /// 发送邮箱验证码。[sendType]：1=注册、2=找回/改密、3=改邮箱。
  /// [loggedIn] 为 true 时走已登录通道 `sendEmailToken`，否则走 `sendEmail`。
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
      if (loggedIn) {
        await BoltFoxApi.sendEmailToken(
          userEmail: target.isEmpty ? null : target,
          sendType: sendType,
        );
      } else {
        await BoltFoxApi.sendEmail(userEmail: target, sendType: sendType);
      }
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
      await BoltFoxApi.changeUserEmail(email: target, emailCode: emailCode.trim());
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
        message: tr(zh: '个人信息已更新。', en: 'Profile updated.', ja: 'プロフィールを更新しました。'),
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
        if (userProductId != null) 'userProductId': userProductId,
      });
      final rows = _extractRows(data);
      if (rows.isNotEmpty) {
        final mapped = <AlbumPhoto>[];
        for (var i = 0; i < rows.length; i++) {
          mapped.add(_albumPhotoFromJson(rows[i], i));
        }
        _albumPhotos
          ..clear()
          ..addAll(mapped);
        notifyListeners();
      }
      return ActionFeedback(
        success: true,
        message: tr(zh: '相册已更新。', en: 'Album refreshed.', ja: 'アルバムを更新しました。'),
      );
    } catch (error) {
      return _apiFailure(error);
    }
  }

  /// 删除相册照片（支持多选）：先调用 `/Client/UserProduct/delUserProductImg`，
  /// 成功后再同步本地（对带 IMG_MASK 的种子照片更新设备掩码，统一软删除）。
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
          (photo) =>
              photoIds.contains(photo.id) &&
              photo.ownerUserId == _currentUser.id &&
              photo.isOnDevice,
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
    try {
      await BoltFoxApi.delUserProductImg(
        photos.map((photo) => photo.id as Object).toList(),
      );
    } catch (error) {
      return _apiFailure(error);
    }
    final photosByDevice = <String, List<AlbumPhoto>>{};
    for (final photo in photos) {
      photosByDevice
          .putIfAbsent(photo.deviceId, () => <AlbumPhoto>[])
          .add(photo);
    }
    for (final entry in photosByDevice.entries) {
      // 后端相册的 deviceId 可能不在当前设备列表中，找不到设备时跳过掩码同步。
      final matches = _devices.where((device) => device.id == entry.key);
      if (matches.isNotEmpty) {
        final device = matches.first;
        var deleteMask = 0;
        for (final photo in entry.value) {
          deleteMask |= photo.imageMaskBit;
        }
        if (deleteMask != 0) {
          final result = FrameDeviceProtocol.simulateDeleteImages(
            imageMask: device.imageMask,
            deleteMask: deleteMask,
            screenType: device.screenType,
            currentImageIndex: device.currentImageIndex,
          );
          if (result.success) {
            device.imageMask = result.imageMask;
            device.currentImageIndex = result.currentImageIndex;
          }
        }
      }
      for (final photo in entry.value) {
        photo.isOnDevice = false;
      }
    }
    notifyListeners();
    return ActionFeedback(
      success: true,
      message: tr(
        zh: '已删除所选照片。',
        en: 'Selected photos deleted.',
        ja: '選択した写真を削除しました。',
      ),
    );
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
  Future<ActionFeedback> refreshCastRecords({String? userProductId}) async {
    try {
      final data = await BoltFoxApi.getUserProductImgRecordList({
        'pageIndex': 1,
        'pageSize': 100,
        if (userProductId != null) 'userProductId': userProductId,
      });
      final rows = _extractRows(data);
      if (rows.isNotEmpty) {
        final mapped = <CastRecord>[];
        for (var i = 0; i < rows.length; i++) {
          mapped.add(_castRecordFromJson(rows[i], i));
        }
        _castRecords
          ..clear()
          ..addAll(mapped);
        notifyListeners();
      }
      return ActionFeedback(
        success: true,
        message: tr(zh: '投屏记录已更新。', en: 'Records refreshed.', ja: '投映履歴を更新しました。'),
      );
    } catch (error) {
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
    try {
      await BoltFoxApi.editUserProduct(userProductId: deviceId, productName: value);
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
        'pageSize': 50,
      });
      final rows = _extractRows(data);
      if (rows.isNotEmpty) {
        final mapped = rows.map(_deviceFromJson).toList();
        _devices
          ..clear()
          ..addAll(mapped);
        if (!_devices.any((device) => device.id == _selectedDeviceId)) {
          _selectedDeviceId = _devices.first.id;
        }
        notifyListeners();
      }
      return ActionFeedback(
        success: true,
        message: tr(zh: '设备列表已更新。', en: 'Devices refreshed.', ja: '端末一覧を更新しました。'),
      );
    } catch (error) {
      return _apiFailure(error);
    }
  }

  /// 绑定设备：`/Client/UserProduct/addUserProduct`，成功后重新拉取列表取服务端 id。
  Future<ActionFeedback> bindDevice({
    required int productId,
    required String productName,
    required String productSerialNo,
  }) async {
    try {
      await BoltFoxApi.addUserProduct(
        productId: productId,
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

  /// 删除 / 解绑设备：`/Client/UserProduct/delUserProduct`，成功后清理本地设备与相关数据。
  Future<ActionFeedback> deleteDevice(String deviceId) async {
    try {
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

  /// 一键清空设备：先调用 `/Client/UserProduct/clearUserProductImg`，
  /// 成功后再同步本地 IMG_MASK 与「我的相册」在设备上的照片。
  Future<ActionFeedback> clearDeviceMemory(String deviceId) async {
    final device = _findDevice(deviceId);
    final deleteMask = device.imageMask;
    if (deleteMask == 0) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '设备内没有可清空的照片。',
          en: 'There are no photos to clear.',
          ja: 'クリアできる写真がありません。',
        ),
      );
    }
    try {
      await BoltFoxApi.clearUserProductImg(deviceId);
    } catch (error) {
      return _apiFailure(error);
    }
    final result = FrameDeviceProtocol.simulateDeleteImages(
      imageMask: device.imageMask,
      deleteMask: deleteMask,
      screenType: device.screenType,
      currentImageIndex: device.currentImageIndex,
    );
    if (!result.success) {
      return ActionFeedback(
        success: false,
        message: tr(
          zh: '清空失败：${result.resultCode.labelZh}。',
          en: 'Clear failed: ${result.resultCode.labelZh}.',
          ja: 'クリアに失敗しました: ${result.resultCode.labelZh}。',
        ),
      );
    }
    device.imageMask = result.imageMask;
    device.currentImageIndex = result.currentImageIndex;
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
        zh: '已通过删除全量 IMG_MASK 清空设备，共移除 $clearedCount 张照片。',
        en: 'Device memory cleared. Removed $clearedCount photos.',
        ja: '端末メモリをクリアし、$clearedCount 枚を削除しました。',
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
    _isLoggedIn = false;
    _currentUser.email = '';
    notifyListeners();
  }

  /// 用户注销：调用 `/Client/User/userOff` 并清除本地登录态与本地资产。
  Future<void> deleteAccount() async {
    try {
      await BoltFoxApi.userOff();
    } catch (_) {
      // 注销接口失败时仍清除本地态。
    }
    ApiSession.instance.clear();
    _albumPhotos.removeWhere((photo) => photo.ownerUserId == _currentUser.id);
    _castRecords.removeWhere((record) => record.ownerUserId == _currentUser.id);
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

  /// 登录后尽力拉取一次用户信息，失败不阻断登录流程。
  Future<void> _refreshUserInfo() async {
    try {
      final data = await BoltFoxApi.getUserInfo();
      _applyUserInfo(data);
    } catch (_) {
      // 用户信息拉取失败时保留本地占位资料。
    }
  }

  /// 用后端用户信息覆盖本地展示字段（昵称 / 邮箱）。
  /// 设备、相册等数据仍走本地 mock，故此处不改写用户 id，避免本地数据过滤错乱。
  void _applyUserInfo(dynamic data) {
    if (data is! Map) {
      return;
    }
    final nick = data['nickName'] ?? data['nickname'];
    if (nick is String && nick.isNotEmpty) {
      _currentUser.nickname = nick;
    }
    final email = data['email'] ?? data['userEmail'];
    if (email is String && email.isNotEmpty) {
      _currentUser.email = email;
    }
  }

  /// 从分页接口 retData 中取出数据行，兼容直接返回数组或包裹在
  /// `list/rows/records/data/items` 字段中的两种常见结构。
  List<Map<String, dynamic>> _extractRows(dynamic data) {
    dynamic rows = data;
    if (data is Map) {
      rows = data['list'] ??
          data['rows'] ??
          data['records'] ??
          data['data'] ??
          data['items'];
    }
    if (rows is List) {
      return rows
          .whereType<Map>()
          .map((row) => row.map((key, value) => MapEntry(key.toString(), value)))
          .toList();
    }
    return const [];
  }

  /// 把后端设备记录映射为 [DeviceItem]；蓝牙字段给安全默认值，连接后再由 BLE 更新。
  DeviceItem _deviceFromJson(Map<String, dynamic> data) {
    final id = (data['userProductId'] ?? data['id'] ?? _nextId('dev')).toString();
    final name = (data['productName'] ?? data['name'] ?? '相框').toString();
    final serial =
        (data['productSerialNo'] ?? data['serialNo'] ?? data['sn'] ?? '')
            .toString();
    final firmware =
        (data['productVersionNo'] ?? data['firmwareVersion'] ?? '').toString();
    return DeviceItem(
      id: id,
      name: name,
      kind: (data['productTypeName'] ?? data['kind'] ?? '').toString(),
      screenType: FrameScreenType.inch589,
      batteryLevel: 0,
      charging: false,
      connected: false,
      role: DeviceRole.owner,
      serialNumber: serial,
      hardwareVersion: (data['hardwareVersion'] ?? 'HW-1.0').toString(),
      firmwareVersion: firmware,
      imageMask: 0,
      currentImageIndex: -1,
      playbackMode: FramePlaybackMode.sequence,
      carouselIntervalSeconds:
          FrameProtocolConfig.defaultCarouselIntervalSeconds,
      carouselEnabled: false,
    );
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
      final rows = _extractRows(data);
      if (rows.isNotEmpty) {
        _faqArticles
          ..clear()
          ..addAll(rows.map(_faqFromJson));
        notifyListeners();
      }
      return ActionFeedback(
        success: true,
        message: tr(zh: '帮助文档已更新。', en: 'Help docs refreshed.', ja: 'ヘルプを更新しました。'),
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
        answer = (data['content'] ?? data['answer'] ?? data['faqContent'])
            ?.toString();
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

  FaqArticle _faqFromJson(Map<String, dynamic> data) {
    return FaqArticle(
      id: (data['faqId'] ?? data['id'] ?? _nextId('faq')).toString(),
      question: (data['title'] ?? data['question'] ?? data['faqTitle'] ?? '')
          .toString(),
      answer: (data['content'] ?? data['answer'] ?? data['faqContent'] ?? '')
          .toString(),
    );
  }

  /// 把后端相册图片记录映射为 [AlbumPhoto]；BLE 相关字段给默认值。
  AlbumPhoto _albumPhotoFromJson(Map<String, dynamic> data, int index) {
    final id =
        (data['uProductImgId'] ?? data['id'] ?? _nextId('photo')).toString();
    final deviceId =
        (data['userProductId'] ?? data['deviceId'] ?? '').toString();
    final url = (data['img'] ?? data['imgUrl'] ?? data['url'] ?? data['imageUrl'])
        ?.toString();
    return AlbumPhoto(
      id: id,
      title: (data['imgName'] ?? data['name'] ?? data['title'] ?? '照片')
          .toString(),
      source: ImageSourceType.album,
      deviceId: deviceId,
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
      uploadedAt: _parseDate(
        data['createTime'] ?? data['createdAt'] ?? data['uploadTime'],
      ),
      imageUrl: (url == null || url.isEmpty) ? null : url,
    );
  }

  /// 把后端投屏记录映射为 [CastRecord]；成功/失败由后端状态字段判定（取值待确认）。
  CastRecord _castRecordFromJson(Map<String, dynamic> data, int index) {
    final id = (data['upirId'] ?? data['id'] ?? _nextId('record')).toString();
    final deviceId =
        (data['userProductId'] ?? data['deviceId'] ?? '').toString();
    final url = (data['img'] ?? data['imgUrl'] ?? data['url'] ?? data['imageUrl'])
        ?.toString();
    return CastRecord(
      id: id,
      title: (data['imgName'] ?? data['productName'] ?? data['title'] ?? '投屏记录')
          .toString(),
      deviceId: deviceId,
      ownerUserId: _currentUser.id,
      status: _castStatusFromJson(data),
      source: ImageSourceType.album,
      color: _paletteColor(index),
      width: 0,
      height: 0,
      message: (data['remark'] ?? data['message'] ?? data['failReason'] ?? '')
          .toString(),
      createdAt: _parseDate(
        data['createTime'] ?? data['createdAt'] ?? data['projectionTime'],
      ),
      imageUrl: (url == null || url.isEmpty) ? null : url,
    );
  }

  /// 由后端状态字段判定投屏成功/失败（字段与取值以后端为准，待联调确认）。
  CastStatus _castStatusFromJson(Map<String, dynamic> data) {
    final raw = data['uploadState'] ??
        data['state'] ??
        data['status'] ??
        data['deviceUploadState'] ??
        data['isSuccess'];
    if (raw == null) {
      return CastStatus.success;
    }
    final value = raw.toString().toLowerCase();
    const failed = {'0', 'false', 'fail', 'failed', 'error', '-1'};
    return failed.contains(value) ? CastStatus.failed : CastStatus.success;
  }

  /// 把接口异常映射为页面可展示的 [ActionFeedback]，优先透传后端 `retMsg`。
  ActionFeedback _apiFailure(Object error) {
    if (error is ApiException) {
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

  String _nextId(String prefix) {
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
  }

  bool _isValidEmail(String email) {
    final trimmed = email.trim();
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(trimmed);
  }
}
