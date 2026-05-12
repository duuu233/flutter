import 'package:flutter/material.dart';

import '../../../shared/shared.dart';
import '../../../state.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  Widget build(BuildContext context) {
    return SubPageScaffold(
      title: state.tr(zh: '设置', en: 'Settings', ja: '設定'),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          AppPanel(
            child: Column(
              children: [
                MenuTile(
                  icon: Icons.info_outline_rounded,
                  title: state.tr(zh: '关于我们', en: 'About', ja: '私たちについて'),
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
                MenuTile(
                  icon: Icons.support_agent_rounded,
                  title: state.tr(zh: '联系方式', en: 'Contact', ja: '連絡先'),
                  subtitle: 'support@frameflow.app',
                  onTap: () => _showInfoDialog(
                    context,
                    title: state.tr(zh: '联系方式', en: 'Contact', ja: '連絡先'),
                    content: 'support@frameflow.app\n+86 400-001-2400',
                  ),
                ),
                const Divider(height: 24),
                MenuTile(
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
                    title: state.tr(
                      zh: '隐私政策',
                      en: 'Privacy Policy',
                      ja: 'プライバシーポリシー',
                    ),
                    content: state.tr(
                      zh: '位置权限用于蓝牙搜索，蓝牙权限用于连接设备，相机权限用于拍照上传。当前工程未接入云端存储。',
                      en: 'Location is used for Bluetooth discovery, Bluetooth for device connection, and camera for capture upload. This build does not connect to cloud storage.',
                      ja: '位置情報は Bluetooth 探索、Bluetooth は端末接続、カメラは撮影アップロードに使用します。現在の実装はクラウド保存を利用しません。',
                    ),
                  ),
                ),
                const Divider(height: 24),
                MenuTile(
                  icon: Icons.description_outlined,
                  title: state.tr(zh: '用户协议', en: 'User Agreement', ja: '利用規約'),
                  subtitle: state.tr(
                    zh: '设备与账号使用规范',
                    en: 'Device and account rules',
                    ja: '端末とアカウントの利用規約',
                  ),
                  onTap: () => _showInfoDialog(
                    context,
                    title: state.tr(
                      zh: '用户协议',
                      en: 'User Agreement',
                      ja: '利用規約',
                    ),
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
          AppPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.tr(zh: '语种设置', en: 'Language', ja: '言語設定'),
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
          AppPanel(
            child: Column(
              children: [
                MenuTile(
                  icon: Icons.logout_rounded,
                  title: state.tr(zh: '退出登录', en: 'Log Out', ja: 'ログアウト'),
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
                MenuTile(
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
      builder: (context) =>
          AlertDialog(title: Text(title), content: Text(content)),
    );
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
