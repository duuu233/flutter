part of 'home_page.dart';

// =============================================================================
// 首页相关的底部弹层。均为展示型组件，操作通过回调上抛给 _HomePageState。
// =============================================================================

/// 「绑定设备-扫描不到怎么办?」帮助弹层。
///
/// 场景：在绑定流程（搜索中 / 未发现设备）点击「扫描不到怎么办?」后，覆盖在
/// [_BindDeviceView] 之上显示排查清单。[onClose] 关闭，[onRetry] 重新扫描。
class _ScanHelpSheet extends StatelessWidget {
  const _ScanHelpSheet({required this.onClose, required this.onRetry});

  final VoidCallback onClose;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onClose,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.42)),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Stack(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: Text(
                            AppL10n.of(context).homeScanHelpTitle,
                            textAlign: TextAlign.center,
                            style: _HomeTextStyles.sheetTitle,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 24,
                              height: 24,
                            ),
                            onPressed: onClose,
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Color(0xFF7E7E7E),
                              size: 25,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: 115,
                      height: 115,
                      child: Image.asset(
                        'assets/images/scan_help_art.png',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const _ScanHelpIconFallback();
                        },
                      ),
                    ),
                    const SizedBox(height: 26),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        AppL10n.of(context).homeScanHelpChecklistTitle,
                        style: _HomeTextStyles.helpTitle,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        AppL10n.of(context).homeScanHelpBody,
                        style: _HomeTextStyles.helpBody,
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: _GradientButton(
                        label: AppL10n.of(context).homeRescan,
                        onPressed: onRetry,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 通用提示弹层（标题 + 说明 + 单个主按钮）。
///
/// 复用于多个场景：未绑定时投屏的「暂未绑定设备 / 立即绑定」、设备未连接的
/// 「设备连接失败 / 重新连接」、以及「离线模式 / 我知道了」。
class _DeviceNoticeSheet extends StatelessWidget {
  const _DeviceNoticeSheet({
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.onPressed,
  });

  final String title;
  final String message;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 22,
                    height: 22,
                  ),
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFF7E7E7E),
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: _HomeTextStyles.sheetTitle,
              ),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: _HomeTextStyles.sheetBody,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: _GradientButton(
                  label: buttonLabel,
                  onPressed: onPressed,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「选择投屏方式」弹层（拍照 / 相册 + 取消）。
///
/// 场景：已绑定首页点击「选择投屏方式」标题时弹出。
class _CastMethodSheet extends StatelessWidget {
  const _CastMethodSheet({required this.onCamera, required this.onAlbum});

  final VoidCallback onCamera;
  final VoidCallback onAlbum;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppL10n.of(context).homeCastSheetTitle,
                style: _HomeTextStyles.sheetTitle,
              ),
              const SizedBox(height: 25),
              _CastSheetRow(
                title: AppL10n.of(context).homeCastCameraTitle,
                subtitle: AppL10n.of(context).homeCastCameraSheetSubtitle,
                artAsset: 'assets/images/home-media-mini01.png',
                arrowAsset: 'assets/images/home-camera-card-right-icon.png',
                onTap: onCamera,
              ),
              // 小程序 .media-option margin-bottom: 20rpx = 10。
              const SizedBox(height: 10),
              _CastSheetRow(
                title: AppL10n.of(context).homeCastAlbumTitle,
                subtitle: AppL10n.of(context).homeCastAlbumSheetSubtitle,
                artAsset: 'assets/images/home-media-mini02.png',
                arrowAsset: 'assets/images/home-album-card-right-icon.png',
                onTap: onAlbum,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: Material(
                  color: const Color(0xFFEDEDED),
                  borderRadius: BorderRadius.circular(28),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(28),
                    onTap: () => Navigator.maybePop(context),
                    child: Center(
                      child: Text(
                        AppL10n.of(context).cancel,
                        style: _HomeTextStyles.cancelButton,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
