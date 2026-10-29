import 'dart:async';

import 'package:flutter/material.dart';

import '../../../network/iot/iot_api.dart';
import '../../../network/iot/iot_ws.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../state.dart';
import '../wifi_l10n.dart';
import '../wifi_status.dart';
import '../wifi_tf.dart';

/// WiFi 版 TF 卡设置（2026-10-29，同小程序 `subpackages/device/wifi-tf`）。入口：WiFi 详情「TF卡」行（有卡才能点）。
///   · 开关「TF卡播放」：开 = 设备当前是本地模式（LOCAL_TF）；不存本地，设备重新入网后自然回到关闭。
///   · 开启：先查设备，只有在线且 tfStatus=present 才弹二次确认，否则不让开并提示；确认后 POST /api/device/play-tf
///     → 等 WS command.result（按 msgid，30 秒），期间 loading 防重复点击。success=true 提示即将进入本地模式；
///     false 设备拒绝、状态不变；超时补查一次，已是本地模式按成功，否则提示未响应。
///   · 关闭：协议没有远程切回指令，只能在设备端重新入网，点了只提示。
///   · 本期不做 TF 卡清除。
class WifiTfPage extends StatefulWidget {
  const WifiTfPage({super.key, required this.state, required this.deviceId});

  final PhotoFrameState state;
  final String deviceId;

  @override
  State<WifiTfPage> createState() => _WifiTfPageState();
}

class _WifiTfPageState extends State<WifiTfPage> {
  bool _switching = false;

  /// 设备刚接受切换、还没断开的那一小段（60 秒内）开关按开显示。
  DateTime? _acceptedAt;
  String _subscribed = '';

  DeviceItem get _device => widget.state.deviceById(widget.deviceId);

  String get _deviceNo => IotApi.plainDeviceNo(_device.serialNumber);

  @override
  void initState() {
    super.initState();
    // command.result 需先订阅；详情页通常已订阅，没订才订
    final deviceNo = _deviceNo;
    if (deviceNo.isNotEmpty && !IotWs.instance.subscriptions.contains(deviceNo)) {
      IotWs.instance.subscribe(deviceNo);
      _subscribed = deviceNo;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        WifiStatusStore.instance.refresh(_device);
      }
    });
  }

  @override
  void dispose() {
    if (_subscribed.isNotEmpty) {
      IotWs.instance.unsubscribe(_subscribed);
    }
    super.dispose();
  }

  bool _isOn(WifiOnlineStatus status) {
    if (status == WifiOnlineStatus.local) {
      _acceptedAt = null; // 已进入本地模式，此后开关只看状态：设备重新入网即回到关闭
      return true;
    }
    final accepted = _acceptedAt;
    return _switching || (accepted != null && DateTime.now().difference(accepted) < const Duration(seconds: 60));
  }

  Future<void> _toggle(bool turningOn) async {
    final l10n = AppL10n.of(context);
    if (!turningOn) {
      AppToast.show(context, l10n.wifiTfRestoreHint);
      return;
    }
    if (_switching) {
      return;
    }
    AppLoadingDialog.show(context, l10n.wifiTfChecking);
    final WifiDeviceStatus status;
    try {
      status = await WifiStatusStore.instance.refresh(_device);
    } finally {
      AppLoadingDialog.hide(context);
    }
    if (!mounted) {
      return;
    }
    if (!status.online) {
      final tip = wifiBlockedTip(l10n, status.status);
      AppToast.warn(context, tip.isNotEmpty ? tip : l10n.wifiNotOnlineTip);
      return;
    }
    final tf = wifiTfState(l10n, status.shadow);
    if (tf.state != WifiTfState.present) {
      AppToast.warn(context, tf.state == WifiTfState.absent ? l10n.wifiTfNoCard : l10n.wifiTfUnknownCard);
      return;
    }
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.wifiTfConfirmTitle,
      message: l10n.wifiTfConfirmMessage,
      icon: Icons.sd_card_outlined,
      tone: AppDialogTone.danger,
      confirmLabel: l10n.wifiTfOpen,
    );
    if (confirmed == true && mounted) {
      await _startPlayTf(l10n);
    }
  }

  Future<void> _startPlayTf(AppL10n l10n) async {
    if (_switching) {
      return;
    }
    final deviceNo = _deviceNo;
    setState(() => _switching = true);
    AppLoadingDialog.show(context, l10n.wifiTfSwitching);
    // 推送可能早于 HTTP 响应：先挂上等待器再发请求
    final waiter = WifiCommandResultWaiter(IotWs.instance.on('command.result'), deviceNo, 'play_tf');
    WifiCommandOutcome? outcome;
    Object? failure;
    try {
      final res = await IotApi.playTf(deviceNo);
      outcome = await waiter.wait(res['msgid']);
      // 超时：WS 可能断过，补查一次在线状态，已是本地模式就算成功
      if (outcome.timeout) {
        try {
          if (wifiDeviceState(await IotApi.getDeviceOnline(deviceNo)) == WifiOnlineStatus.local) {
            outcome = (timeout: false, success: true, result: null);
          }
        } catch (_) {}
      }
    } catch (error) {
      debugPrint('[WiFi TF] play-tf 失败 $error');
      failure = error;
    } finally {
      waiter.dispose();
      AppLoadingDialog.hide(context);
    }
    if (!mounted) {
      return;
    }
    final String tip;
    if (failure != null) {
      tip = wifiPlayTfErrorText(l10n, failure);
    } else if (outcome == null || outcome.timeout) {
      tip = l10n.wifiTfNoResponse;
    } else if (outcome.success) {
      _acceptedAt = DateTime.now();
      tip = l10n.wifiTfAccepted;
    } else {
      tip = l10n.wifiTfRejected(outcome.result);
    }
    setState(() => _switching = false);
    AppToast.show(context, tip);
    unawaited(WifiStatusStore.instance.refresh(_device));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return ListenableBuilder(
      listenable: WifiStatusStore.instance,
      builder: (context, _) {
        final status = WifiStatusStore.instance.of(widget.deviceId);
        final tf = wifiTfState(l10n, status.shadow);
        const labelStyle = TextStyle(color: Color(0xFF33373D), fontSize: 14, fontWeight: FontWeight.w600);
        return FigmaScreen(
          title: l10n.wifiTfSettingsTitle,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              FigmaGlassCard(
                borderRadius: 18,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(
                  children: [
                    SizedBox(
                      height: 50,
                      child: Row(
                        children: [
                          Text(l10n.wifiTfCapacity, style: labelStyle),
                          const Spacer(),
                          Text(tf.text, style: const TextStyle(color: Color(0xFF777E88), fontSize: 14)),
                        ],
                      ),
                    ),
                    const Divider(height: 1, thickness: 0.5, color: Color(0x0F2A2B2B)),
                    SizedBox(
                      height: 50,
                      child: Row(
                        children: [
                          Text(l10n.wifiTfPlay, style: labelStyle),
                          const Spacer(),
                          Switch(
                            value: _isOn(status.status),
                            activeTrackColor: const Color(0xFFFF6A20),
                            onChanged: _switching ? null : _toggle,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
                child: Text(
                  l10n.wifiTfTip,
                  style: const TextStyle(color: Color(0xFF8B9098), fontSize: 12, height: 1.6),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}
