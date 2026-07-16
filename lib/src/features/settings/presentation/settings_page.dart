import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../network/api_exception.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../state.dart';
import 'package:BoltStar/src/shared/widgets/app_widgets.dart';
import 'package:BoltStar/src/shared/widgets/figma_common.dart';

/// 设置页面，对照微信小程序 `subpackages/settings/index` 精准还原。
///
/// 第一张玻璃卡仅含「语种设置」；第二张含「联系方式 / 隐私政策 / 用户协议」
/// （小程序中「更新BoltStar」入口被注释，故此处不展示）。底部「退出登录」胶囊按钮
/// 与「用户注销」文字链分别弹确认弹窗。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.state});

  final PhotoFrameState state;

  // 联系方式（与小程序 index.js 的 contact 一致）。
  static const String _contact = '99999@qq.com';

  /// 检查 App 更新：查最新版本 → 有更新则弹窗 → 「立即更新」用 url_launcher 打开下载地址
  /// （对齐小程序 app.js 里的 getLastVersion / getAndroidDownload TODO）。
  Future<void> _checkUpdate(BuildContext context) async {
    final l10n = AppL10n.of(context);
    AppToast.show(context, l10n.checkingUpdate);
    AppVersionInfo info;
    try {
      info = await state.checkAppVersion();
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      // ApiException 的 message 已本地化，直接展示；其他异常只给通用文案，详情进日志。
      debugPrint('[Settings] 检查更新失败: $error');
      AppToast.show(
        context,
        error is ApiException
            ? error.message
            : l10n.checkUpdateFailedGeneric,
      );
      return;
    }
    if (!context.mounted) {
      return;
    }
    if (!info.hasUpdate) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.checkUpdate),
          content: Text(l10n.alreadyLatest(info.currentVersion)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.gotIt),
            ),
          ],
        ),
      );
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.newVersionFound(info.latestVersion)),
        content: Text(
          info.description.isEmpty ? l10n.newVersionPrompt : info.description,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.updateLater),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.updateNow),
          ),
        ],
      ),
    );
    if (go != true) {
      return;
    }
    final url = info.downloadUrl.trim();
    if (url.isEmpty) {
      if (context.mounted) {
        AppToast.show(context, l10n.noDownloadUrl);
      }
      return;
    }
    final uri = Uri.tryParse(url);
    // scheme 白名单：downloadUrl 来自后端接口，若后端被篡改返回 intent://、tel://
    // 等任意 scheme，externalApplication 会直接拉起任意外部应用。只放行
    // https 与两端应用商店 scheme，其余静默拒绝并提示无下载地址。
    const allowedSchemes = {'https', 'market', 'itms-apps'};
    if (uri == null || !allowedSchemes.contains(uri.scheme)) {
      debugPrint('[Settings] 拒绝非白名单下载地址: $url');
      if (context.mounted) {
        AppToast.show(context, l10n.noDownloadUrl);
      }
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      // market:// 在没有应用商店的 ROM 上无处理者会抛 PlatformException
      //（ActivityNotFoundException），不能让它冒泡崩掉 App。
      debugPrint('[Settings] 打开下载地址失败: $error');
      if (context.mounted) {
        AppToast.show(context, l10n.openDownloadFailed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return FigmaScreen(
      title: l10n.settingsTitle,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 17),
          FigmaGlassCard(
            borderRadius: 11,
            child: _SettingsRow(
              iconAsset: 'assets/images/set-icon01.png',
              iconBg: const Color(0x14FF6421),
              title: l10n.languageSetting,
              value: l10n.currentLanguageLabel,
              onTap: () => Navigator.of(
                context,
              ).pushNamed<void>(AppRoutes.figmaLanguageSettings),
            ),
          ),
          const SizedBox(height: 14),
          FigmaGlassCard(
            borderRadius: 11,
            child: Column(
              children: [
                _SettingsRow(
                  iconAsset: 'assets/images/set-icon02.png',
                  iconBg: const Color(0x1A287DFF),
                  title: l10n.contactUs,
                  value: _contact,
                  trailing: _RowTrailing.copy,
                  onTap: () => _copyContact(context),
                ),
                const _SettingsDivider(),
                _SettingsRow(
                  iconAsset: 'assets/images/set-icon03.png',
                  iconBg: const Color(0x1A287DFF),
                  title: l10n.privacyPolicy,
                  onTap: () => Navigator.of(
                    context,
                  ).pushNamed<void>(AppRoutes.figmaPrivacyPolicy),
                ),
                const _SettingsDivider(),
                _SettingsRow(
                  iconAsset: 'assets/images/set-icon04.png',
                  iconBg: const Color(0x1A287DFF),
                  title: l10n.userAgreement,
                  onTap: () => Navigator.of(
                    context,
                  ).pushNamed<void>(AppRoutes.figmaUserAgreement),
                ),
                const _SettingsDivider(),
                _SettingsRow(
                  iconAsset: 'assets/images/set-icon04.png',
                  iconBg: const Color(0x1A287DFF),
                  title: l10n.checkUpdate,
                  onTap: () => _checkUpdate(context),
                ),
              ],
            ),
          ),
        ],
      ),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 56,
            width: double.infinity,
            child: _LogoutButton(onTap: () => _confirmLogout(context)),
          ),
          const SizedBox(height: 14),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _confirmDeleteAccount(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                l10n.deleteAccount,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF808690),
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyContact(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: _contact));
    if (!context.mounted) {
      return;
    }
    AppToast.show(context, AppL10n.of(context).contactCopied);
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final l10n = AppL10n.of(context);
    final confirmed = await _showConfirmDialog(
      context,
      title: l10n.logout,
      message: l10n.logoutConfirmMessage,
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    // 蒙层 loading：登出要打后端接口，弱网下有可感延迟，期间阻断重复点击。
    AppLoadingDialog.show(context);
    try {
      await state.logout();
    } finally {
      if (context.mounted) {
        AppLoadingDialog.hide(context);
      }
    }
    if (!context.mounted) {
      return;
    }
    // 退回根路由即可：根节点按 isLoggedIn 渲染，登出后它本身就是登录页
    // （见 bolt_star_app.dart 的强制登录门控）。不能用 pushNamedAndRemoveUntil 清空整个栈，
    // 那样根路由也没了，重新登录后会卡在登录页。
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final l10n = AppL10n.of(context);
    // 两步确认（对齐小程序 index.js delete-warn → delete）：
    // 第一步警示设备照片需自行清空，否则注销后无法再删。
    final step1 = await _showConfirmDialog(
      context,
      title: l10n.deleteAccount,
      message: l10n.deleteAccountWarn1,
    );
    if (step1 != true || !context.mounted) {
      return;
    }
    // 第二步二次确认。
    final step2 = await _showConfirmDialog(
      context,
      title: l10n.deleteAccountConfirmTitle,
      message: l10n.deleteAccountWarn2,
    );
    if (step2 != true || !context.mounted) {
      return;
    }
    // 蒙层 loading：注销接口 + 本地资产清理耗时可感，期间阻断重复点击。
    final ActionFeedback result;
    AppLoadingDialog.show(context);
    try {
      result = await state.deleteAccount();
    } finally {
      if (context.mounted) {
        AppLoadingDialog.hide(context);
      }
    }
    if (!context.mounted) {
      return;
    }
    // 对齐小程序：注销接口失败则留在原页并提示，不本地登出。
    if (!result.success) {
      AppToast.show(context, result.message);
      return;
    }
    // 同退出登录：回根路由，根节点自己会变成登录页。
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

Future<bool?> _showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<bool>(
    context: context,
    barrierColor: const Color(0x802A2B2B),
    builder: (context) => _ConfirmDialog(title: title, message: message),
  );
}

enum _RowTrailing { chevron, copy }

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.iconAsset,
    required this.iconBg,
    required this.title,
    this.value,
    this.trailing = _RowTrailing.chevron,
    required this.onTap,
  });

  final String iconAsset;
  final Color iconBg;
  final String title;
  final String? value;
  final _RowTrailing trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 62,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
                child: Center(
                  child: Image.asset(
                    iconAsset,
                    width: 20,
                    height: 20,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF2A2D32),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
              if (value != null) ...[
                Text(
                  value!,
                  style: const TextStyle(
                    color: Color(0xFF808690),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 1.2,
                  ),
                ),
                const SizedBox(width: 9),
              ],
              if (trailing == _RowTrailing.chevron)
                const Text(
                  '›',
                  style: TextStyle(
                    color: Color(0xFF777E88),
                    fontSize: 21,
                    fontWeight: FontWeight.w300,
                    height: 1,
                  ),
                )
              else
                Image.asset(
                  'assets/images/copy-icon01.png',
                  width: 16,
                  height: 16,
                  fit: BoxFit.contain,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 卡片内行间分隔线（小程序 `.setting-row + .setting-row::before`）：
/// 左右内缩 18、1px、rgba(207,214,224,0.72)。
class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 18),
      child: Divider(height: 1, thickness: 1, color: Color(0xB8CFD6E0)),
    );
  }
}

/// 退出登录（小程序 `.outline-logout`）：胶囊 + 浅橙底 + 橙描边 + 橙字。
class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(28);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFBF2EE).withValues(alpha: 0.8),
        borderRadius: radius,
        border: Border.all(color: const Color(0xFFEB5F1B)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Center(
            child: Text(
              AppL10n.of(context).logout,
              style: const TextStyle(
                color: Color(0xFFEB5F1B),
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(36, 35, 36, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF2A2D32),
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
            const SizedBox(height: 11),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF636A74),
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 21),
            Row(
              children: [
                Expanded(
                  child: _DialogButton(
                    label: AppL10n.of(context).cancel,
                    filled: false,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: _DialogButton(
                    label: AppL10n.of(context).confirm,
                    filled: true,
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.filled,
    required this.onPressed,
  });

  final String label;
  final bool filled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: filled ? null : const Color(0xFFEEEEEE),
        borderRadius: radius,
        gradient: filled
            ? const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xFFFF8338), Color(0xFFFF621F)],
              )
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onPressed,
          child: Container(
            height: 36,
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: filled ? Colors.white : const Color(0xFF2A2D32),
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
