import 'package:flutter/material.dart';

import '../../../network/api_exception.dart';
import '../../../network/boltfox_api.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../state.dart';
import '../wifi_l10n.dart';
import '../wifi_share.dart';

/// 接受设备分享（2026-11-12，同小程序 `subpackages/device/wifi-share-accept`）。
/// 入口：房主分享的 H5 落地页拉起 App（boltstar://share/accept?d=..&p=..&u=..&n=..&o=..&t=..），
/// 根组件在闪屏结束且已登录后推到本页（见 [WifiShareInbox]）。
///   · 参数缺失 / 格式不对：「分享链接无效」；
///   · 进页面校验一次有效期（chkTimeValid），明确过期换成「分享链接已过期」，校验失败不拦；
///   · 点「接受」：再校验一次（以这次为准，校验不了不接受）→ 是自己分享的提示 → 已在自己列表直接进详情 →
///     addUserProduct（isToHave=0、shareUserId=所有者 userId）→ 重拉列表进设备详情。服务端拒绝时提示接口原话。
class WifiShareAcceptPage extends StatefulWidget {
  const WifiShareAcceptPage({super.key, required this.state, required this.query});

  final PhotoFrameState state;
  final Map<String, String> query;

  @override
  State<WifiShareAcceptPage> createState() => _WifiShareAcceptPageState();
}

class _WifiShareAcceptPageState extends State<WifiShareAcceptPage> {
  late final WifiShareInvite? _invite = WifiShareInvite.parse(widget.query);
  bool _checking = false;
  bool _expired = false;
  bool _accepting = false;

  @override
  void initState() {
    super.initState();
    final invite = _invite;
    debugPrint('[设备分享] 接受页 ${invite == null ? '链接无效' : '设备 ${invite.deviceId} 所有者 ${invite.ownerUserId}'}');
    if (invite != null) {
      _checking = true; // 首帧前直接置位（initState 里不能 setState）
      _checkOnEnter();
    }
  }

  Future<void> _checkOnEnter() async {
    final valid = await _checkValid();
    if (!mounted) {
      return;
    }
    setState(() {
      _checking = false;
      if (valid == false) {
        _expired = true;
      }
    });
  }

  /// true 有效 / false 已过期 / null 校验失败。
  Future<bool?> _checkValid() async {
    final invite = _invite;
    if (invite == null) {
      return false;
    }
    try {
      final valid = wifiShareValidFlag(await BoltFoxApi.chkTimeValid(currentTime: invite.shareTime));
      debugPrint('[设备分享] 链接有效期校验 ${invite.shareTime} ${valid == null ? '返回无法识别' : valid ? '有效' : '已过期'}');
      return valid;
    } on ApiException catch (error) {
      // 同小程序：业务失败但 retData 带了 boolean 的按它判断
      final flag = wifiShareValidFlag(error.data is bool ? error.data : null);
      debugPrint('[设备分享] 链接有效期校验失败 ${error.code} ${error.message}');
      return flag;
    } catch (error) {
      debugPrint('[设备分享] 链接有效期校验失败 $error');
      return null;
    }
  }

  DeviceItem? _findBound(String deviceId) {
    final target = wifiPlainDeviceNo(deviceId);
    for (final device in widget.state.devices) {
      if (wifiPlainDeviceNo(device.serialNumber) == target) {
        return device;
      }
    }
    return null;
  }

  Future<void> _accept() async {
    final invite = _invite;
    if (invite == null || _accepting || _checking || _expired) {
      return;
    }
    setState(() => _accepting = true);
    try {
      await _doAccept(invite);
    } finally {
      if (mounted) {
        setState(() => _accepting = false);
      }
    }
  }

  Future<void> _doAccept(WifiShareInvite invite) async {
    final l10n = AppL10n.of(context);
    final valid = await _checkValid();
    if (!mounted) {
      return;
    }
    if (valid == false) {
      setState(() => _expired = true);
      return;
    }
    if (valid == null) {
      AppToast.warn(context, l10n.wifiAcceptCheckFailed);
      return;
    }
    if (widget.state.currentUser.userId.isEmpty) {
      await widget.state.refreshCurrentUser();
    }
    if (!mounted) {
      return;
    }
    if (widget.state.currentUser.userId == '${invite.ownerUserId}') {
      AppToast.show(context, l10n.wifiAcceptOwn);
      return;
    }
    await widget.state.refreshDevices();
    if (!mounted) {
      return;
    }
    final existed = _findBound(invite.deviceId);
    if (existed != null) {
      AppToast.show(context, l10n.wifiAcceptExists);
      _openDetail(existed);
      return;
    }
    try {
      await BoltFoxApi.addUserProduct(
        productId: invite.productId,
        productName: invite.deviceName.isNotEmpty ? invite.deviceName : '智能相框',
        productSerialNo: invite.deviceId,
        isToHave: 0,
        shareUserId: invite.ownerUserId,
      );
      debugPrint('[设备分享] 已接受 设备 ${invite.deviceId}');
    } catch (error) {
      debugPrint('[设备分享] 接受失败 $error');
      if (mounted) {
        final message = error is ApiException ? error.message : '';
        AppToast.warn(context, message.isNotEmpty ? message : l10n.wifiAcceptFailed);
      }
      return;
    }
    await widget.state.refreshDevices();
    if (!mounted) {
      return;
    }
    AppToast.show(context, l10n.wifiAcceptDone);
    final saved = _findBound(invite.deviceId);
    if (saved != null) {
      _openDetail(saved);
    } else {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _openDetail(DeviceItem device) {
    widget.state.selectDevice(device.id);
    Navigator.of(context).pushReplacementNamed(AppRoutes.figmaDeviceDetails, arguments: device.id);
  }

  void _close() => Navigator.of(context).popUntil((route) => route.isFirst);

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final invite = _invite;
    final String title;
    final String desc;
    if (invite == null) {
      title = l10n.wifiAcceptInvalid;
      desc = l10n.wifiAcceptReshare;
    } else if (_expired) {
      title = l10n.wifiAcceptExpired;
      desc = l10n.wifiAcceptReshare;
    } else {
      title = invite.deviceName.isNotEmpty ? invite.deviceName : '--';
      desc = l10n.wifiAcceptDesc(invite.ownerName);
    }
    final canAccept = invite != null && !_expired;
    final busy = _accepting || _checking;
    return FigmaScreen(
      title: l10n.wifiAcceptPageTitle,
      body: Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [BoxShadow(color: Color(0x143C3510), blurRadius: 16, offset: Offset(0, 4))],
          ),
          child: Column(
            children: [
              if (canAccept) ...[
                Image.asset('assets/images/home-device-thumb.png', width: 120, height: 120),
                const SizedBox(height: 16),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF2A2D32), fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Text(
                desc,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF8B9098), fontSize: 14, height: 1.5),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: canAccept ? _accept : _close,
                child: Opacity(
                  opacity: canAccept && busy ? 0.6 : 1,
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFF9140), Color(0xFFFF6A20)],
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      !canAccept
                          ? l10n.wifiAcceptBackHome
                          : _accepting
                          ? l10n.wifiAcceptProcessing
                          : _checking
                          ? l10n.wifiAcceptChecking
                          : l10n.wifiAcceptButton,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              if (canAccept) ...[
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: _close,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(l10n.wifiAcceptLater, style: const TextStyle(color: Color(0xFF8B9098), fontSize: 14)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
