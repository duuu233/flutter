part of 'home_page.dart';

/// 绑定设备流程视图（`_bindMode != none` 时替换主视图显示）。
///
/// 按 [mode] 呈现三种场景，外加一个覆盖弹层：
/// - `searching` →「绑定设备-搜索设备」：雷达动画 + 取消扫描。
/// - `notFound`  →「绑定设备-未搜索到设备」：失败雷达 + 重新扫描。
/// - `found`     →「绑定设备-已搜索到设备」：附近设备列表 + 立即绑定。
/// - [showScanHelp] 为 true 时，在以上之上盖一层「扫描不到怎么办?」帮助弹层。
///
/// 本组件只负责展示与把操作上抛；真正的扫描计时、选中、连接逻辑在
/// [_HomePageState]。布局同样用滚动 + IntrinsicHeight 适配不同屏高。
class _BindDeviceView extends StatelessWidget {
  const _BindDeviceView({
    required this.mode,
    required this.devices,
    required this.selectedIndex,
    required this.showScanHelp,
    required this.onBack,
    required this.onHelp,
    required this.onCloseHelp,
    required this.onRetry,
    required this.onCancel,
    required this.onSelectDevice,
    required this.onBind,
  });

  /// 当前绑定子场景（searching / notFound / found）。
  final _HomeBindMode mode;

  /// 已发现的附近设备列表（found 场景使用）。
  final List<DeviceItem> devices;

  /// 列表中当前选中项下标。
  final int selectedIndex;

  /// 是否叠加「扫描不到怎么办?」帮助弹层。
  final bool showScanHelp;

  final VoidCallback onBack;
  final VoidCallback onHelp;
  final VoidCallback onCloseHelp;
  final VoidCallback onRetry;
  final VoidCallback onCancel;
  final ValueChanged<int> onSelectDevice;
  final VoidCallback onBind;

  bool get _found => mode == _HomeBindMode.found;
  bool get _notFound => mode == _HomeBindMode.notFound;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 34,
                          child: Stack(
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  width: 34,
                                  height: 34,
                                  child: _CircleIconButton(
                                    icon: Icons.arrow_back_rounded,
                                    onTap: onBack,
                                  ),
                                ),
                              ),
                              Center(
                                child: Text(
                                  AppL10n.of(context).homeBindDevice,
                                  style: _HomeTextStyles.navTitle,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        Center(
                          child: SizedBox(
                            width: 250,
                            height: 250,
                            child: _BluetoothRadar(
                              failed: _notFound || showScanHelp,
                              success: _found,
                              dimmed: showScanHelp,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        ..._modeContent(context),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        if (showScanHelp)
          _ScanHelpSheet(onClose: onCloseHelp, onRetry: onRetry),
      ],
    );
  }

  /// 根据 [mode] 返回雷达下方的主体内容。
  List<Widget> _modeContent(BuildContext context) {
    final l10n = AppL10n.of(context);
    if (mode == _HomeBindMode.searching) {
      return _statusContent(
        context: context,
        title: l10n.homeBindSearchingTitle,
        subtitle: l10n.homeBindSearchingSubtitle,
        buttonLabel: l10n.homeBindCancelScan,
        onButton: onCancel,
      );
    }
    if (_found) {
      return _foundContent(context);
    }
    if (_notFound && !showScanHelp) {
      return _statusContent(
        context: context,
        title: l10n.homeBindNotFoundTitle,
        subtitle: l10n.homeBindNotFoundSubtitle,
        buttonLabel: l10n.homeRescan,
        onButton: onRetry,
      );
    }
    // notFound 且正显示帮助弹层时，主体让位给上层弹层。
    return const [Spacer()];
  }

  /// searching / notFound 共用：标题 + 副标题 +「扫描不到怎么办?」+ 主按钮。
  List<Widget> _statusContent({
    required BuildContext context,
    required String title,
    required String subtitle,
    required String buttonLabel,
    required VoidCallback onButton,
  }) {
    return [
      const SizedBox(height: 8),
      Text(
        title,
        textAlign: TextAlign.center,
        style: _HomeTextStyles.bindTitle,
      ),
      const SizedBox(height: 10),
      Text(
        subtitle,
        textAlign: TextAlign.center,
        style: _HomeTextStyles.bindSubtitle,
      ),
      const Spacer(),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onHelp,
        child: Text(
          AppL10n.of(context).homeScanHelpTitle,
          textAlign: TextAlign.center,
          style: _HomeTextStyles.orangeLink,
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 56,
        child: _GradientButton(label: buttonLabel, onPressed: onButton),
      ),
    ];
  }

  /// found 场景：附近设备列表 +「立即绑定」。
  List<Widget> _foundContent(BuildContext context) {
    return [
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: Text(
              AppL10n.of(context).homeNearbyDevices,
              style: _HomeTextStyles.sectionTitle,
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onRetry,
            child: Image.asset(
              'assets/images/refresh-icon.png',
              width: 28,
              height: 28,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.refresh_rounded,
                  color: Color(0xFFFF6A24),
                  size: 24,
                );
              },
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      for (var index = 0; index < devices.length; index++) ...[
        _FoundDeviceTile(
          device: devices[index],
          selected: index == selectedIndex,
          iconAsset: _deviceIconAsset(index),
          onTap: () => onSelectDevice(index),
        ),
        if (index != devices.length - 1) const SizedBox(height: 11),
      ],
      const Spacer(),
      SizedBox(
        height: 56,
        child: _GradientButton(
          label: AppL10n.of(context).homeBindNow,
          onPressed: onBind,
        ),
      ),
    ];
  }

  /// 附近设备图标按列表序取 `device-list-icon01~03.png`（与小程序一致）。
  String _deviceIconAsset(int index) {
    final n = (index % 3) + 1;
    return 'assets/images/device-list-icon0$n.png';
  }
}
