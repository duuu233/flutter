import 'dart:async';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../../device/ble/device_ble.dart';
import '../../../device/ble_controller.dart';
import '../../../device/frame_device_protocol.dart';
import '../../../device/recently_bound_device.dart';
import '../../../device/serial_match.dart';
import '../../../native_device_api.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/device_name_dialog.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../state.dart';
import 'bind_device_found.dart';
import 'bind_device_not_found.dart';
import 'bind_device_searching.dart';
import '../../../device/device_thumb.dart';
import '../../../device/product_broadcast_id.dart';
import '../../../device/wifi/blufi.dart';
import '../../../device/wifi/broadcast_match.dart';
import '../../../network/boltfox_api.dart';
import '../../wifi/presentation/wifi_list_page.dart';
import '../../wifi/wifi_l10n.dart';
import '../../wifi/wifi_provision.dart';

/// 绑定设备流程编排页：权限 → 扫描 → 发现 / 未发现 → 连接 → 绑定。
///
/// 把扫描结果与连接态集中在一个 State 内，按阶段渲染对应的视觉页
/// （[BindDeviceSearching] / [BindDeviceFound] / [BindDeviceNotFound]）。
/// 真正的 BLE 动作走 [BleController]（持久连接，供首页/投屏复用）。
class BindDeviceFlowPage extends StatefulWidget {
  const BindDeviceFlowPage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<BindDeviceFlowPage> createState() => _BindDeviceFlowPageState();
}

enum _Stage { permission, scanning, found, notFound }

/// WiFi 版设备的规格查询结果（getProductByDevice，同一次搜索每台只查一次）。
class _WifiLookup {
  const _WifiLookup.loading() : loading = true, product = null, reason = '';
  const _WifiLookup.done(this.product, this.reason) : loading = false;

  final bool loading;

  /// 查到的产品行（productId / productName / sizeModel）；null = 未知设备。
  final Map<String, dynamic>? product;

  /// 没查到的原因（联调用，非正式包在未知设备提示里显示）。
  final String reason;
}

class _BindDeviceFlowPageState extends State<BindDeviceFlowPage> {
  /// 扫描窗口（2026-07-29 由 12s 放宽到 20s，与小程序 `bind.js SCAN_TIMEOUT_MS` 同值）。
  ///
  /// 依据：设备广播间隔约 3s，7 台同时在场时 12s 实测经常搜不全（少 1~2 台）——每台设备一个
  /// 窗口内只有几次现身机会，还要和别台抢同一条广播信道。20s 给每台约 6~7 次机会，基本能扫全。
  /// 之所以敢把窗口拉这么长，是因为交互同时改成了「搜到一个显示一个」：用户不用等满窗口——
  /// 列表边搜边追加，看到自己那台就能直接点「立即绑定」（[_stopScanForBind] 会立刻停扫转入连接）。
  /// 旧交互下列表要等窗口跑满才整批出现，单方面拉长窗口只会让人干等，这也是两件事必须一起改的原因。
  static const Duration _scanTimeout = Duration(seconds: 20);

  final BleController _ble = BleController.instance;
  // 初始为「权限确认」安静占位态：系统授权框必须**先于**扫描动画单独出现，
  // 不能压在「正在搜索」雷达页上同屏弹出（产品要求：先授权，后设备操作）。
  _Stage _stage = _Stage.permission;
  List<ScanResult> _results = const [];
  bool _binding = false;

  /// 产品列表的「广播名 → 尺寸型号」，列表副标题的尺寸按它显示（见 [_entryOf]）；拉到前为空，尺寸显示「--寸」。
  List<ProductSizeModel> _productSizeModels = const [];

  /// 扫描是否仍在进行。与 [_stage] 分开存：搜到第一台后 stage 就切到 `found`（列表开始显示），
  /// 但扫描还在继续，雷达要继续转、列表要继续追加——这两件事同时为真才是「边搜边显示」。
  bool _scanning = false;

  /// 扫描轮次。每次重新搜索/停扫都自增，在途扫描的增量与最终结果按 seq 对不上就直接丢弃，
  /// 避免上一轮的结果回写到这一轮的列表（对齐小程序 `bind.js` 的 `scanSeq`）。
  int _scanSeq = 0;

  /// 设备 id → 首次被搜到的序号，用来把展示顺序钉死（见 [_applyScanResult]）。
  final Map<String, int> _scanOrder = <String, int>{};

  /// WiFi 版规格查询账本（12 位 deviceNo → 结果）。不跨搜索缓存：每次重新搜索都换一本新账、全部重查；
  /// 换新对象而不是清空旧对象——上一轮在途的查询回来时写的是旧账本，不会污染本轮（同小程序 bind.js wifiLookups）。
  Map<String, _WifiLookup> _wifiLookups = <String, _WifiLookup>{};

  /// WiFi 版「立即配网」的蓝牙连接进行中（防连点）。
  bool _wifiConnecting = false;

  @override
  void initState() {
    super.initState();
    // 与扫描并行拉产品列表（会话缓存、失败静默），回来后重建列表补上尺寸
    unawaited(
      widget.state.loadProductSizeModels().then((list) {
        if (mounted && list.isNotEmpty) {
          setState(() => _productSizeModels = list);
        }
      }),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  @override
  void dispose() {
    // 系统返回键/iOS 侧滑不会经过「取消搜索」按钮；页面销毁时也必须立刻停扫，
    // 否则 20s 扫描会留在后台占用射频，下一次进入容易与旧扫描互相干扰。
    _scanSeq++;
    _scanning = false;
    unawaited(_ble.stopScan());
    super.dispose();
  }

  Future<void> _startScan() async {
    if (!mounted) {
      return;
    }
    // 本轮扫描的编号；展示顺序表跟着一起重置（见 _applyScanResult）。
    final seq = ++_scanSeq;
    _scanOrder.clear();
    _wifiLookups = <String, _WifiLookup>{};
    // 权限阶段：页面保持只有导航栏的安静占位，等系统授权框（定位/附近设备）先行处理完。
    setState(() {
      _stage = _Stage.permission;
      _results = const [];
      _scanning = false;
    });
    // 蓝牙开启/权限校验（对齐小程序 utils/bluetooth.js openAdapter + describeAdapterError）：
    // 区分「环境不支持/通道缺失」「权限没给」「蓝牙没开」，分别给明确引导，而不是把所有
    // 失败都静默混成「未发现设备」。try/catch 兜住 iOS 未注册 device_api 通道时的
    // MissingPluginException，避免整条链路卡在 searching。
    DevicePermissionStatus status;
    try {
      status = await NativeDeviceApi.requestBluetoothPermissions();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _stage = _Stage.notFound);
      // 异常详情进日志，不进 toast（用户读不完也看不懂技术文本）。
      debugPrint('[Bind] 蓝牙权限通道异常: $error');
      _toast(AppL10n.of(context).bindBtUnsupported);
      return;
    }
    if (!mounted) {
      return;
    }
    if (!status.bluetoothPermissionGranted) {
      // 用户拒绝授权：直接弹「去设置」引导框（对齐产品图3），页面落到「未发现设备」可重试。
      setState(() => _stage = _Stage.notFound);
      final l10n = AppL10n.of(context);
      await _showBluetoothGuide(
        title: l10n.bindBtPermissionTitle,
        message: l10n.bindBtPermissionMessage,
        actionLabel: l10n.bindGoSettings,
        onAction: NativeDeviceApi.openAppSettings,
      );
      return;
    }
    if (!status.bluetoothEnabled) {
      setState(() => _stage = _Stage.notFound);
      final l10n = AppL10n.of(context);
      await _showBluetoothGuide(
        title: l10n.bindBtOffTitle,
        message: l10n.bindBtOffMessage,
        actionLabel: l10n.bindGoOpenBt,
        onAction: NativeDeviceApi.openBluetoothSettings,
      );
      return;
    }
    // 权限/开关全就绪，才切入「正在搜索」态开始设备操作（雷达动画 + BLE 扫描同时开始）。
    setState(() {
      _stage = _Stage.scanning;
      _scanning = true;
    });
    // 扫描：对齐小程序 bind.js —— 白名单只留目标相框（2 个尺寸），窗口见 [_scanTimeout]。
    // onUpdate：搜到一台就渲染一台（边搜边显示），不必等满窗口；扫描期间雷达继续转。
    List<ScanResult> list;
    try {
      list = await _ble.scan(
        timeout: _scanTimeout,
        // 蓝牙版与 WiFi 版一起搜（只有本页这么搜，其它扫描入口不受影响），行上用标签区分
        includeWifi: true,
        onUpdate: (devices) => _applyScanResult(seq, devices),
      );
    } catch (error) {
      if (!mounted || seq != _scanSeq) {
        return; // 本轮已被停扫/重搜作废
      }
      debugPrint('[Bind] 扫描失败: $error');
      // 超时单独提示「连接超时，稍后再试」（2026-08-01，对齐小程序）：
      // 扫描超时和真扫描失败对用户是两回事，且必须走 l10n 才跟随语种。
      final l10n = AppL10n.of(context);
      _toast(
        isBleTimeoutError(error) ? l10n.bleConnectTimeout : l10n.bindScanFailed,
      );
      setState(() {
        _scanning = false;
        _stage = _Stage.notFound;
      });
      return;
    }
    if (!mounted || seq != _scanSeq) {
      // 停扫（_stopScanForBind/_cancelScan）或重新搜索已让本轮作废：结果直接丢弃，
      // 否则会把已经停下的那一刻的列表又盖回去，甚至把用户已选中的那台挤动。
      return;
    }
    _applyScanResult(seq, list);
    setState(() {
      _scanning = false;
      _stage = _results.isEmpty ? _Stage.notFound : _Stage.found;
    });
  }

  /// 把一次扫描结果（增量或最终）渲染到列表；作废轮次的结果直接丢弃。
  ///
  /// 展示顺序按「首次被搜到的先后」钉死，新设备一律追加到末尾：
  /// [BleController.scan] 回吐的是**按 RSSI 降序**的列表，边搜边渲染时信号一抖动整列表就重排，
  /// 行与行来回跳，用户指头底下那台可能在按下的瞬间换成了别台（误绑）。首见序号一旦分配就不再变，
  /// 列表只增不重排，这才是「下面同步新增已搜出的设备」该有的观感（对齐小程序 applyScanResult）。
  void _applyScanResult(int seq, List<ScanResult> list) {
    if (!mounted || seq != _scanSeq) {
      return;
    }
    for (final result in list) {
      _scanOrder.putIfAbsent(
        result.device.remoteId.str,
        () => _scanOrder.length,
      );
      // WiFi 版：首次见到这台就查规格（每台只查一次）
      final wifi = _wifiMatchOf(result);
      if (wifi != null) {
        _lookupWifiProduct(wifi.wifiDeviceNo);
      }
    }
    final ordered = [...list]
      ..sort(
        (a, b) => (_scanOrder[a.device.remoteId.str] ?? 0).compareTo(
          _scanOrder[b.device.remoteId.str] ?? 0,
        ),
      );
    setState(() {
      _results = ordered;
      // 搜到第一台就切到发现页开始显示列表（雷达仍在转、扫描仍在继续），不必等满窗口。
      if (_scanning && ordered.isNotEmpty) {
        _stage = _Stage.found;
      }
    });
  }

  /// 立刻结束搜索但**保留已搜到的列表**（与 [_cancelScan] 不同，后者还会退出本页）。
  ///
  /// 两个入口：① 用户点「停止搜索」；② 搜索还没结束就点了「立即绑定」——此时必须先停扫再连：
  ///   · 扫描与连接抢同一路射频，边扫边连本就是「连不上」的主因之一；
  ///   · seq 自增后在途扫描的结果不再回写列表，用户选中的那台不会在连接过程中被新搜到的设备挤动。
  /// 必须 **await**：[FrameBleClient.connect] 自己不等扫描停下，没停干净就连
  /// 等于让连接去和自己的扫描抢射频（`_bind` 因此 await 本方法再 connect）。
  Future<void> _stopScanForBind() async {
    if (!_scanning) {
      return;
    }
    _scanSeq++; // 使在途扫描的增量与最终结果失效
    setState(() {
      _scanning = false;
      _stage = _results.isEmpty ? _Stage.notFound : _Stage.found;
    });
    await _ble.stopScan();
    // `_ble.stopScan()` 已等 Dart 扫描任务与原生 stopScan 收网；再沉淀一小会儿，
    // 对齐小程序 whenScanStopped，避免 Android 扫描与 GATT 建连抢同一路射频。
    // 自动重连路径用的是同一个常量（见 `FrameBleClient.settleAfterScan`），改一处即两端生效。
    await FrameBleClient.settleAfterScan();
  }

  /// 「取消搜索」：停扫并退出绑定流程（对齐小程序 `bind.js cancelScan`）。
  /// 不停扫就走，20s 窗口会在后台继续占着射频，妨碍下一次进来重扫。
  void _cancelScan() {
    _scanSeq++;
    _scanning = false;
    _ble.stopScan();
    Navigator.maybePop(context);
  }

  /// 把扫描结果构造成发现页的展示项（对齐小程序 `bind.wxml` 的 `nearby-sub`）。
  /// 第二行（2026-10-27 同步小程序 main-wifi）：通信类型标签把尺寸包进来（如「蓝牙版·5.89寸」），
  /// 后接电量与「信号」+ 信号格（不再写「强 / 弱」文字）。
  ///   · 蓝牙版：尺寸按广播名匹配产品、取后台配置的 sizeModel，匹配不到或没配显示「--寸」；电量取自广播厂商数据；
  ///   · WiFi 版：尺寸来自 getProductByDevice（查询中显示小圆圈 loading / 查不到为「未知设备」），广播里没有电量；
  ///     设备ID 显示广播名里解析出的 12 位 deviceNo 加冒号。
  BindDeviceEntry _entryOf(ScanResult result) {
    final scanName =
        '${result.device.platformName} ${result.advertisementData.advName}';
    final l10n = AppL10n.of(context);
    final bars = rssiToBars(result.rssi);
    final wifi = _wifiMatchOf(result);
    if (wifi != null) {
      final lookup = _wifiLookups[wifi.wifiDeviceNo] ?? const _WifiLookup.loading();
      final product = lookup.product;
      final size = (product?['sizeModel'] ?? '').toString();
      final code = canonicalDeviceSerial(wifi.wifiDeviceNo);
      return BindDeviceEntry(
        id: result.device.remoteId.str,
        name: BleController.displayName(result),
        subtitle: '',
        deviceId: code.isNotEmpty ? code : wifi.wifiDeviceNo,
        thumbAsset: DeviceThumb.ofScanName(scanName),
        wifi: true,
        specLoading: lookup.loading,
        specUnknown: !lookup.loading && product == null,
        sizeText: lookup.loading
            ? ''
            : product == null
            ? l10n.wifiUnknownDevice
            : (size.isNotEmpty ? size : l10n.bindSizeUnknown),
        signalBars: bars,
      );
    }
    final sizeModel = ProductBroadcastId.sizeModelOfScan(
      scanName,
      _productSizeModels,
    );
    final battery = BleController.batteryOf(result);
    return BindDeviceEntry(
      id: result.device.remoteId.str,
      name: BleController.displayName(result),
      subtitle: '',
      deviceId: _displayDeviceCode(result),
      // 设备图按本次广播名区分机型（name 与广播包里的 advName 都看，与扫描白名单同口径）。
      thumbAsset: DeviceThumb.ofScanName(scanName),
      sizeText: sizeModel.isNotEmpty ? sizeModel : l10n.bindSizeUnknown,
      batteryText: battery != null ? l10n.bindBatteryLabel(battery) : '',
      signalBars: bars,
    );
  }

  /// 这台是不是 WiFi 版：广播名按后台 `*` 模板（产品列表 broadcastId）或内置 `IJ_*` 命中，带出 12 位 deviceNo。
  WifiMatch? _wifiMatchOf(ScanResult result) => BroadcastMatch.wifiMatch(
    [result.device.platformName, result.advertisementData.advName],
    [for (final product in _productSizeModels) product.broadcastId],
  );

  /// 按 12 位 deviceNo 查 WiFi 产品规格。同一次搜索每台只查一次（边搜边显示会反复回调同一台）；
  /// 查不到 / 失败 / 超时一律按「未知设备」，不重试。
  void _lookupWifiProduct(String deviceNo) {
    final lookups = _wifiLookups;
    if (deviceNo.isEmpty || lookups.containsKey(deviceNo)) {
      return;
    }
    lookups[deviceNo] = const _WifiLookup.loading();
    BoltFoxApi.lookupProductByDevice(deviceNo)
        .catchError((Object error) => (product: null, reason: '查询出错：$error'))
        .then((result) {
          final product = result.product;
          debugPrint(
            '[WiFi规格查询] $deviceNo '
            '${product != null ? '查到 sizeModel=${product['sizeModel']}' : result.reason}',
          );
          lookups[deviceNo] = _WifiLookup.done(product, result.reason);
          // 页面已销毁，或已重新搜索（本条属于上一轮）
          if (mounted && identical(lookups, _wifiLookups)) {
            setState(() {});
          }
        });
  }

  /// 选中 WiFi 设备后按「立即配网」：规格查到才进配网；未知设备直接弹窗拦下，不进入配网。
  /// 配网第一步就是蓝牙连上设备：在本页连，连上才进 WiFi 列表页（同一会话留给列表页扫 WiFi、
  /// 配网状态页下发参数复用）；连不上就停在本页提示，可直接再点重试。与蓝牙版同样先停扫、等射频安静再连。
  Future<void> _openWifiProvision(ScanResult result, WifiMatch wifi) async {
    if (_wifiConnecting) {
      return;
    }
    final l10n = AppL10n.of(context);
    final lookup = _wifiLookups[wifi.wifiDeviceNo];
    if (lookup == null || lookup.loading) {
      _toast(l10n.wifiLookingUp);
      return;
    }
    final product = lookup.product;
    if (product == null) {
      // 未知设备：正式包只给「未知设备，请联系客服开通」，联调包带上没查到的原因
      await showAppNoticeDialog(
        context,
        title: l10n.wifiUnknownDeviceTip,
        message: kReleaseMode ? null : (lookup.reason.isNotEmpty ? lookup.reason : '没有查询结果'),
        icon: Icons.info_outline_rounded,
      );
      return;
    }
    _wifiConnecting = true;
    await _stopScanForBind();
    if (!mounted) {
      return;
    }
    final remoteId = result.device.remoteId.str;
    AppLoadingDialog.show(context, l10n.bindConnecting);
    try {
      await Blufi.connect(remoteId);
    } catch (error) {
      debugPrint('[WiFi配网] 蓝牙连接设备失败 $remoteId $error');
      AppLoadingDialog.hide(context);
      _wifiConnecting = false;
      if (mounted) {
        _toast(l10n.wifiConnectDeviceFailed);
      }
      return;
    }
    AppLoadingDialog.hide(context);
    _wifiConnecting = false;
    if (!mounted) {
      return;
    }
    // 配网要用的设备信息走内存交接（BLE 句柄、不带冒号的 deviceNo、查到的产品），不进路由
    final size = (product['sizeModel'] ?? '').toString();
    WifiProvision.setTarget(
      WifiProvisionTarget(
        bleRemoteId: remoteId,
        deviceNo: wifi.wifiDeviceNo,
        name: BleController.displayName(result),
        spec: size.isNotEmpty ? size : l10n.bindSizeUnknown,
        productId: (product['productId'] ?? '').toString(),
        productName: (product['productName'] ?? '').toString(),
      ),
    );
    // 已连上设备 → 进 WiFi 列表页让设备扫描附近 WiFi → 选中后进账号密码页
    await Navigator.of(context).push<void>(
      AppPageRoute(builder: (_) => WifiListPage(state: widget.state)),
    );
  }

  /// 展示用「设备ID」：只取本次广播厂商数据里的完整 6 字节 Device_ID，按原顺序带冒号展示
  /// （如 `37:0B:00:D0:44:5A`），与设备详情页（连上后 0x01 读到的值）一致；安卓、iOS 同一来源。
  ///
  /// 取不到合法的完整 6 字节时统一显示 `--`（2026-10-22 同步小程序 `bind.js displayDeviceCode`）。
  /// 不再拿系统给的 `remoteId` 兜底：
  ///   · 安卓的 `remoteId` 是手机系统给的蓝牙地址，字节序与设备ID相反（EB-169 实测：
  ///     设备ID 37:0B:00:D0:44:5A，系统地址 5A:44:D0:00:0B:37），显示出来就是错的；
  ///   · iOS 的 `remoteId` 是手机生成的随机 UUID，与设备无关。
  ///
  /// 为什么要展示：默认设备名 = 产品广播名，同型号设备必然重名，绑定前这是唯一能把两台区分开的标识。
  /// 展示不等于身份：判重、认领会话、绑定入库一律仍只认连上后 0x01 读到的完整 ID。
  static String _displayDeviceCode(ScanResult result) {
    final id = canonicalDeviceSerial(
      BleController.advertisingOf(result)?.deviceId,
    );
    return id.isEmpty ? '--' : id;
  }

  /// 蓝牙未开启 / 权限未授予时的引导弹窗：给一个「去设置 / 去打开蓝牙」的直达按钮
  /// （接 [NativeDeviceApi.openBluetoothSettings] / [NativeDeviceApi.openAppSettings]，
  ///  二者在 Android 侧已实现）。对齐小程序 showPermissionGuide 的明确引导，而非模糊 toast。
  Future<void> _showBluetoothGuide({
    required String title,
    required String message,
    required String actionLabel,
    required Future<void> Function() onAction,
  }) async {
    if (!mounted) {
      return;
    }
    final go = await showAppConfirmDialog(
      context,
      title: title,
      message: message,
      icon: Icons.bluetooth_disabled_rounded,
      confirmLabel: actionLabel,
    );
    if (go != true) {
      return;
    }
    try {
      await onAction();
    } catch (_) {
      // 打开系统设置失败不阻断（如 iOS 通道未实现），用户可手动去设置。
    }
  }

  /// 绑定当前选中设备（按 id），完整对齐小程序 `bind.js bindById`：
  /// 连接读信息 → 判重（已绑定则复用不新建）→ 绑定 → 回填选中 → 延时返回。
  Future<void> _bind(String id) async {
    if (_binding) {
      return; // 绑定进行中，忽略重复点击，避免重复绑定
    }
    // WiFi 版不走蓝牙绑定：查规格 → 进 WiFi 配网（蓝牙版下面的流程一行没动）
    final selectedIndex = _results.indexWhere((r) => r.device.remoteId.str == id);
    if (selectedIndex >= 0) {
      final wifi = _wifiMatchOf(_results[selectedIndex]);
      if (wifi != null) {
        await _openWifiProvision(_results[selectedIndex], wifi);
        return;
      }
    }
    // _binding 必须在**任何 await 之前**同步置起：下面 await 停扫期间按钮照样点得动，
    // 晚一步置起就等于给连点留了一个空窗（与 AI 发送那处同款病灶，见 ai_chat_page 的 _guardedSend）。
    setState(() => _binding = true);
    // 搜索中直接点绑定：先停扫**并等它真停下**再连（见 [_stopScanForBind]）。
    await _stopScanForBind();
    if (!mounted) {
      return;
    }
    final index = _results.indexWhere((r) => r.device.remoteId.str == id);
    if (index < 0) {
      setState(() => _binding = false); // 选中项已不在列表（列表刷新过），放开按钮让用户重选
      return;
    }
    final result = _results[index];

    // 真机设备：先连接读取真实信息（电量/播放/屏幕/固件），连接失败则中止绑定（无模拟兜底）。
    // Bug19：全程只保留这一个 loading，直到跳转设备列表前一刻才 hide——
    // 原实现连接成功后就 hide，随后的绑定网络请求（判重/上报/回查）+ 固定 800/500ms 延时全程无指示，
    // 观感就是「绑定中的框都没了还没跳转」。这里改为连接→绑定全程覆盖、跳转即消失。
    AppLoadingDialog.show(context, AppL10n.of(context).bindConnecting);
    try {
      final error = await _ble.connect(result);
      if (!mounted) {
        return;
      }
      if (error != null) {
        AppLoadingDialog.hide(context);
        setState(() => _binding = false);
        // error 已是 BleController 本地化好的友好文案（如「连接失败，请靠近设备后重试」），
        // 直接展示——不再套「设备连接失败：」前缀，也不把 android-code:133 等原始异常抛给用户。
        _toast(error);
        return;
      }
      // 连接读信息成功：不再 hide、也不再 800ms 停留，直接进入绑定（loading 继续覆盖）。

      final info = _ble.info;
      // 稳定设备身份只允许使用固件 0x01 返回的完整 6 字节 Device_ID。
      // 广播 4 字节短 ID 与 BLE remoteId 都只是本次连接的候选/句柄，不得绑定入库。
      final serial = canonicalDeviceSerial(info?.deviceId);
      if (serial.isEmpty) {
        AppLoadingDialog.hide(context);
        await _ble.disconnect();
        if (!mounted) {
          return;
        }
        setState(() => _binding = false);
        _toast(AppL10n.of(context).bleIncompleteDeviceIdentity);
        return;
      }
      final name = BleController.displayName(result);
      final serials = <String>[serial];
      // 本机屏幕类型码（优先固件 0x01 读到的，其次广播）：判重时按型号一票否决，
      // 防广播 4 字节与后端 6 字节偶合，把新设备(如 3.7寸)误判成已绑定的别台(如 5.89寸)而不新建绑定。
      final scannedScreen = info?.screenType ?? _ble.broadcastScreenType;

      // 绑定判重（移植小程序 bind.js findBoundDevice）：只用 0x01 完整 6 字节 ID
      // 与后端完整 ID 精确比对。已绑定的不再新建记录，广播短 ID 不参与判重。
      // 先尽力刷新一次列表再判；刷新失败沿用本地列表，不把老设备误判成新设备。
      await widget.state.refreshDevices();
      if (!mounted) {
        return;
      }
      final existed = _findBound(serials, scannedScreen);
      if (existed != null) {
        // 已绑定：复用该记录并设为当前选中（沿用刚建立的连接 = 已连接）。
        // 保持 binding=true 直到返回上一页，避免 500ms 窗口内被重复点击触发二次操作。
        widget.state.selectDevice(existed.id);
        widget.state.reconcileConnectionFlags();
        // 跳转前一刻关掉 loading，随即返回设备列表（去掉原 500ms 固定延时）。
        // 不再弹「该设备已绑定，已为你连接」：按反馈去掉已绑定/已连接/直接连接这类成功提示，静默返回列表。
        AppLoadingDialog.hide(context);
        Navigator.of(context).maybePop();
        return;
      }

      // 上报后端绑定：productId 由 state.bindDevice 内部拉产品列表按机型匹配解析（对齐小程序 api.bindDevice），
      // 这里把扫描到的型号/屏幕/名称传过去供匹配打分。
      final feedback = await widget.state.bindDevice(
        productName: name,
        productSerialNo: serial,
        model: BleController.modelOf(result),
        screen: BleController.screenLabelOf(result),
        scanName: name,
      );
      if (!mounted) {
        return;
      }
      if (!feedback.success) {
        // 绑定失败仍停留在本页：先关 loading，再断开占用的单连接，避免妨碍重试（对齐小程序 disconnect + 停留）。
        AppLoadingDialog.hide(context);
        await _ble.disconnect();
        if (!mounted) {
          return;
        }
        setState(() => _binding = false);
        _toast(feedback.message);
        return;
      }

      // 绑定成功后回查列表（bindDevice 内已 refreshDevices），用硬件序列号找到这条新记录并设为当前选中，
      // 让各页都能按稳定的 userProductId 认出它（对齐小程序绑定成功后回填 userProductId + setSelectedDevice）。
      final persisted = _findBound(serials, scannedScreen);
      if (persisted != null) {
        widget.state.selectDevice(persisted.id);
        // 记住「刚绑定的这台」：设备列表排序的第二优先级（需求第 6 项）。
        unawaited(RecentlyBoundDevice.instance.remember(persisted.id));
      }
      widget.state.reconcileConnectionFlags();
      // 关掉 loading（_binding 保持 true 到本页销毁，防重复点击）。
      AppLoadingDialog.hide(context);
      HapticFeedback.mediumImpact(); // 绑定成功触觉反馈
      // 不再弹「绑定成功」提示（需求第 17 项）：紧接着就要弹命名弹窗，成功 toast 会压在它上面，
      // 且返回设备列表本身就是反馈。
      await _promptRenameAfterBind(persisted?.id ?? '');
      if (!mounted) {
        return;
      }
      Navigator.of(context).maybePop();
    } finally {
      // 兜底收口：mounted 早退/异常路径都不把 canPop:false 的蒙层留在 root 栈上
      //（hide 幂等，上面各分支「跳转前一刻 hide」的时序不受影响）。
      AppLoadingDialog.hide(context);
    }
  }

  /// 新绑定成功后在**当前页**引导命名（需求第 1 项：弱性强制）。
  ///
  /// 交互：绑定成功 → 弹出带默认名称的设备名称编辑弹窗 → 点「保存」写回后端 →
  /// 再按原逻辑返回上一页。点「稍后」/点遮罩则直接沿用默认名返回，不阻断绑定。
  /// 已绑定设备的复用路径**不进入这里**，避免每次重连都要求改名（对齐小程序 bind.js）。
  ///
  /// 拿不到后端记录主键（回查失败）时静默跳过：没有 id 就没法调改名接口，
  /// 弹一个注定保存失败的框只会让用户以为绑定出了问题。
  Future<void> _promptRenameAfterBind(String userProductId) async {
    if (!mounted || userProductId.isEmpty) {
      return;
    }
    final l10n = AppL10n.of(context);
    final bound = widget.state.deviceById(userProductId);
    final current = bound.name;
    final name = await showDeviceNameDialog(
      context,
      initialValue: current,
      title: l10n.devBindNameTitle,
      cancelLabel: l10n.devBindNameLater,
      // 与之后「我的设备」里显示的同一张：刚绑定记录按所属产品算出的图。
      thumbAsset: bound.thumbAsset,
    );
    if (!mounted || name == null || name == current) {
      return;
    }
    // 保存中 loading（同「我的设备」/详情页两个改名入口，需求第 16 项）。
    AppLoadingDialog.show(context, l10n.saving);
    final ActionFeedback feedback;
    try {
      feedback = await widget.state.renameDevice(userProductId, name);
    } finally {
      AppLoadingDialog.hide(context);
    }
    if (!mounted || feedback.success) {
      return;
    }
    // 改名失败不回滚绑定：设备已经绑上了，只提示改名没成功，用户可在设备页重试。
    _toast(feedback.message);
  }

  /// 在已绑定设备列表里按完整 6 字节 ID 精确匹配 + 型号一票否决，
  /// 找出这台已绑定记录（无则 null）。
  DeviceItem? _findBound(List<String> serials, int scannedScreen) {
    final completeSerials = serials.where(isCompleteDeviceSerial).toList();
    if (completeSerials.isEmpty) {
      return null;
    }
    for (final device in widget.state.devices) {
      if (!sameScreenCode(scannedScreen, device.screenCode)) {
        continue;
      }
      if (completeSerials.any(
        (serial) => verifiedDeviceSerialMatch(serial, device.serialNumber),
      )) {
        return device;
      }
    }
    return null;
  }

  void _toast(String message) {
    AppToast.warn(context, message);
  }

  @override
  Widget build(BuildContext context) {
    switch (_stage) {
      case _Stage.permission:
        // 权限确认中的安静占位页：只有导航栏与背景，系统授权框单独呈现，
        // 不与「正在搜索」的雷达动画同屏。
        return FigmaScreen(
          title: AppL10n.of(context).bindDeviceTitle,
          scrollable: false,
          body: const SizedBox.expand(),
        );
      case _Stage.scanning:
        // 还没搜到任何一台的空窗期：整页雷达 + 「正在搜索」。搜到第一台就切到 found 页
        // （雷达继续转 + 列表同步追加），不再整段扫描期都停在这一页。
        return BindDeviceSearching(onCancel: _cancelScan);
      case _Stage.notFound:
        return BindDeviceNotFound(onRetry: _startScan);
      case _Stage.found:
        return BindDeviceFound(
          entries: [for (final result in _results) _entryOf(result)],
          scanning: _scanning,
          onStopScan: _stopScanForBind,
          onRefresh: _startScan,
          onBindId: _bind,
          // 长按某台设备进入硬件联调调试台（调试台自行扫描连接，此处仅提供进入入口）。
          onDebugId: (_) =>
              Navigator.of(context).pushNamed<void>(AppRoutes.bleDebug),
        );
    }
  }
}
