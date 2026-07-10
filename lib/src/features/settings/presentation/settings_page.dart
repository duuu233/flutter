import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../routes/app_routes.dart';
import '../../../state.dart';
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

  @override
  Widget build(BuildContext context) {
    return FigmaScreen(
      title: '设置',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 17),
          FigmaGlassCard(
            borderRadius: 11,
            child: _SettingsRow(
              iconAsset: 'assets/images/set-icon01.png',
              iconBg: const Color(0x14FF6421),
              title: '语种设置',
              value: _languageLabel(state.language),
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
                  title: '联系方式',
                  value: _contact,
                  trailing: _RowTrailing.copy,
                  onTap: () => _copyContact(context),
                ),
                const _SettingsDivider(),
                _SettingsRow(
                  iconAsset: 'assets/images/set-icon03.png',
                  iconBg: const Color(0x1A287DFF),
                  title: '隐私政策',
                  onTap: () => Navigator.of(
                    context,
                  ).pushNamed<void>(AppRoutes.figmaPrivacyPolicy),
                ),
                const _SettingsDivider(),
                _SettingsRow(
                  iconAsset: 'assets/images/set-icon04.png',
                  iconBg: const Color(0x1A287DFF),
                  title: '用户协议',
                  onTap: () => Navigator.of(
                    context,
                  ).pushNamed<void>(AppRoutes.figmaUserAgreement),
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
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '用户注销',
                textAlign: TextAlign.center,
                style: TextStyle(
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

  String _languageLabel(AppLanguage language) {
    switch (language) {
      case AppLanguage.zh:
        return '简中';
      case AppLanguage.en:
        return 'English';
      case AppLanguage.ja:
        return '日本語';
    }
  }

  Future<void> _copyContact(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: _contact));
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已复制联系方式')));
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await _showConfirmDialog(
      context,
      title: '退出登录',
      message: '退出后将返回登录页，是否继续?',
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    await state.logout();
    if (!context.mounted) {
      return;
    }
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.auth, (route) => false);
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    // 两步确认（对齐小程序 index.js delete-warn → delete）：
    // 第一步警示设备照片需自行清空，否则注销后无法再删。
    final step1 = await _showConfirmDialog(
      context,
      title: '用户注销',
      message: '注销将永久删除您的所有账号数据，请确认设备照片已自行清空，否则注销后将无法删除设备照片。',
    );
    if (step1 != true || !context.mounted) {
      return;
    }
    // 第二步二次确认。
    final step2 = await _showConfirmDialog(
      context,
      title: '确认注销',
      message: '我已了解设备照片需自行处理的说明，并确认继续注销。',
    );
    if (step2 != true || !context.mounted) {
      return;
    }
    await state.deleteAccount();
    if (!context.mounted) {
      return;
    }
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.auth, (route) => false);
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
          child: const Center(
            child: Text(
              '退出登录',
              style: TextStyle(
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
                    label: '取消',
                    filled: false,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: _DialogButton(
                    label: '确定',
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
