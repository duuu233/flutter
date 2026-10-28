import 'package:flutter/material.dart';

import '../../../network/iot/iot_api.dart';
import '../../../network/iot/iot_client.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../shared/widgets/home_figma_common.dart';
import '../../../state.dart';
import '../wifi_l10n.dart';
import '../wifi_sleep.dart';
import '../wifi_status.dart';
import '../wifi_widgets.dart';

/// WiFi 版休眠设置，同步小程序 `subpackages/device/wifi-sleep`（实现报告反馈第二节）。入口：WiFi 设备详情「休眠设置」。
///   · 回显：IoT GET /api/device/sleep（只要权限，离线也能查）；从未设置显示「未开启休眠」；
///   · 三种模式：关闭（确认后提交 mode=0）/ 周期（休眠、唤醒两个 HH:mm，不能相同，可跨午夜）/
///     一次性（开始、结束各一个日期 + 时间，开始早于结束、结束不能已过）；
///   · 保存：IoT POST /api/device/sleep，只传本地时间、不转 UTC；要求设备在线，4041 补查给休眠 / 关机 / 离线提示，
///     4000 显示服务端给的具体字段；保存成功后重新查询回显。
/// 换算与校验见 [WifiSleep]。
class WifiSleepPage extends StatefulWidget {
  const WifiSleepPage({super.key, required this.state, required this.deviceId});

  final PhotoFrameState state;
  final String deviceId;

  @override
  State<WifiSleepPage> createState() => _WifiSleepPageState();
}

class _WifiSleepPageState extends State<WifiSleepPage> {
  bool _loading = true;
  bool _queryFailed = false;
  bool _saving = false;
  String _summary = '';
  String _updatedAt = '';
  WifiSleepForm _form = WifiSleep.formFromSleep(null);

  String get _deviceNo => IotApi.plainDeviceNo(widget.state.deviceById(widget.deviceId).serialNumber);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadPlan(fillForm: true);
      if (mounted) {
        setState(() => _loading = false);
      }
    });
  }

  /// 查当前休眠计划；[fillForm]=true 时按它回填表单（进页时），保存后只刷新顶部说明。
  Future<void> _loadPlan({required bool fillForm}) async {
    Map<String, dynamic>? plan;
    try {
      plan = await IotApi.getSleep(_deviceNo);
      debugPrint('[WiFi休眠] 当前计划 $plan');
    } catch (error) {
      debugPrint('[WiFi休眠] 查询失败 $error');
    }
    if (!mounted) {
      return;
    }
    final l10n = AppL10n.of(context);
    setState(() {
      _queryFailed = plan == null;
      _summary = plan != null ? WifiSleep.summary(l10n, plan) : l10n.wifiSleepQueryFailed;
      _updatedAt = '${plan?['updatedAt'] ?? ''}';
      if (fillForm) {
        _form = WifiSleep.formFromSleep(plan);
      }
    });
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    final l10n = AppL10n.of(context);
    final built = WifiSleep.buildPayload(l10n, _deviceNo, _form);
    final payload = built.payload;
    if (payload == null) {
      AppToast.warn(context, built.error);
      return;
    }
    if (payload['mode'] == WifiSleep.modeOff) {
      final confirmed = await showAppConfirmDialog(
        context,
        title: l10n.wifiSleepCloseTitle,
        message: l10n.wifiSleepCloseConfirm,
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }
    debugPrint('[WiFi休眠] 保存 $payload');
    setState(() => _saving = true);
    try {
      await IotApi.setSleep(payload);
    } catch (error) {
      debugPrint('[WiFi休眠] 保存失败 $error');
      if (!mounted) return;
      var tip = l10n.wifiSaveFailed;
      if (error is IotException) {
        tip = error.numericCode == 4041
            ? await wifiOfflineTipFor(l10n, _deviceNo)
            : error.numericCode == 4000 && error.serverMessage.isNotEmpty
            ? error.serverMessage
            : error.message;
      }
      if (mounted) {
        setState(() => _saving = false);
        AppToast.warn(context, tip);
      }
      return;
    }
    if (!mounted) return;
    AppToast.show(context, payload['mode'] == WifiSleep.modeOff ? l10n.wifiSleepClosedToast : l10n.wifiSleepSaved);
    await _loadPlan(fillForm: false);
    if (mounted) {
      setState(() => _saving = false);
    }
  }

  Future<void> _pickTime(String current, WifiSleepForm Function(String value) apply) async {
    final value = await pickWifiTime(context, current);
    if (value != null && mounted) {
      setState(() => _form = apply(value));
    }
  }

  Future<void> _pickDate(String current, WifiSleepForm Function(String value) apply) async {
    final value = await pickWifiDate(context, current);
    if (value != null && mounted) {
      setState(() => _form = apply(value));
    }
  }

  Widget _dateTimeRow(String label, String date, String time, {required bool begin}) {
    const valueStyle = TextStyle(color: Color(0xFF2A2D32), fontSize: 14, fontWeight: FontWeight.w600);
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF33373D), fontSize: 14)),
          const Spacer(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _pickDate(
              date,
              (value) => begin ? _form.copyWith(beginDate: value) : _form.copyWith(endDate: value),
            ),
            child: Padding(padding: const EdgeInsets.all(6), child: Text(date, style: valueStyle)),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _pickTime(
              time,
              (value) => begin ? _form.copyWith(beginTime: value) : _form.copyWith(endTime: value),
            ),
            child: Padding(padding: const EdgeInsets.all(6), child: Text(time, style: valueStyle)),
          ),
        ],
      ),
    );
  }

  Widget _tip(String text) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(text, style: const TextStyle(color: Color(0xFF8A9099), fontSize: 12, height: 1.5)),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    const titleStyle = TextStyle(color: Color(0xFF25282D), fontSize: 15, fontWeight: FontWeight.w700);
    return FigmaScreen(
      title: l10n.wifiSleepSettings,
      body: _loading
          ? const Padding(padding: EdgeInsets.only(top: 120), child: Center(child: CircularProgressIndicator()))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                FigmaGlassCard(
                  borderRadius: 16,
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.wifiSleepCurrent, style: titleStyle),
                      const SizedBox(height: 8),
                      Text(
                        _summary,
                        style: TextStyle(
                          color: _queryFailed ? const Color(0xFFE5533D) : const Color(0xFF2A2D32),
                          fontSize: 14,
                        ),
                      ),
                      if (_updatedAt.isNotEmpty) _tip(l10n.wifiLastSet(_updatedAt)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                FigmaGlassCard(
                  borderRadius: 16,
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(l10n.wifiSleepMode, style: titleStyle),
                      const SizedBox(height: 12),
                      WifiSegment<int>(
                        value: _form.mode,
                        items: [
                          (WifiSleep.modeOff, l10n.wifiSleepModeOff),
                          (WifiSleep.modeDaily, l10n.wifiSleepModeDaily),
                          (WifiSleep.modeOnce, l10n.wifiSleepModeOnce),
                        ],
                        onChanged: (mode) => setState(() => _form = _form.copyWith(mode: mode)),
                      ),
                      const SizedBox(height: 8),
                      if (_form.mode == WifiSleep.modeDaily) ...[
                        WifiFormRow(
                          label: l10n.wifiSleepDailySleep,
                          value: _form.sleepTime,
                          onTap: () => _pickTime(_form.sleepTime, (value) => _form.copyWith(sleepTime: value)),
                        ),
                        WifiFormRow(
                          label: l10n.wifiSleepDailyWake,
                          value: _form.crossDay ? l10n.wifiNextDay(_form.wakeTime) : _form.wakeTime,
                          onTap: () => _pickTime(_form.wakeTime, (value) => _form.copyWith(wakeTime: value)),
                        ),
                        _tip(l10n.wifiSleepCrossDayTip),
                      ] else if (_form.mode == WifiSleep.modeOnce) ...[
                        _dateTimeRow(l10n.wifiSleepBegin, _form.beginDate, _form.beginTime, begin: true),
                        _dateTimeRow(l10n.wifiSleepEnd, _form.endDate, _form.endTime, begin: false),
                        _tip(l10n.wifiSleepOnceTip),
                      ] else
                        _tip(l10n.wifiSleepOffTip),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.wifiSleepNote,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF8A9099), fontSize: 12),
                ),
                const SizedBox(height: 24),
              ],
            ),
      bottom: _loading
          ? null
          : FigmaHomePrimaryButton(
              label: _saving ? l10n.wifiSaving : l10n.wifiSave,
              fontWeight: FontWeight.w700,
              onPressed: _saving ? null : _save,
            ),
    );
  }
}
