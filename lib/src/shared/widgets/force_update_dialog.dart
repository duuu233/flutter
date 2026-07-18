import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_l10n.dart';
import 'app_dialog.dart';
import 'app_toast.dart';

/// 强制升级弹窗（登录成功后 `getLastVersion` 返回 `compulsory=1` 且 `isUpdate=1` 时弹出）。
///
/// 视觉沿用项目既有的确认弹窗语言（小程序 `.confirm-dialog`）：白卡 radius 14 +
/// 左侧橙色图标盒 + 标题/说明 + 底部胶囊按钮，只是**只有一个通栏「立即更新」**。
///
/// 与普通确认弹窗的关键差别——它是**关不掉**的：
/// - `barrierDismissible: false`：点遮罩无效；
/// - `PopScope(canPop: false)`：物理返回键 / 手势返回无效；
/// - 点「立即更新」只把用户送去应用商店，**弹窗不关**——用户从商店返回时若没真的
///   升级，仍然被挡在这里（升级完成后是新装的包，重进自然不再命中强制升级）。
///
/// 非强制升级（compulsory=2/3/4）不走这里：用户自己去「设置 → 更新BoltStar」手动更新。
class ForceUpdateDialog extends StatelessWidget {
  const ForceUpdateDialog({
    super.key,
    required this.latestVersion,
    required this.downloadUrl,
    required this.description,
  });

  final String latestVersion;
  final String downloadUrl;

  /// 后端 `upgradeTips`，为空时回退到通用文案。
  final String description;

  /// 弹出强制升级弹窗。用 rootNavigator 挂到根栈，保证盖住所有业务页面。
  static Future<void> show(
    BuildContext context, {
    required String latestVersion,
    required String downloadUrl,
    required String description,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      useRootNavigator: true,
      builder: (_) => ForceUpdateDialog(
        latestVersion: latestVersion,
        downloadUrl: downloadUrl,
        description: description,
      ),
    );
  }

  Future<void> _openStore(BuildContext context) async {
    final url = downloadUrl.trim();
    final uri = url.isEmpty ? null : Uri.tryParse(url);
    // scheme 白名单：downloadUrl 来自后端，若被篡改成 intent://、tel:// 等，
    // externalApplication 会直接拉起任意外部应用（同 update_boltstar_page.dart）。
    const allowedSchemes = {'https', 'market', 'itms-apps'};
    if (uri == null || !allowedSchemes.contains(uri.scheme)) {
      debugPrint('[ForceUpdate] 拒绝非白名单下载地址: $url');
      if (context.mounted) {
        AppToast.warn(context, AppL10n.of(context).setCheckUpdateFailed);
      }
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      // 没有应用商店的 ROM 上 market:// 会抛 PlatformException，不能冒泡崩掉 App。
      debugPrint('[ForceUpdate] 打开下载地址失败: $error');
      if (context.mounted) {
        AppToast.warn(context, AppL10n.of(context).setDownloadOpenFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final message = description.trim().isEmpty
        ? l10n.setForceUpdateMessage
        : description.trim();
    final version = latestVersion.trim();
    return PopScope(
      // 返回键 / 手势返回都关不掉：强制升级必须升级后才能继续用。
      canPop: false,
      child: AppDialog(
        icon: Icons.system_update_alt_rounded,
        title: l10n.setForceUpdateTitle,
        message: version.isEmpty
            ? message
            : '${l10n.setForceUpdateVersion(version)}\n$message',
        // 通栏「立即更新」：没有取消按钮，这是强制升级弹窗与普通确认弹窗的差别；
        // 点它只把用户送去商店，**不关弹窗**（见类文档）。
        showCancel: false,
        confirmLabel: l10n.setUpdateNow,
        onConfirm: () => _openStore(context),
      ),
    );
  }
}
