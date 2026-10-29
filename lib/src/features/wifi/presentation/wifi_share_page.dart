import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../network/api_exception.dart';
import '../../../network/api_rows.dart';
import '../../../network/boltfox_api.dart';
import '../../../shared/l10n/app_l10n.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/app_widgets.dart';
import '../../../shared/widgets/figma_common.dart';
import '../../../state.dart';
import '../wifi_l10n.dart';
import '../wifi_share.dart';
import '../wifi_wechat_share.dart';

/// WiFi 版分享列表（2026-10-29，同小程序 `subpackages/device/wifi-share`）。入口：WiFi 详情「分享设备」（仅所有者）。
///   · 第一栏固定所有者（头像 + 昵称 + 身份），橙色底与接收者区分；下面是接收者（头像 + 昵称 + 加入时间 + 移除）；
///   · 底部「分享设备」：把小程序接受页卡片发到微信会话（简化版，无邀请码，见 [WifiWeChatShare]），
///     对方在小程序里接受。拿不到自己的 userId / 产品 ID，或没配置小程序原始 ID 时按钮置灰、点了提示；
///   · 移除：二次确认后 delUserProduct 删成员那条记录（服务端口径：成员即失去设备），再刷新列表。
/// 数据：老服务 getShareUserProductList（按后端设备号）；服务端暂无加入时间字段，显示「--」。
class WifiSharePage extends StatefulWidget {
  const WifiSharePage({super.key, required this.state, required this.deviceId});

  final PhotoFrameState state;
  final String deviceId;

  @override
  State<WifiSharePage> createState() => _WifiSharePageState();
}

class _WifiSharePageState extends State<WifiSharePage> {
  bool _loading = true;
  bool _loadError = false;
  bool _busy = false;
  WifiShareMember? _owner;
  List<WifiShareMember> _members = const [];

  DeviceItem get _device => widget.state.deviceById(widget.deviceId);

  UserProfile get _user => widget.state.currentUser;

  bool get _canShare =>
      WifiWeChatShare.configured && _user.userId.isNotEmpty && _device.productId > 0 && _device.serialNumber.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = false;
    });
    if (_user.userId.isEmpty) {
      await widget.state.refreshCurrentUser();
    }
    List<Map<String, dynamic>>? rows;
    try {
      rows = extractApiRows(await BoltFoxApi.getShareUserProductList(deviceId: _device.serialNumber));
    } catch (error) {
      debugPrint('[WiFi分享] 成员列表查询失败 $error');
      rows = null;
    }
    if (!mounted) {
      return;
    }
    if (rows == null) {
      setState(() {
        _loading = false;
        _loadError = true;
      });
      return;
    }
    final user = _user;
    final split = wifiSplitMembers(
      rows,
      WifiShareMember(id: widget.deviceId, name: user.nickname, avatar: user.avatarUrl, joinedAt: ''),
    );
    setState(() {
      _loading = false;
      _owner = split.owner;
      _members = split.members;
    });
  }

  Future<void> _remove(WifiShareMember member) async {
    if (_busy) {
      return;
    }
    final l10n = AppL10n.of(context);
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.wifiShareRemoveTitle,
      message: l10n.wifiShareRemoveMessage(member.name.isNotEmpty ? member.name : '--'),
      iconAsset: 'assets/images/device-detail-icon06.png',
      icon: Icons.person_remove_outlined,
      tone: AppDialogTone.danger,
      confirmLabel: l10n.wifiShareRemove,
    );
    if (confirmed != true || !mounted) {
      return;
    }
    _busy = true;
    AppLoadingDialog.show(context, l10n.wifiShareRemoving);
    Object? failure;
    try {
      await BoltFoxApi.delUserProduct(member.id);
    } catch (error) {
      failure = error;
    } finally {
      AppLoadingDialog.hide(context);
      _busy = false;
    }
    if (!mounted) {
      return;
    }
    if (failure != null) {
      AppToast.warn(context, failure is ApiException && failure.message.isNotEmpty ? failure.message : l10n.wifiShareFailed);
      return;
    }
    AppToast.show(context, l10n.wifiShareRemoved);
    await _load();
  }

  Future<void> _share() async {
    final l10n = AppL10n.of(context);
    if (!_canShare) {
      AppToast.warn(context, l10n.wifiShareUnavailable);
      return;
    }
    if (_busy) {
      return;
    }
    _busy = true;
    try {
      if (!await WifiWeChatShare.isWeChatInstalled()) {
        if (mounted) {
          AppToast.warn(context, l10n.wifiShareNoWeChat);
        }
        return;
      }
      final device = _device;
      final user = _user;
      final ok = await WifiWeChatShare.shareMiniProgram(
        path: WifiShareLink.acceptPath(
          deviceId: device.serialNumber,
          productId: device.productId,
          ownerUserId: user.userId,
          deviceName: device.name,
          ownerName: user.nickname,
        ),
        title: l10n.wifiShareCardTitle(user.nickname, device.name),
      );
      if (!ok && mounted) {
        AppToast.warn(context, l10n.wifiShareFailed);
      }
    } catch (error) {
      debugPrint('[WiFi分享] 分享失败 $error');
      if (mounted) {
        AppToast.warn(context, l10n.wifiShareFailed);
      }
    } finally {
      _busy = false;
    }
  }

  Widget _avatar(String url) {
    Widget fallback() => Image.asset('assets/images/mine-header.jpg', fit: BoxFit.cover);
    return Container(
      width: 44,
      height: 44,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFEEF1F5)),
      child: url.isNotEmpty
          ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover, errorWidget: (context, url, error) => fallback())
          : fallback(),
    );
  }

  Widget _name(String name) => Text(
    name.isNotEmpty ? name : '--',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(color: Color(0xFF2A2D32), fontSize: 15, fontWeight: FontWeight.w600),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final owner = _owner;
    Widget body;
    if (_loading) {
      body = const Padding(padding: EdgeInsets.only(top: 120), child: Center(child: CircularProgressIndicator()));
    } else if (_loadError) {
      body = Padding(
        padding: const EdgeInsets.only(top: 16),
        child: FigmaGlassCard(
          borderRadius: 18,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 36),
          child: Column(
            children: [
              Text(l10n.wifiShareFailed, style: const TextStyle(color: Color(0xFF2A2D32), fontSize: 15)),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _load,
                child: Text(l10n.retry, style: const TextStyle(color: Color(0xFFFF6A20), fontSize: 14)),
              ),
            ],
          ),
        ),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          if (owner != null)
            // 所有者固定第一栏：暖橙底，与下面白色的接收者列表区分
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0x2EFF9140), Color(0x1AFF6A20)]),
                border: Border.all(color: const Color(0x47FF6A20)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  _avatar(owner.avatar),
                  const SizedBox(width: 12),
                  Expanded(child: _name(owner.name)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFF9140), Color(0xFFFF6A20)],
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      l10n.wifiShareOwner,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          FigmaGlassCard(
            borderRadius: 18,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.wifiShareShared,
                  style: const TextStyle(color: Color(0xFF33373D), fontSize: 14, fontWeight: FontWeight.w700),
                ),
                if (_members.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      l10n.wifiShareEmpty,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF9BA2AD), fontSize: 13),
                    ),
                  ),
                for (final member in _members)
                  SizedBox(
                    height: 64,
                    child: Row(
                      children: [
                        _avatar(member.avatar),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _name(member.name),
                              const SizedBox(height: 4),
                              Text(
                                l10n.wifiShareJoinedAt(member.joinedAt.isNotEmpty ? member.joinedAt : '--'),
                                style: const TextStyle(color: Color(0xFF8B9098), fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _remove(member),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0x66FF3045)),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              l10n.wifiShareRemove,
                              style: const TextStyle(color: Color(0xFFFF3045), fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Opacity(
            opacity: _canShare ? 1 : 0.5,
            child: GestureDetector(
              onTap: _share,
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
                  l10n.wifiShareDevice,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.wifiShareTip,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF8B9098), fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 24),
        ],
      );
    }
    return FigmaScreen(title: l10n.wifiShareDevice, body: body);
  }
}
