import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_l10n.dart';
import 'app_toast.dart';

/// 设备名称长度上限，按 Unicode 码点计（emoji / 生僻字算 1 个）。
///
/// 与小程序 `utils/device-name.js` 的 `DEVICE_NAME_MAX_LEN`、
/// `PhotoFrameState.renameDevice` 的服务端提交前校验三处同值，改要一起改。
const int kDeviceNameMaxLength = 20;

/// 按码点数名称长度：`String.length` 是 UTF-16 码元数，一个 emoji 会算成 2，
/// 20 字上限会莫名其妙变成 10 个 emoji。
int deviceNameLength(String value) => value.runes.length;

/// 设备名称编辑弹窗（小程序 `components/device-name-dialog` 的 Flutter 版）。
///
/// 三个入口共用同一套样式与校验：我的设备列表、设备详情摘要卡、**绑定成功后的命名引导**。
/// 原来 Flutter 侧是 `showAppConfirmDialog + AppDialogTextField` 拼出来的通用确认框，
/// 没有独立视觉（用户反馈「设备名称编辑弹出框无样式」），这里按小程序稿重画：
/// 顶部相框+笔的橙色标记 → 居中标题与副标题 → 带实时计数的输入框 → 取消/保存双键。
///
/// 返回值：点「保存」且校验通过 → 去掉首尾空格的名称；取消/点遮罩/返回键 → null。
/// **本组件只负责取名，不负责调接口**——保存中的 loading 与失败提示留在调用方
///（三处都已有 `AppLoadingDialog` + 失败 toast，见需求第 16 项）。
Future<String?> showDeviceNameDialog(
  BuildContext context, {
  required String initialValue,
  String? title,
  String? subtitle,
  String? cancelLabel,
  String? confirmLabel,
  bool barrierDismissible = true,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: const Color(0x6B131D2B),
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) => _DeviceNameDialog(
      initialValue: initialValue,
      title: title,
      subtitle: subtitle,
      cancelLabel: cancelLabel,
      confirmLabel: confirmLabel,
    ),
  );
}

class _DeviceNameDialog extends StatefulWidget {
  const _DeviceNameDialog({
    required this.initialValue,
    this.title,
    this.subtitle,
    this.cancelLabel,
    this.confirmLabel,
  });

  final String initialValue;
  final String? title;
  final String? subtitle;
  final String? cancelLabel;
  final String? confirmLabel;

  @override
  State<_DeviceNameDialog> createState() => _DeviceNameDialogState();
}

class _DeviceNameDialogState extends State<_DeviceNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  /// 双击「保存」会 pop 两次（第二次把弹窗下面的页面也弹掉），用闩锁挡住
  ///（同 `showAppConfirmDialog` 的做法）。
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  void _cancel() {
    if (_resolved) {
      return;
    }
    _resolved = true;
    Navigator.of(context).pop();
  }

  void _confirm() {
    if (_resolved) {
      return;
    }
    final l10n = AppL10n.of(context);
    final name = _controller.text.trim();
    // 空名称不放行：接口层虽然也拦（renameDevice），但那要等一次网络往返才报错。
    if (name.isEmpty) {
      AppToast.warn(context, l10n.devNameHint);
      return;
    }
    // 超长在输入阶段已被 maxLength 限制住，这里是提交前的最后一道（粘贴、输入法组合等）。
    if (deviceNameLength(name) > kDeviceNameMaxLength) {
      AppToast.warn(context, l10n.devNameTooLong(kDeviceNameMaxLength));
      return;
    }
    _resolved = true;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final length = deviceNameLength(_controller.text);
    return Dialog(
      backgroundColor: Colors.transparent,
      // 键盘避让（2026-08-01）：`Dialog` 自带的 viewInsets 让位只保证「弹窗整体被顶到键盘之上」，
      // 小屏 + 大键盘时剩余高度可能不够，内容会溢出、底部两个按钮被裁掉。
      // 纵向留 24 的余量并把内容放进可滚动容器，任何机型上「取消/保存」都够得着。
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFAFFFFFF), Color(0xF5F6FBFF)],
            ),
            border: Border.all(color: const Color(0xF0FFFFFF)),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4E688D).withValues(alpha: 0.22),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 图标与标题同一行（2026-08-01 产品要求）：原先 76 的大图独占一行，
              // 把弹窗撑得很高，键盘一弹底部按钮就没地方放。缩到 32 并与标题并排。
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const _DeviceNameMark(),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.title ?? l10n.devRenameTitle,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF252B33),
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                widget.subtitle ?? l10n.devNameDialogTip,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF89919D),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              // 输入行：左输入 + 右实时计数（n/20）。
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: const Color(0xDBECF4FC),
                  border: Border.all(color: const Color(0x389CB3D1)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        maxLength: kDeviceNameMaxLength,
                        // 默认 maxLength 按 UTF-16 码元截断，emoji 会被砍成半个代理对（乱码方块）。
                        // 换成按码点计数的限制器，与 [deviceNameLength] / 后端校验同口径。
                        maxLengthEnforcement: MaxLengthEnforcement.none,
                        inputFormatters: [
                          _RuneLengthLimiter(kDeviceNameMaxLength),
                        ],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _confirm(),
                        cursorColor: const Color(0xFFFF6725),
                        style: const TextStyle(
                          color: Color(0xFF252B33),
                          fontSize: 15,
                          height: 1.2,
                        ),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          counterText: '',
                          hintText: l10n.devNameHint,
                          hintStyle: const TextStyle(
                            color: Color(0xFF98A0AB),
                            fontSize: 15,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      '$length/$kDeviceNameMaxLength',
                      style: const TextStyle(
                        color: Color(0xFF98A0AB),
                        fontSize: 11,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _DialogButton(
                      label: widget.cancelLabel ?? l10n.cancel,
                      textColor: const Color(0xFF6D7682),
                      background: const Color(0xFFEDF2F7),
                      onTap: _cancel,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DialogButton(
                      label: widget.confirmLabel ?? l10n.save,
                      textColor: Colors.white,
                      gradient: const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [Color(0xFFFF8B42), Color(0xFFFF6122)],
                      ),
                      onTap: _confirm,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 弹窗标题行左侧的设备图（2026-07-31 起用 `home-icon02`，与首页/设备列表/设备详情统一）。
/// 该图四角 alpha=0 自带圆角，故不加底色容器与圆角裁剪，否则四角会露出色晕。
/// 2026-08-01：由独占一行的 76 缩到与标题同行的 32（小程序 `.name-dialog__device` 64rpx）。
class _DeviceNameMark extends StatelessWidget {
  const _DeviceNameMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Image.asset(
        'assets/images/home-icon02.png',
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => const Icon(
          Icons.photo_library_outlined,
          color: Color(0xFFEB5F1B),
          size: 22,
        ),
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.textColor,
    required this.onTap,
    this.background,
    this.gradient,
  });

  final String label;
  final Color textColor;
  final VoidCallback onTap;
  final Color? background;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(999);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        gradient: gradient,
        borderRadius: radius,
        boxShadow: gradient == null
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFFFF6122).withValues(alpha: 0.22),
                  blurRadius: 14,
                  offset: const Offset(0, 7),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Container(
            height: 44,
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              // 文案恒居中（对齐小程序 2026-07-31 的按钮居中修复）：容器已 center，
              // 这里再钉一次 textAlign，长短文案、换语种都不会偏。
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 按 Unicode 码点数限长的输入格式化器。
///
/// Flutter 自带的 `LengthLimitingTextInputFormatter` 按 UTF-16 码元截断：一个 emoji 占 2 个，
/// 20 字上限只能打 10 个 emoji，而且截在代理对中间会留下半个字符（乱码方块）。
class _RuneLengthLimiter extends TextInputFormatter {
  const _RuneLengthLimiter(this.maxRunes);

  final int maxRunes;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final runes = newValue.text.runes.toList();
    if (runes.length <= maxRunes) {
      return newValue;
    }
    // 超限：保留旧值，不做「截半个 emoji」的硬砍，光标也不用重算。
    return oldValue;
  }
}
