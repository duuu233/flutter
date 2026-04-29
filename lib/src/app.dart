import 'package:flutter/material.dart';

import 'state.dart';

class FrameFlowApp extends StatefulWidget {
  const FrameFlowApp({super.key});

  @override
  State<FrameFlowApp> createState() => _FrameFlowAppState();
}

class _FrameFlowAppState extends State<FrameFlowApp> {
  final PhotoFrameState _state = PhotoFrameState.seeded();
  int _currentIndex = 0;

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _state,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: _state.tr(
            zh: '相框投屏',
            en: 'Frame Cast',
            ja: 'フレーム投映',
          ),
          theme: _buildTheme(),
          home: _Shell(
            state: _state,
            currentIndex: _currentIndex,
            onIndexChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
          ),
        );
      },
    );
  }

  ThemeData _buildTheme() {
    const primary = Color(0xFF234E52);
    const secondary = Color(0xFFD97757);
    const surface = Color(0xFFF6EFE5);
    const onSurface = Color(0xFF1F2933);

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
      ).copyWith(
        primary: primary,
        secondary: secondary,
        surface: surface,
        onSurface: onSurface,
        error: const Color(0xFFB5412F),
      ),
      scaffoldBackgroundColor: surface,
      textTheme: const TextTheme(
        displaySmall: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.4,
          color: onSurface,
        ),
        headlineSmall: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
          color: onSurface,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: onSurface,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: onSurface,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          height: 1.45,
          color: onSurface,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.45,
          color: Color(0xFF4B5563),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      dividerTheme: DividerThemeData(
        color: Colors.black.withValues(alpha: 0.08),
        thickness: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1F2933),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.72),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: secondary, width: 1.2),
        ),
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({
    required this.state,
    required this.currentIndex,
    required this.onIndexChanged,
  });

  final PhotoFrameState state;
  final int currentIndex;
  final ValueChanged<int> onIndexChanged;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const _AtmosphereBackground(),
          SafeArea(
            bottom: false,
            child: IndexedStack(
              index: currentIndex,
              children: [
                _HomePage(
                  state: state,
                  onOpenMine: () => onIndexChanged(1),
                ),
                _MinePage(state: state),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              color: Colors.white.withValues(alpha: 0.82),
              boxShadow: [
                BoxShadow(
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                  color: Colors.black.withValues(alpha: 0.08),
                ),
              ],
            ),
            child: NavigationBar(
              selectedIndex: currentIndex,
              backgroundColor: Colors.transparent,
              indicatorColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
              onDestinationSelected: onIndexChanged,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.cast_connected_outlined),
                  selectedIcon: const Icon(Icons.cast_connected),
                  label: state.tr(
                    zh: '首页',
                    en: 'Home',
                    ja: 'ホーム',
                  ),
                ),
                NavigationDestination(
                  icon: const Icon(Icons.person_outline),
                  selectedIcon: const Icon(Icons.person),
                  label: state.tr(
                    zh: '我的',
                    en: 'Mine',
                    ja: 'マイ',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AtmosphereBackground extends StatelessWidget {
  const _AtmosphereBackground();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF7EDE2),
                  Color(0xFFF2E2D1),
                  Color(0xFFEADCCA),
                ],
              ),
            ),
          ),
          const Positioned(
            top: -120,
            left: -80,
            child: _GlowOrb(
              size: 260,
              color: Color(0xFFB8D8D8),
            ),
          ),
          const Positioned(
            top: 100,
            right: -40,
            child: _GlowOrb(
              size: 190,
              color: Color(0xFFF2CC8F),
            ),
          ),
          const Positioned(
            bottom: 120,
            left: -30,
            child: _GlowOrb(
              size: 200,
              color: Color(0xFFD4A373),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: 0.34),
            color.withValues(alpha: 0.04),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage({
    required this.state,
    required this.onOpenMine,
  });

  final PhotoFrameState state;
  final VoidCallback onOpenMine;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedDevice = state.selectedDevice;
    final usage = state.deviceUsage(selectedDevice.id);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          sliver: SliverList(
            delegate: SliverChildListDelegate(
              [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF102A43),
                        Color(0xFF234E52),
                        Color(0xFF2A6F6F),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 26,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              state.tr(
                                zh: '相框投屏',
                                en: 'Frame Cast',
                                ja: 'フレーム投映',
                              ),
                              key: const Key('home-title'),
                              style: theme.textTheme.displaySmall?.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ),
                          _StatTag(
                            label: '${selectedDevice.batteryLevel}%',
                            icon: Icons.battery_5_bar_rounded,
                            foreground: Colors.white,
                            background: Colors.white.withValues(alpha: 0.12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        state.tr(
                          zh: '围绕拍照、相册、设备切换和投屏记录的一体化工作台。',
                          en: 'A unified workspace for capture, album upload, device switching and casting records.',
                          ja: '撮影、アルバム、端末切替、投映履歴をまとめたワークスペース。',
                        ),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: Colors.white.withValues(alpha: 0.82),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _HeroMetric(
                            label: state.tr(
                              zh: '当前设备',
                              en: 'Active Device',
                              ja: '現在の端末',
                            ),
                            value: selectedDevice.name,
                          ),
                          _HeroMetric(
                            label: state.tr(
                              zh: '容量占用',
                              en: 'Capacity',
                              ja: '容量',
                            ),
                            value: '$usage/${selectedDevice.capacity}',
                          ),
                          _HeroMetric(
                            label: state.tr(
                              zh: '启用权限',
                              en: 'Permissions',
                              ja: '権限',
                            ),
                            value: '${state.activePermissionCount}/3',
                          ),
                          _HeroMetric(
                            label: state.tr(
                              zh: '成功率',
                              en: 'Success Rate',
                              ja: '成功率',
                            ),
                            value: '${(state.successRate * 100).round()}%',
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () => _startCameraCast(context),
                              icon: const Icon(Icons.photo_camera_outlined),
                              label: Text(
                                state.tr(
                                  zh: '拍照投屏',
                                  en: 'Camera Cast',
                                  ja: '撮影して投映',
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFD97757),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _showDevicePicker(context),
                              icon: const Icon(Icons.bluetooth_searching_rounded),
                              label: Text(
                                state.tr(
                                  zh: '切换设备',
                                  en: 'Switch Device',
                                  ja: '端末切替',
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _SectionHeader(
                  title: state.tr(
                    zh: '投屏入口',
                    en: 'Casting Entries',
                    ja: '投映入口',
                  ),
                  subtitle: state.tr(
                    zh: '覆盖拍照、相册、权限和蓝牙绑定。',
                    en: 'Cover camera, album, permissions and Bluetooth binding.',
                    ja: '撮影、アルバム、権限、Bluetooth バインドをまとめます。',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.collections_outlined,
                        title: state.tr(
                          zh: '相册选图',
                          en: 'Album Picker',
                          ja: 'アルバム選択',
                        ),
                        subtitle: state.tr(
                          zh: '挑选样片并进入设备预览。',
                          en: 'Pick a sample and open device preview.',
                          ja: '画像を選んで端末プレビューへ進みます。',
                        ),
                        accent: const Color(0xFF3D5A80),
                        onTap: () => _startAlbumCast(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.verified_user_outlined,
                        title: state.tr(
                          zh: '权限检查',
                          en: 'Permissions',
                          ja: '権限確認',
                        ),
                        subtitle: state.tr(
                          zh: '位置、蓝牙、相机统一配置。',
                          en: 'Manage location, Bluetooth and camera.',
                          ja: '位置情報・Bluetooth・カメラを一括設定。',
                        ),
                        accent: const Color(0xFF6B705C),
                        onTap: () => _showPermissionPanel(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _ActionCard(
                  icon: Icons.route_rounded,
                  title: state.tr(
                    zh: '投屏流程',
                    en: 'Casting Flow',
                    ja: '投映フロー',
                  ),
                  subtitle: state.tr(
                    zh: '选择图片 > 选择设备 > 预览尺寸 > 确认投屏。',
                    en: 'Select image > device > preview size > confirm cast.',
                    ja: '画像選択 > 端末選択 > サイズ確認 > 投映確定。',
                  ),
                  accent: const Color(0xFFD4A373),
                  onTap: () => _showFlowGuide(context),
                ),
                const SizedBox(height: 20),
                _SectionHeader(
                  title: state.tr(
                    zh: '当前设备',
                    en: 'Current Device',
                    ja: '現在の端末',
                  ),
                  subtitle: state.tr(
                    zh: '支持设备切换、容量查看和轮播状态查看。',
                    en: 'Switch devices and inspect capacity and carousel state.',
                    ja: '端末切替、容量確認、スライド状態確認に対応。',
                  ),
                ),
                const SizedBox(height: 12),
                _Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _DeviceIllustration(color: const Color(0xFF234E52)),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(selectedDevice.name, style: theme.textTheme.titleLarge),
                                const SizedBox(height: 4),
                                Text(
                                  selectedDevice.kind,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          _StatusPill(
                            label: state.roleLabel(selectedDevice.role),
                            active: selectedDevice.role == DeviceRole.owner,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _StatTag(
                            label: '${selectedDevice.batteryLevel}%',
                            icon: Icons.battery_full_rounded,
                            foreground: theme.colorScheme.primary,
                            background: theme.colorScheme.primary.withValues(alpha: 0.10),
                          ),
                          _StatTag(
                            label: '$usage/${selectedDevice.capacity}',
                            icon: Icons.photo_library_outlined,
                            foreground: const Color(0xFFD97757),
                            background: const Color(0xFFD97757).withValues(alpha: 0.12),
                          ),
                          _StatTag(
                            label: selectedDevice.carouselEnabled
                                ? state.tr(zh: '轮播开启', en: 'Carousel On', ja: 'スライド ON')
                                : state.tr(zh: '轮播关闭', en: 'Carousel Off', ja: 'スライド OFF'),
                            icon: Icons.slideshow_rounded,
                            foreground: const Color(0xFF6B705C),
                            background: const Color(0xFF6B705C).withValues(alpha: 0.12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: usage / selectedDevice.capacity,
                        minHeight: 10,
                        borderRadius: BorderRadius.circular(999),
                        backgroundColor: Colors.black.withValues(alpha: 0.06),
                        color: theme.colorScheme.secondary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        state.tr(
                          zh: '设备满载时，会引导用户前往“我的相册”清理照片或联系设备所有者。',
                          en: 'If storage is full, users are directed to My Album or the device owner.',
                          ja: '容量がいっぱいの場合、マイアルバムまたはオーナー連絡へ案内します。',
                        ),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _SectionHeader(
                  title: state.tr(
                    zh: '最近投屏',
                    en: 'Recent Casts',
                    ja: '最近の投映',
                  ),
                  subtitle: state.tr(
                    zh: '同步展示成功与失败记录。',
                    en: 'Shows both success and failure records.',
                    ja: '成功と失敗の履歴をまとめて表示します。',
                  ),
                ),
                const SizedBox(height: 12),
                ...state.castRecords.take(3).map(
                  (record) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _RecordCard(
                      state: state,
                      record: record,
                      compact: true,
                      onRecast: () async {
                        final deviceId = await _pickDeviceId(context);
                        if (!context.mounted || deviceId == null) {
                          return;
                        }
                        final result = state.recastRecord(record.id, deviceId);
                        _showFeedback(context, result.message);
                      },
                      onDelete: () => state.deleteCastRecord(record.id),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _startCameraCast(BuildContext context) async {
    final draft = state.createCameraDraft();
    await _showCastPreview(context, draft);
  }

  Future<void> _startAlbumCast(BuildContext context) async {
    final draft = await showModalBottomSheet<DraftPhoto>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DraftPickerSheet(state: state),
    );
    if (!context.mounted || draft == null) {
      return;
    }
    await _showCastPreview(context, draft);
  }

  Future<void> _showCastPreview(BuildContext context, DraftPhoto draft) async {
    final deviceId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CastPreviewSheet(
        state: state,
        draft: draft,
      ),
    );
    if (!context.mounted || deviceId == null) {
      return;
    }
    final result = state.castDraft(draft: draft, deviceId: deviceId);
    _showFeedback(context, result.message);
    if (result.deviceFull) {
      onOpenMine();
    }
  }

  Future<void> _showPermissionPanel(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _BottomSheetFrame(
          title: state.tr(
            zh: '用户权限',
            en: 'Permissions',
            ja: 'ユーザー権限',
          ),
          child: Column(
            children: PermissionKind.values.map((permission) {
              return SwitchListTile.adaptive(
                value: state.permissions[permission]!,
                contentPadding: EdgeInsets.zero,
                title: Text(state.permissionLabel(permission)),
                subtitle: Text(
                  permission == PermissionKind.location
                      ? state.tr(
                          zh: '蓝牙搜索依赖位置权限。',
                          en: 'Location is required for Bluetooth discovery.',
                          ja: 'Bluetooth 探索には位置情報が必要です。',
                        )
                      : permission == PermissionKind.bluetooth
                          ? state.tr(
                              zh: '用于搜索并连接相框设备。',
                              en: 'Required to discover and connect frames.',
                              ja: '相框端末の探索と接続に使用します。',
                            )
                          : state.tr(
                              zh: '用于拍照上传。',
                              en: 'Required for taking photos.',
                              ja: '撮影アップロードに使用します。',
                            ),
                ),
                onChanged: (value) => state.setPermission(permission, value),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Future<void> _showDevicePicker(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _BottomSheetFrame(
          title: state.tr(
            zh: '绑定设备',
            en: 'Bind Device',
            ja: '端末を接続',
          ),
          child: Column(
            children: state.devices.map((device) {
              final usage = state.deviceUsage(device.id);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: () {
                    state.connectDevice(device.id);
                    Navigator.of(context).pop();
                  },
                  borderRadius: BorderRadius.circular(24),
                  child: Ink(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: device.id == state.selectedDevice.id
                          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.10)
                          : Colors.white.withValues(alpha: 0.72),
                    ),
                    child: Row(
                      children: [
                        _DeviceIllustration(
                          color: device.id == state.selectedDevice.id
                              ? Theme.of(context).colorScheme.primary
                              : const Color(0xFF6B705C),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(device.name, style: Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 4),
                              Text(
                                '${device.kind} · $usage/${device.capacity}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        if (device.connected)
                          const Icon(Icons.check_circle_rounded, color: Color(0xFF2A9D8F)),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Future<void> _showFlowGuide(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final steps = [
          state.tr(
            zh: '选择照片来源',
            en: 'Choose image source',
            ja: '画像の取得方法を選択',
          ),
          state.tr(
            zh: '选择设备并检查容量',
            en: 'Select device and inspect capacity',
            ja: '端末を選び容量を確認',
          ),
          state.tr(
            zh: '预览处理后尺寸',
            en: 'Preview processed size',
            ja: '処理後サイズを確認',
          ),
          state.tr(
            zh: '确认投屏并写入记录',
            en: 'Confirm cast and save record',
            ja: '投映を確定し履歴へ保存',
          ),
        ];
        return _BottomSheetFrame(
          title: state.tr(
            zh: '投屏流程',
            en: 'Casting Flow',
            ja: '投映フロー',
          ),
          child: Column(
            children: [
              for (var index = 0; index < steps.length; index++)
                Padding(
                  padding: EdgeInsets.only(bottom: index == steps.length - 1 ? 0 : 14),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(steps[index])),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _pickDeviceId(BuildContext context) async {
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            state.tr(
              zh: '选择设备',
              en: 'Choose Device',
              ja: '端末選択',
            ),
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: state.devices.map((device) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.desktop_windows_outlined),
                  title: Text(device.name),
                  subtitle: Text(device.kind),
                  onTap: () => Navigator.of(context).pop(device.id),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  void _showFeedback(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _MinePage extends StatelessWidget {
  const _MinePage({required this.state});

  final PhotoFrameState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = state.currentUser;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          sliver: SliverList(
            delegate: SliverChildListDelegate(
              [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(32),
                    color: Colors.white.withValues(alpha: 0.76),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 24,
                        offset: const Offset(0, 14),
                        color: Colors.black.withValues(alpha: 0.08),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: user.avatarColor,
                            child: Text(
                              user.nickname.isNotEmpty
                                  ? user.nickname.substring(0, 1).toUpperCase()
                                  : 'F',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 22,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.nickname,
                                  key: const Key('mine-page-title'),
                                  style: theme.textTheme.headlineSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  state.isLoggedIn
                                      ? user.email
                                      : state.tr(
                                          zh: '未登录',
                                          en: 'Signed out',
                                          ja: '未ログイン',
                                        ),
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                          FilledButton.tonal(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => _AuthPage(state: state),
                                ),
                              );
                            },
                            child: Text(
                              state.tr(
                                zh: '登录注册',
                                en: 'Auth',
                                ja: '認証',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(user.signature, style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _StatTag(
                            label: '${state.totalPhotoCount}',
                            icon: Icons.photo_library_outlined,
                            foreground: theme.colorScheme.primary,
                            background: theme.colorScheme.primary.withValues(alpha: 0.10),
                          ),
                          _StatTag(
                            label: '${state.devices.length}',
                            icon: Icons.devices_outlined,
                            foreground: const Color(0xFFD97757),
                            background: const Color(0xFFD97757).withValues(alpha: 0.12),
                          ),
                          _StatTag(
                            label: '${state.successCount}/${state.failureCount}',
                            icon: Icons.receipt_long_outlined,
                            foreground: const Color(0xFF6B705C),
                            background: const Color(0xFF6B705C).withValues(alpha: 0.12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _SectionHeader(
                  title: state.tr(
                    zh: '账户与资料',
                    en: 'Account',
                    ja: 'アカウント',
                  ),
                  subtitle: state.tr(
                    zh: '邮箱验证码登录、个人信息和头像管理。',
                    en: 'Email verification, profile and avatar management.',
                    ja: 'メール認証、プロフィール、アバター管理。',
                  ),
                ),
                const SizedBox(height: 12),
                _Panel(
                  child: Column(
                    children: [
                      _MenuTile(
                        icon: Icons.alternate_email_rounded,
                        title: state.tr(
                          zh: '登录注册 - app',
                          en: 'Email Login',
                          ja: 'メールログイン',
                        ),
                        subtitle: state.tr(
                          zh: '邮箱验证码注册 / 登录',
                          en: 'Register or sign in with email code',
                          ja: 'メール認証コードで登録 / ログイン',
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => _AuthPage(state: state),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 24),
                      _MenuTile(
                        icon: Icons.badge_outlined,
                        title: state.tr(
                          zh: '个人信息',
                          en: 'Profile',
                          ja: 'プロフィール',
                        ),
                        subtitle: state.tr(
                          zh: '昵称、头像、ID、邮箱修改',
                          en: 'Nickname, avatar, ID and email update',
                          ja: 'ニックネーム、アバター、ID、メール変更',
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => _ProfilePage(state: state),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _SectionHeader(
                  title: state.tr(
                    zh: '资产与设备',
                    en: 'Assets & Devices',
                    ja: '資産と端末',
                  ),
                  subtitle: state.tr(
                    zh: '我的相册、设备管理与投屏记录。',
                    en: 'My Album, device management and cast records.',
                    ja: 'マイアルバム、端末管理、投映履歴。',
                  ),
                ),
                const SizedBox(height: 12),
                _Panel(
                  child: Column(
                    children: [
                      _MenuTile(
                        icon: Icons.photo_library_outlined,
                        title: state.tr(
                          zh: '我的相册',
                          en: 'My Album',
                          ja: 'マイアルバム',
                        ),
                        subtitle: state.tr(
                          zh: '只显示成功上传至设备的照片数据',
                          en: 'Only shows photos successfully uploaded to devices',
                          ja: '端末へのアップロード成功分のみ表示',
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => _AlbumPage(state: state),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 24),
                      _MenuTile(
                        icon: Icons.devices_outlined,
                        title: state.tr(
                          zh: '我的设备',
                          en: 'My Devices',
                          ja: 'マイデバイス',
                        ),
                        subtitle: state.tr(
                          zh: '设备连接、电量、SN 码、权限、清空与轮播',
                          en: 'Connection, battery, SN, role, clear and carousel',
                          ja: '接続、電池、SN、権限、全削除、スライド設定',
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => _DevicesPage(state: state),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 24),
                      _MenuTile(
                        icon: Icons.history_toggle_off_rounded,
                        title: state.tr(
                          zh: '投屏管理',
                          en: 'Cast Records',
                          ja: '投映管理',
                        ),
                        subtitle: state.tr(
                          zh: '成功 / 失败记录，支持再次投屏和删除',
                          en: 'Success / failure records with recast and delete',
                          ja: '成功 / 失敗履歴の再投映と削除',
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => _CastManagementPage(state: state),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _SectionHeader(
                  title: state.tr(
                    zh: '帮助与设置',
                    en: 'Support & Settings',
                    ja: 'サポートと設定',
                  ),
                  subtitle: state.tr(
                    zh: '帮助文档、语言、隐私政策和账号退出。',
                    en: 'Guides, language, privacy policy and sign-out.',
                    ja: 'ガイド、言語、プライバシー、ログアウト。',
                  ),
                ),
                const SizedBox(height: 12),
                _Panel(
                  child: Column(
                    children: [
                      _MenuTile(
                        icon: Icons.menu_book_outlined,
                        title: state.tr(
                          zh: '操作指南',
                          en: 'Guides',
                          ja: '操作ガイド',
                        ),
                        subtitle: state.tr(
                          zh: '按设备类型查看帮助文档',
                          en: 'Browse help documents by device type',
                          ja: '端末タイプ別のヘルプを表示',
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => _GuidePage(state: state),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 24),
                      _MenuTile(
                        icon: Icons.settings_outlined,
                        title: state.tr(
                          zh: '设置',
                          en: 'Settings',
                          ja: '設定',
                        ),
                        subtitle: state.tr(
                          zh: '关于我们、联系方式、隐私政策、用户协议、语种设置',
                          en: 'About, contact, privacy policy, agreement and language',
                          ja: '会社情報、連絡先、プライバシー、規約、言語設定',
                        ),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => _SettingsPage(state: state),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AuthPage extends StatefulWidget {
  const _AuthPage({required this.state});

  final PhotoFrameState state;

  @override
  State<_AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<_AuthPage> {
  late final TextEditingController _emailController;
  final TextEditingController _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.state.currentUser.email);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return _SubPageScaffold(
      title: state.tr(
        zh: '登录注册',
        en: 'Email Login',
        ja: 'メールログイン',
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.tr(
                    zh: 'APP 端邮箱验证码登录',
                    en: 'App Email Verification Login',
                    ja: 'アプリのメール認証ログイン',
                  ),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  state.tr(
                    zh: '用于替代表格中的小程序授权登录流程，适配 iOS / Android / 鸿蒙 app。',
                    en: 'Replaces mini-program auth with email code login for iOS / Android / HarmonyOS apps.',
                    ja: 'ミニプログラム認証の代わりに、iOS / Android / HarmonyOS 向けのメール認証を提供します。',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: state.tr(
                      zh: '邮箱',
                      en: 'Email',
                      ja: 'メール',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: state.tr(
                            zh: '验证码',
                            en: 'Code',
                            ja: '認証コード',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonal(
                      onPressed: () {
                        final feedback = state.sendEmailCode(_emailController.text);
                        _showFeedback(context, feedback.message);
                      },
                      child: Text(
                        state.tr(
                          zh: '发送验证码',
                          en: 'Send Code',
                          ja: '送信',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () {
                    final feedback = state.loginWithEmail(
                      _emailController.text,
                      _codeController.text,
                    );
                    _showFeedback(context, feedback.message);
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: Text(
                    state.tr(
                      zh: '注册 / 登录',
                      en: 'Register / Login',
                      ja: '登録 / ログイン',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFeedback(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ProfilePage extends StatefulWidget {
  const _ProfilePage({required this.state});

  final PhotoFrameState state;

  @override
  State<_ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<_ProfilePage> {
  static const _avatarColors = <Color>[
    Color(0xFFBC6C25),
    Color(0xFF3D5A80),
    Color(0xFF588157),
    Color(0xFFD97757),
    Color(0xFF6D597A),
  ];

  late final TextEditingController _nicknameController;
  late final TextEditingController _emailController;
  late final TextEditingController _signatureController;
  late Color _avatarColor;

  @override
  void initState() {
    super.initState();
    final user = widget.state.currentUser;
    _nicknameController = TextEditingController(text: user.nickname);
    _emailController = TextEditingController(text: user.email);
    _signatureController = TextEditingController(text: user.signature);
    _avatarColor = user.avatarColor;
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _emailController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return _SubPageScaffold(
      title: state.tr(
        zh: '个人信息',
        en: 'Profile',
        ja: 'プロフィール',
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: _avatarColor,
                      child: Text(
                        _nicknameController.text.isNotEmpty
                            ? _nicknameController.text.substring(0, 1).toUpperCase()
                            : 'F',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.tr(
                              zh: '用户 ID',
                              en: 'User ID',
                              ja: 'ユーザー ID',
                            ),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            state.currentUser.id,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _nicknameController,
                  decoration: InputDecoration(
                    labelText: state.tr(
                      zh: '昵称',
                      en: 'Nickname',
                      ja: 'ニックネーム',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: state.tr(
                      zh: '绑定邮箱',
                      en: 'Bound Email',
                      ja: '連携メール',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _signatureController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: state.tr(
                      zh: '个性签名',
                      en: 'Signature',
                      ja: 'シグネチャ',
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  state.tr(
                    zh: '头像样式',
                    en: 'Avatar Style',
                    ja: 'アバタースタイル',
                  ),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _avatarColors.map((color) {
                    final selected = color == _avatarColor;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _avatarColor = color;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color,
                          border: Border.all(
                            color: selected ? Colors.black : Colors.white,
                            width: selected ? 3 : 1.5,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () {
                    final feedback = state.updateProfile(
                      nickname: _nicknameController.text,
                      email: _emailController.text,
                      signature: _signatureController.text,
                      avatarColor: _avatarColor,
                    );
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(content: Text(feedback.message)));
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: Text(
                    state.tr(
                      zh: '保存信息',
                      en: 'Save',
                      ja: '保存',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumPage extends StatefulWidget {
  const _AlbumPage({required this.state});

  final PhotoFrameState state;

  @override
  State<_AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<_AlbumPage> {
  final Set<String> _selectedIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final photos = state.myAlbum;

    return _SubPageScaffold(
      title: state.tr(
        zh: '我的相册',
        en: 'My Album',
        ja: 'マイアルバム',
      ),
      actions: [
        if (_selectedIds.length == 1)
          IconButton(
            icon: const Icon(Icons.cast_connected_outlined),
            onPressed: () => _recastSelected(context),
          ),
        if (_selectedIds.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              final feedback = state.deleteAlbumPhotos(_selectedIds);
              setState(_selectedIds.clear);
              _showFeedback(context, feedback.message);
            },
          ),
      ],
      child: photos.isEmpty
          ? _EmptyState(
              title: state.tr(
                zh: '还没有可显示的照片',
                en: 'No photos to show yet',
                ja: '表示できる写真はまだありません',
              ),
              message: state.tr(
                zh: '这里只保留成功投屏到设备的数据。',
                en: 'Only photos successfully written to devices appear here.',
                ja: 'ここには端末への書き込み成功分のみ表示されます。',
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _Panel(
                  child: Text(
                    state.tr(
                      zh: '支持多选删除；当前实现按“设备物理存储”为准，设备一键清空后照片不会继续留在我的相册。',
                      en: 'Multi-select delete is supported. This build treats device storage as the source of truth, so cleared device photos disappear from My Album.',
                      ja: '複数削除に対応しています。この実装では端末ストレージを正とし、一括クリア後はマイアルバムからも消えます。',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ...photos.map((photo) {
                  final selected = _selectedIds.contains(photo.id);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _Panel(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PhotoArtwork(
                            color: photo.color,
                            source: photo.source,
                            width: 88,
                            height: 108,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        photo.title,
                                        style: Theme.of(context).textTheme.titleLarge,
                                      ),
                                    ),
                                    Checkbox(
                                      value: selected,
                                      onChanged: (_) {
                                        setState(() {
                                          if (selected) {
                                            _selectedIds.remove(photo.id);
                                          } else {
                                            _selectedIds.add(photo.id);
                                          }
                                        });
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${state.deviceName(photo.deviceId)} · ${state.formatDateTime(photo.uploadedAt)}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(photo.note),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    FilledButton.tonal(
                                      onPressed: () => _recastSingle(context, photo.id),
                                      child: Text(
                                        state.tr(
                                          zh: '投屏',
                                          en: 'Cast',
                                          ja: '投映',
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        final feedback = state.deleteAlbumPhotos({photo.id});
                                        _showFeedback(context, feedback.message);
                                      },
                                      child: Text(
                                        state.tr(
                                          zh: '删除',
                                          en: 'Delete',
                                          ja: '削除',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }

  Future<void> _recastSelected(BuildContext context) async {
    final photoId = _selectedIds.first;
    await _recastSingle(context, photoId);
  }

  Future<void> _recastSingle(BuildContext context, String photoId) async {
    final deviceId = await _pickDevice(context, widget.state);
    if (!context.mounted || deviceId == null) {
      return;
    }
    final result = widget.state.recastAlbumPhoto(photoId, deviceId);
    _showFeedback(context, result.message);
  }

  Future<String?> _pickDevice(BuildContext context, PhotoFrameState state) {
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            state.tr(
              zh: '选择投屏设备',
              en: 'Choose Target Device',
              ja: '投映先の端末を選択',
            ),
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: state.devices.map((device) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(device.name),
                  subtitle: Text('${device.kind} · ${state.deviceUsage(device.id)}/${device.capacity}'),
                  onTap: () => Navigator.of(context).pop(device.id),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  void _showFeedback(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _DevicesPage extends StatelessWidget {
  const _DevicesPage({required this.state});

  final PhotoFrameState state;

  @override
  Widget build(BuildContext context) {
    return _SubPageScaffold(
      title: state.tr(
        zh: '我的设备',
        en: 'My Devices',
        ja: 'マイデバイス',
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _Panel(
            child: Text(
              state.tr(
                zh: '支持蓝牙搜索、连接切换、名称编辑、SN 码录入、所有者 / 使用者权限切换、设备一键清空和轮播模式控制。',
                en: 'Supports Bluetooth scan, connection switching, rename, SN code entry, owner/user role change, one-tap clear and carousel control.',
                ja: 'Bluetooth 検索、接続切替、名称編集、SN 入力、オーナー / 利用者切替、一括クリア、スライド制御に対応しています。',
              ),
            ),
          ),
          const SizedBox(height: 12),
          ...state.devices.map((device) {
            final usage = state.deviceUsage(device.id);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _DeviceIllustration(
                          color: device.connected
                              ? Theme.of(context).colorScheme.primary
                              : const Color(0xFF6B705C),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(device.name, style: Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 4),
                              Text('${device.kind} · ${device.serialNumber}'),
                            ],
                          ),
                        ),
                        _StatusPill(
                          label: device.connected
                              ? state.tr(
                                  zh: '已连接',
                                  en: 'Connected',
                                  ja: '接続中',
                                )
                              : state.tr(
                                  zh: '未连接',
                                  en: 'Idle',
                                  ja: '未接続',
                                ),
                          active: device.connected,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _StatTag(
                          label: '${device.batteryLevel}%',
                          icon: Icons.battery_4_bar_rounded,
                          foreground: Theme.of(context).colorScheme.primary,
                          background: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                        ),
                        _StatTag(
                          label: '$usage/${device.capacity}',
                          icon: Icons.photo_library_outlined,
                          foreground: const Color(0xFFD97757),
                          background: const Color(0xFFD97757).withValues(alpha: 0.12),
                        ),
                        _StatTag(
                          label: state.roleLabel(device.role),
                          icon: Icons.lock_outline_rounded,
                          foreground: const Color(0xFF6B705C),
                          background: const Color(0xFF6B705C).withValues(alpha: 0.12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.tonal(
                          onPressed: () => state.connectDevice(device.id),
                          child: Text(
                            device.connected
                                ? state.tr(
                                    zh: '当前设备',
                                    en: 'Current',
                                    ja: '現在の端末',
                                  )
                                : state.tr(
                                    zh: '连接设备',
                                    en: 'Connect',
                                    ja: '接続',
                                  ),
                          ),
                        ),
                        FilledButton.tonal(
                          onPressed: () async {
                            final nextName = await _promptText(
                              context,
                              title: state.tr(
                                zh: '修改设备名称',
                                en: 'Rename Device',
                                ja: '端末名を変更',
                              ),
                              initialValue: device.name,
                            );
                            if (nextName != null) {
                              state.renameDevice(device.id, nextName);
                            }
                          },
                          child: Text(
                            state.tr(
                              zh: '编辑名称',
                              en: 'Rename',
                              ja: '名称編集',
                            ),
                          ),
                        ),
                        FilledButton.tonal(
                          onPressed: () async {
                            final nextSn = await _promptText(
                              context,
                              title: state.tr(
                                zh: '输入设备 SN 码',
                                en: 'Input SN Code',
                                ja: 'SN コード入力',
                              ),
                              initialValue: device.serialNumber,
                            );
                            if (nextSn != null) {
                              state.updateDeviceSerial(device.id, nextSn);
                            }
                          },
                          child: Text(
                            state.tr(
                              zh: 'SN 码',
                              en: 'SN Code',
                              ja: 'SN コード',
                            ),
                          ),
                        ),
                        FilledButton.tonal(
                          onPressed: () {
                            state.setDeviceRole(
                              device.id,
                              device.role == DeviceRole.owner ? DeviceRole.user : DeviceRole.owner,
                            );
                          },
                          child: Text(
                            device.role == DeviceRole.owner
                                ? state.tr(
                                    zh: '切换为使用者',
                                    en: 'Set as User',
                                    ja: '利用者に変更',
                                  )
                                : state.tr(
                                    zh: '设为所有者',
                                    en: 'Set as Owner',
                                    ja: 'オーナーに設定',
                                  ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      value: device.carouselEnabled,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        state.tr(
                          zh: '轮播模式',
                          en: 'Carousel Mode',
                          ja: 'スライドモード',
                        ),
                      ),
                      subtitle: Text(
                        state.tr(
                          zh: '开启后按启用时间起算 24 小时轮播下一张。',
                          en: 'After enabling, the next photo is shown every 24 hours.',
                          ja: '有効化後、24 時間ごとに次の写真へ切り替わります。',
                        ),
                      ),
                      onChanged: (value) => state.toggleCarousel(device.id, value),
                    ),
                    const SizedBox(height: 6),
                    TextButton.icon(
                      onPressed: () {
                        final feedback = state.clearDeviceMemory(device.id);
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(content: Text(feedback.message)));
                      },
                      icon: const Icon(Icons.cleaning_services_outlined),
                      label: Text(
                        state.tr(
                          zh: '一键清空',
                          en: 'One-Tap Clear',
                          ja: '一括クリア',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _CastManagementPage extends StatelessWidget {
  const _CastManagementPage({required this.state});

  final PhotoFrameState state;

  @override
  Widget build(BuildContext context) {
    return _SubPageScaffold(
      title: state.tr(
        zh: '投屏管理',
        en: 'Cast Management',
        ja: '投映管理',
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: state.castRecords.map((record) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _RecordCard(
              state: state,
              record: record,
              onRecast: () async {
                final deviceId = await _pickDevice(context, state);
                if (!context.mounted || deviceId == null) {
                  return;
                }
                final result = state.recastRecord(record.id, deviceId);
                _showFeedback(context, result.message);
              },
              onDelete: () => state.deleteCastRecord(record.id),
            ),
          );
        }).toList(),
      ),
    );
  }

  Future<String?> _pickDevice(BuildContext context, PhotoFrameState state) {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          state.tr(
            zh: '选择设备',
            en: 'Choose Device',
            ja: '端末選択',
          ),
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: state.devices.map((device) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(device.name),
                subtitle: Text(device.kind),
                onTap: () => Navigator.of(context).pop(device.id),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showFeedback(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _GuidePage extends StatelessWidget {
  const _GuidePage({required this.state});

  final PhotoFrameState state;

  @override
  Widget build(BuildContext context) {
    final articles = state.buildGuideArticles();
    return _SubPageScaffold(
      title: state.tr(
        zh: '操作指南',
        en: 'Guides',
        ja: '操作ガイド',
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: articles.map((article) {
          final summary = switch (state.language) {
            AppLanguage.zh => article.summaryZh,
            AppLanguage.en => article.summaryEn,
            AppLanguage.ja => article.summaryJa,
          };
          final title = switch (state.language) {
            AppLanguage.zh => article.titleZh,
            AppLanguage.en => article.titleEn,
            AppLanguage.ja => article.titleJa,
          };
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _Panel(
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(title),
                subtitle: Text(article.category),
                children: summary
                    .map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Icon(Icons.circle, size: 8),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(line)),
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.state});

  final PhotoFrameState state;

  @override
  Widget build(BuildContext context) {
    return _SubPageScaffold(
      title: state.tr(
        zh: '设置',
        en: 'Settings',
        ja: '設定',
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _Panel(
            child: Column(
              children: [
                _MenuTile(
                  icon: Icons.info_outline_rounded,
                  title: state.tr(
                    zh: '关于我们',
                    en: 'About',
                    ja: '私たちについて',
                  ),
                  subtitle: state.tr(
                    zh: '数字相框多端投屏客户端',
                    en: 'Multi-platform client for digital frame casting',
                    ja: 'デジタルフォトフレーム向けマルチプラットフォームクライアント',
                  ),
                  onTap: () => _showInfoDialog(
                    context,
                    title: state.tr(zh: '关于我们', en: 'About', ja: '私たちについて'),
                    content: state.tr(
                      zh: '本工程面向 iOS、Android、鸿蒙三端统一维护投屏业务流程，包含设备管理、相册、记录与帮助模块。',
                      en: 'This project unifies casting, device management, album, record and guide flows for iOS, Android and HarmonyOS.',
                      ja: 'このプロジェクトは iOS、Android、HarmonyOS 向けに投映、端末管理、アルバム、履歴、ガイド機能を統合しています。',
                    ),
                  ),
                ),
                const Divider(height: 24),
                _MenuTile(
                  icon: Icons.support_agent_rounded,
                  title: state.tr(
                    zh: '联系方式',
                    en: 'Contact',
                    ja: '連絡先',
                  ),
                  subtitle: 'support@frameflow.app',
                  onTap: () => _showInfoDialog(
                    context,
                    title: state.tr(zh: '联系方式', en: 'Contact', ja: '連絡先'),
                    content: 'support@frameflow.app\n+86 400-001-2400',
                  ),
                ),
                const Divider(height: 24),
                _MenuTile(
                  icon: Icons.privacy_tip_outlined,
                  title: state.tr(
                    zh: '隐私政策',
                    en: 'Privacy Policy',
                    ja: 'プライバシーポリシー',
                  ),
                  subtitle: state.tr(
                    zh: '说明权限使用范围',
                    en: 'How permissions are used',
                    ja: '権限利用範囲の説明',
                  ),
                  onTap: () => _showInfoDialog(
                    context,
                    title: state.tr(zh: '隐私政策', en: 'Privacy Policy', ja: 'プライバシーポリシー'),
                    content: state.tr(
                      zh: '位置权限用于蓝牙搜索，蓝牙权限用于连接设备，相机权限用于拍照上传。当前工程未接入云端存储。',
                      en: 'Location is used for Bluetooth discovery, Bluetooth for device connection, and camera for capture upload. This build does not connect to cloud storage.',
                      ja: '位置情報は Bluetooth 探索、Bluetooth は端末接続、カメラは撮影アップロードに使用します。現在の実装はクラウド保存を利用しません。',
                    ),
                  ),
                ),
                const Divider(height: 24),
                _MenuTile(
                  icon: Icons.description_outlined,
                  title: state.tr(
                    zh: '用户协议',
                    en: 'User Agreement',
                    ja: '利用規約',
                  ),
                  subtitle: state.tr(
                    zh: '设备与账号使用规范',
                    en: 'Device and account rules',
                    ja: '端末とアカウントの利用規約',
                  ),
                  onTap: () => _showInfoDialog(
                    context,
                    title: state.tr(zh: '用户协议', en: 'User Agreement', ja: '利用規約'),
                    content: state.tr(
                      zh: '所有者可配置设备权限、轮播模式和一键清空；使用者仅管理自己上传的照片。',
                      en: 'Owners can configure permissions, carousel mode and one-tap clear. Users can manage only the photos they uploaded.',
                      ja: 'オーナーは権限、スライドモード、一括クリアを設定できます。利用者は自分がアップロードした写真のみ管理できます。',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.tr(
                    zh: '语种设置',
                    en: 'Language',
                    ja: '言語設定',
                  ),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: AppLanguage.values.map((language) {
                    final selected = state.language == language;
                    return ChoiceChip(
                      selected: selected,
                      label: Text(state.languageLabel(language)),
                      onSelected: (_) => state.switchLanguage(language),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Panel(
            child: Column(
              children: [
                _MenuTile(
                  icon: Icons.logout_rounded,
                  title: state.tr(
                    zh: '退出登录',
                    en: 'Log Out',
                    ja: 'ログアウト',
                  ),
                  subtitle: state.tr(
                    zh: '保留设备与记录，清空邮箱登录态',
                    en: 'Keep device data but clear email session',
                    ja: '端末と履歴を保持したままメールセッションを解除',
                  ),
                  onTap: () {
                    state.logout();
                    _showMessage(
                      context,
                      state.tr(
                        zh: '已退出登录。',
                        en: 'Logged out.',
                        ja: 'ログアウトしました。',
                      ),
                    );
                  },
                ),
                const Divider(height: 24),
                _MenuTile(
                  icon: Icons.person_remove_outlined,
                  title: state.tr(
                    zh: '用户注销',
                    en: 'Delete Account',
                    ja: 'アカウント削除',
                  ),
                  subtitle: state.tr(
                    zh: '移除我的相册与投屏记录',
                    en: 'Remove My Album and casting records',
                    ja: 'マイアルバムと投映履歴を削除',
                  ),
                  onTap: () {
                    state.deleteAccount();
                    _showMessage(
                      context,
                      state.tr(
                        zh: '账号已注销，当前进入访客状态。',
                        en: 'Account deleted. You are now in guest mode.',
                        ja: 'アカウントを削除し、ゲストモードに切り替えました。',
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(
    BuildContext context, {
    required String title,
    required String content,
  }) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
      ),
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SubPageScaffold extends StatelessWidget {
  const _SubPageScaffold({
    required this.title,
    required this.child,
    this.actions,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(title),
        actions: actions,
      ),
      body: Stack(
        children: [
          const _AtmosphereBackground(),
          child,
        ],
      ),
    );
  }
}

class _BottomSheetFrame extends StatelessWidget {
  const _BottomSheetFrame({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F2EA),
        borderRadius: BorderRadius.circular(28),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _DraftPickerSheet extends StatelessWidget {
  const _DraftPickerSheet({required this.state});

  final PhotoFrameState state;

  @override
  Widget build(BuildContext context) {
    return _BottomSheetFrame(
      title: state.tr(
        zh: '选择相册图片',
        en: 'Choose an Album Photo',
        ja: 'アルバム画像を選択',
      ),
      child: Column(
        children: state.draftLibrary.map((draft) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              onTap: () => Navigator.of(context).pop(draft),
              borderRadius: BorderRadius.circular(24),
              child: Ink(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: Colors.white.withValues(alpha: 0.78),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PhotoArtwork(
                      color: draft.color,
                      source: draft.source,
                      width: 82,
                      height: 100,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(draft.title, style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 6),
                          Text(
                            '${draft.width.toInt()} × ${draft.height.toInt()}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(draft.note),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _CastPreviewSheet extends StatefulWidget {
  const _CastPreviewSheet({
    required this.state,
    required this.draft,
  });

  final PhotoFrameState state;
  final DraftPhoto draft;

  @override
  State<_CastPreviewSheet> createState() => _CastPreviewSheetState();
}

class _CastPreviewSheetState extends State<_CastPreviewSheet> {
  late String _deviceId;

  @override
  void initState() {
    super.initState();
    _deviceId = widget.state.selectedDevice.id;
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.state.deviceById(_deviceId);
    final usage = widget.state.deviceUsage(device.id);

    return _BottomSheetFrame(
      title: widget.state.tr(
        zh: '预览图确认',
        en: 'Preview Before Cast',
        ja: '投映前プレビュー',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: _PhotoArtwork(
              color: widget.draft.color,
              source: widget.draft.source,
              width: 190,
              height: 230,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            widget.draft.title,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            widget.state.tr(
              zh: '预处理尺寸：${widget.draft.width.toInt()} × ${widget.draft.height.toInt()}',
              en: 'Processed size: ${widget.draft.width.toInt()} × ${widget.draft.height.toInt()}',
              ja: '処理後サイズ: ${widget.draft.width.toInt()} × ${widget.draft.height.toInt()}',
            ),
          ),
          const SizedBox(height: 6),
          Text(widget.draft.note),
          const SizedBox(height: 18),
          Text(
            widget.state.tr(
              zh: '目标设备',
              en: 'Target Device',
              ja: '投映先端末',
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: widget.state.devices.map((deviceItem) {
              final selected = _deviceId == deviceItem.id;
              return ChoiceChip(
                selected: selected,
                label: Text(deviceItem.name),
                onSelected: (_) {
                  setState(() {
                    _deviceId = deviceItem.id;
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          Text(
            '${device.name} · $usage/${device.capacity}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: usage / device.capacity,
            minHeight: 10,
            borderRadius: BorderRadius.circular(999),
            backgroundColor: Colors.black.withValues(alpha: 0.06),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_deviceId),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(
              widget.state.tr(
                zh: '确认投屏',
                en: 'Confirm Cast',
                ja: '投映を確定',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        color: Colors.white.withValues(alpha: 0.76),
        border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
        boxShadow: [
          BoxShadow(
            blurRadius: 22,
            offset: const Offset(0, 12),
            color: Colors.black.withValues(alpha: 0.06),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: 0.18),
              accent.withValues(alpha: 0.06),
            ],
          ),
          border: Border.all(color: accent.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white.withValues(alpha: 0.10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.76),
                ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                ),
          ),
        ],
      ),
    );
  }
}

class _StatTag extends StatelessWidget {
  const _StatTag({
    required this.label,
    required this.icon,
    required this.foreground,
    required this.background,
  });

  final String label;
  final IconData icon;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: background,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.active,
  });

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF2A9D8F) : const Color(0xFF6C757D);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DeviceIllustration extends StatelessWidget {
  const _DeviceIllustration({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withValues(alpha: 0.95),
            color.withValues(alpha: 0.72),
          ],
        ),
      ),
      child: const Icon(
        Icons.desktop_windows_rounded,
        color: Colors.white,
      ),
    );
  }
}

class _PhotoArtwork extends StatelessWidget {
  const _PhotoArtwork({
    required this.color,
    required this.source,
    this.width = 76,
    this.height = 92,
  });

  final Color color;
  final ImageSourceType source;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.96),
            color.withValues(alpha: 0.56),
            const Color(0xFFF8F2EA),
          ],
        ),
      ),
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                source == ImageSourceType.camera
                    ? Icons.photo_camera_outlined
                    : Icons.collections_outlined,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                height: height * 0.32,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: Colors.white.withValues(alpha: 0.24),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
              ),
              child: Icon(icon, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.state,
    required this.record,
    required this.onRecast,
    required this.onDelete,
    this.compact = false,
  });

  final PhotoFrameState state;
  final CastRecord record;
  final VoidCallback onRecast;
  final VoidCallback onDelete;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PhotoArtwork(
            color: record.color,
            source: record.source,
            width: compact ? 68 : 80,
            height: compact ? 84 : 98,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        record.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    _StatusPill(
                      label: state.statusLabel(record.status),
                      active: record.status == CastStatus.success,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${state.deviceName(record.deviceId)} · ${state.formatDateTime(record.createdAt)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 6),
                Text(record.message),
                if (!compact) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.tonal(
                        onPressed: onRecast,
                        child: Text(
                          state.tr(
                            zh: '投屏',
                            en: 'Cast',
                            ja: '投映',
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: onDelete,
                        child: Text(
                          state.tr(
                            zh: '删除',
                            en: 'Delete',
                            ja: '削除',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: _Panel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inbox_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<String?> _promptText(
  BuildContext context, {
  required String title,
  required String initialValue,
}) async {
  final controller = TextEditingController(text: initialValue);
  final result = await showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
  controller.dispose();
  return result;
}
