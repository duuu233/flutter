import 'package:flutter/material.dart';

import '../../../routes/app_routes.dart';
import '../../../state.dart';
import '../../figma_generated/presentation/widgets/figma_common.dart';

/// 设置页面，对应 UI 稿「设置」。
///
/// 包含语种设置、联系方式、隐私政策、用户协议、更新入口，以及退出登录与用户注销。
/// 退出登录 / 用户注销使用确认弹窗（对应「设置-退出登录」「设置-用户注销」两张稿）。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  Widget build(BuildContext context) {
    return FigmaPhoneFrame(
      child: Stack(
        children: [
          const FigmaPageBackground(),
          const Positioned(
            left: 0,
            top: 0,
            width: 375,
            height: 90,
            child: FigmaTopNavigation(title: '设置'),
          ),
          Positioned(
            left: 24,
            top: 109,
            width: 327,
            child: FigmaGlassCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  _SettingsRow(
                    icon: Icons.translate_rounded,
                    iconColor: const Color(0xFFFF6A24),
                    title: '语种设置',
                    value: _languageLabel(state.language),
                    onTap: () => Navigator.of(
                      context,
                    ).pushNamed<void>(AppRoutes.figmaLanguageSettings),
                  ),
                  const FigmaFormDivider(),
                  _SettingsRow(
                    icon: Icons.phone_in_talk_outlined,
                    iconColor: const Color(0xFF4A98FF),
                    title: '联系方式',
                    value: '99999@qq.com',
                    onTap: () => _showContactDialog(context),
                  ),
                  const FigmaFormDivider(),
                  _SettingsRow(
                    icon: Icons.shield_outlined,
                    iconColor: const Color(0xFF4A98FF),
                    title: '隐私政策',
                    onTap: () => Navigator.of(
                      context,
                    ).pushNamed<void>(AppRoutes.figmaPrivacyPolicy),
                  ),
                  const FigmaFormDivider(),
                  _SettingsRow(
                    icon: Icons.description_outlined,
                    iconColor: const Color(0xFF4A98FF),
                    title: '用户协议',
                    onTap: () => Navigator.of(
                      context,
                    ).pushNamed<void>(AppRoutes.figmaUserAgreement),
                  ),
                  const FigmaFormDivider(),
                  _SettingsRow(
                    icon: Icons.system_update_alt_rounded,
                    iconColor: const Color(0xFF4A98FF),
                    title: '更新BoltStar',
                    value: '版本1.0.0',
                    onTap: () => Navigator.of(
                      context,
                    ).pushNamed<void>(AppRoutes.figmaUpdateBoltStarAvailable),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 26,
            top: 470,
            width: 323,
            height: 56,
            child: _OutlinedActionButton(
              label: '退出登录',
              onPressed: () => _confirmLogout(context),
            ),
          ),
          Positioned(
            left: 0,
            top: 752,
            width: 375,
            child: Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _confirmDeleteAccount(context),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6, horizontal: 24),
                  child: Text(
                    '用户注销',
                    style: TextStyle(
                      color: Color(0x992A2B2B),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const FigmaBottomHomeIndicator(),
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

  void _showContactDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('联系方式'),
        content: const Text('客服邮箱：99999@qq.com\n服务时间：周一至周五 9:00 - 18:00'),
        actions: [
          TextButton(
            onPressed: () => Navigator.maybePop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await _showConfirmDialog(
      context,
      title: '退出登录',
      message: '退出后将返回登录页，是否继续？',
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    state.logout();
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.auth, (route) => false);
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await _showConfirmDialog(
      context,
      title: '用户注销',
      message: '注销后您的所有数据将会彻底删除且无法恢复，确定要注销账号？',
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    state.deleteAccount();
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
    barrierColor: Colors.black.withValues(alpha: 0.32),
    builder: (context) => _ConfirmDialog(title: title, message: message),
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.value,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 58,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 22),
              const SizedBox(width: 14),
              Expanded(child: Text(title, style: FigmaTextStyles.formLabel)),
              if (value != null)
                Text(
                  value!,
                  style: FigmaTextStyles.formHint.copyWith(
                    color: const Color(0x992A2B2B),
                  ),
                ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0x662A2B2B),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutlinedActionButton extends StatelessWidget {
  const _OutlinedActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onPressed,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFFF6A24), width: 1.4),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFFFF6A24),
              fontSize: 18,
              fontWeight: FontWeight.w500,
              letterSpacing: 2,
              height: 1.2,
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF2A2B2B),
                fontSize: 18,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0x992A2B2B),
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _DialogButton(
                    label: '取消',
                    filled: false,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 14),
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
    return Material(
      color: filled ? const Color(0xFFFF6A24) : const Color(0xFFF1F1F3),
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onPressed,
        child: Container(
          height: 46,
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: filled ? Colors.white : const Color(0xFF2A2B2B),
              fontSize: 16,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}
