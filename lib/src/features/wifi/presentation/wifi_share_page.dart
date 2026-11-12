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
import '../wifi_share_card.dart';
import '../wifi_wechat_share.dart';

/// WiFi 版共享设备列表（2026-10-29，同小程序 `subpackages/device/wifi-share`）。入口：WiFi 详情「共享设备」（2026-11-05 起所有者与接收者都能进）。
///   · 接收者（2026-11-05，同小程序）：内容与所有者一致（所有者栏 + 已分享成员），没有底部「分享设备」；
///     身份进页面时按 getUserProductDetail（isToHave / shareUserId，[wifiIsOwner]）自己查，查不到按加载失败；
///     列表里没有所有者那条时接收者不拿自己兜底（所有者栏不显示）。
///     成员列表里接收者自己那行（成员 userProductId = 本人记录）在原「移除」位置显示灰字「我」（该行能解绑时显示「移除」）。
///   · 「移除」（2026-11-05 起后端控制，同小程序）：成员接口每条带 isCanDel，== 1 才显示、才能移除（[WifiShareMember.canDel]），
///     不再按所有者 / 接收者判断。移除的是自己（接收者解绑自己）时走 [PhotoFrameState.deleteDevice] 清本机记录，提示后回首页。
///   · 第一栏固定所有者（头像 + 昵称 + 身份），橙色底与接收者区分；下面是接收者（头像 + 昵称 + 加入时间 + 移除）；
///   · 底部「分享设备」：把小程序接受页卡片发到微信会话（简化版，无邀请码，见 [WifiWeChatShare]），
///     对方在小程序里接受。拿不到自己的 userId / 产品 ID，或没配置小程序原始 ID 时按钮置灰、点了提示；
///     分享这一刻取服务器时间戳写进卡片 t（2026-11-04 分享链接有效期，小程序接受页校验），取不到不发卡片；
///     卡片封面（2026-11-04 同小程序）由 [WifiShareCard] 画（邀请标签 + 设备图 + 设备名 / 规格 + 接受按钮），画不出来用设备图；
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
  bool _isOwner = false;
  WifiShareMember? _owner;
  List<WifiShareMember> _members = const [];

  DeviceItem get _device => widget.state.deviceById(widget.deviceId);

  UserProfile get _user => widget.state.currentUser;

  bool get _canShare =>
      _isOwner &&
      WifiWeChatShare.configured && _user.userId.isNotEmpty && _device.productId > 0 && _device.serialNumber.isNotEmpty;

  /// 「分享设备」置灰的原因（2026-11-12 排查「点了提示暂时无法分享」）：逐条对应 [_canShare] 的条件，
  /// 进页面加载完与点按钮时写进联调日志。
  List<String> _shareBlockers() => [
    if (!_isOwner) '不是所有者',
    if (WifiWeChatShare.miniProgramUserName.trim().isEmpty)
      '打包没配小程序原始ID（--dart-define=WECHAT_MINI_PROGRAM_USERNAME=gh_…）',
    if (!WifiWeChatShare.configured && WifiWeChatShare.miniProgramUserName.trim().isNotEmpty) '当前平台不支持微信分享',
    if (_user.userId.isEmpty) '取不到当前用户 userId',
    if (_device.productId <= 0) '设备没有产品ID（productId=${_device.productId}）',
    if (_device.serialNumber.isEmpty) '设备没有设备号（serialNumber 为空）',
  ];

  void _logShareState() {
    final blockers = _shareBlockers();
    debugPrint(
      blockers.isEmpty
          ? '[WiFi分享] 可以分享 设备 ${_device.serialNumber} 产品 ${_device.productId} 用户 ${_user.userId}'
          : '[WiFi分享] 分享按钮置灰：${blockers.join('；')}',
    );
  }

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
    // 身份按设备详情判断（同小程序 wifiShare.isOwner）；查不到不猜，按加载失败处理
    bool? owner;
    try {
      final data = await BoltFoxApi.getUserProductDetail(userProductId: widget.deviceId);
      if (data is Map) {
        owner = wifiIsOwner(data.map((k, v) => MapEntry(k.toString(), v)));
      }
    } catch (error) {
      debugPrint('[WiFi分享] 所有者查询失败 $error');
    }
    if (owner == true && _user.userId.isEmpty) {
      await widget.state.refreshCurrentUser();
    }
    List<Map<String, dynamic>>? rows;
    if (owner != null) {
      try {
        rows = extractApiRows(await BoltFoxApi.getShareUserProductList(deviceId: _device.serialNumber));
      } catch (error) {
        debugPrint('[WiFi分享] 成员列表查询失败 $error');
        rows = null;
      }
    }
    if (!mounted) {
      return;
    }
    if (owner == null || rows == null) {
      setState(() {
        _loading = false;
        _loadError = true;
      });
      return;
    }
    final user = _user;
    final split = wifiSplitMembers(
      rows,
      owner ? WifiShareMember(id: widget.deviceId, name: user.nickname, avatar: user.avatarUrl, joinedAt: '') : null,
    );
    setState(() {
      _loading = false;
      _isOwner = owner;
      _owner = split.owner;
      _members = split.members;
    });
    debugPrint('[WiFi分享] 身份 ${owner ? '所有者' : '接收者'}，成员 ${split.members.length} 人');
    if (owner) {
      _logShareState();
    }
  }

  /// 接收者自己那行：成员 userProductId = 本人这条记录（所有者那栏不标「我」）。
  bool _isMe(WifiShareMember member) => !_isOwner && member.id.isNotEmpty && member.id == widget.deviceId;

  Future<void> _remove(WifiShareMember member) async {
    if (_busy || !member.canDel) {
      return;
    }
    final l10n = AppL10n.of(context);
    final isMe = _isMe(member);
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.wifiShareRemoveTitle,
      message: isMe ? l10n.wifiShareRemoveSelfMessage : l10n.wifiShareRemoveMessage(member.name.isNotEmpty ? member.name : '--'),
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
      if (isMe) {
        // 解绑的是自己：走 state.deleteDevice，连同本机设备列表 / 缓存一起清掉
        final feedback = await widget.state.deleteDevice(member.id);
        if (!feedback.success) {
          failure = feedback.message;
        }
      } else {
        await BoltFoxApi.delUserProduct(member.id);
      }
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
      final message = failure is ApiException ? failure.message : (failure is String ? failure : '');
      AppToast.warn(context, message.isNotEmpty ? message : l10n.wifiShareFailed);
      return;
    }
    AppToast.show(context, l10n.wifiShareRemoved);
    if (isMe) {
      // 设备已不在自己名下，留在这页（和下面的详情页）只会加载失败：回首页
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    await _load();
  }

  Future<void> _share() async {
    final l10n = AppL10n.of(context);
    if (!_isOwner) {
      return;
    }
    if (!_canShare) {
      _logShareState();
      AppToast.warn(context, l10n.wifiShareUnavailable);
      return;
    }
    if (_busy) {
      return;
    }
    _busy = true;
    try {
      if (!await WifiWeChatShare.isWeChatInstalled()) {
        debugPrint('[WiFi分享] 微信未安装或 SDK 注册失败');
        if (mounted) {
          AppToast.warn(context, l10n.wifiShareNoWeChat);
        }
        return;
      }
      // 分享这一刻取服务器时间戳写进卡片 t（2026-11-04 分享链接有效期，同小程序）；取不到不发卡片——
      // 小程序接受页对不带 t 的卡片一律显示「分享链接无效」。
      String? shareTime;
      try {
        shareTime = wifiShareTime(await BoltFoxApi.getCurrentTime());
      } catch (error) {
        debugPrint('[WiFi分享] 获取服务器时间戳失败 $error');
      }
      if (shareTime == null) {
        debugPrint('[WiFi分享] 取不到服务器时间戳（getCurrentTime），不发卡片');
        if (mounted) {
          AppToast.warn(context, l10n.wifiShareUnavailable);
        }
        return;
      }
      final device = _device;
      final user = _user;
      // 卡片封面（2026-11-04 同小程序）：画一张 5:4 的邀请封面；画不出来 / 超出微信大小上限时用设备图，不用页面截图
      final cover = await WifiShareCard.render(
        name: device.name,
        spec: device.sizeModel.trim().isNotEmpty ? '${l10n.wifiBadge} · ${device.sizeModel.trim()}' : l10n.wifiBadge,
        tag: l10n.wifiShareCardTag,
        button: l10n.wifiShareCardButton,
        thumbAsset: device.thumbAsset,
      );
      if (!mounted) {
        return;
      }
      final ok = await WifiWeChatShare.shareMiniProgram(
        cover: cover,
        path: WifiShareLink.acceptPath(
          deviceId: device.serialNumber,
          productId: device.productId,
          ownerUserId: user.userId,
          deviceName: device.name,
          ownerName: user.nickname,
          shareTime: shareTime,
        ),
        title: l10n.wifiShareCardTitle(user.nickname, device.name),
      );
      debugPrint('[WiFi分享] 拉起微信${ok ? '成功' : '失败'}');
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
                        if (member.canDel)
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
                          )
                        else if (_isMe(member))
                          // 接收者自己那行：原「移除」位置的「我」（只是标记，不可点；同小程序 .share-me）
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 5),
                            child: Text(
                              l10n.wifiShareMe,
                              style: const TextStyle(color: Color(0xFF8B9098), fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // 底部「分享设备」与提示只给所有者（2026-11-05，同小程序：接收者没有分享设备按钮）
          if (_isOwner) ...[
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
          ],
          const SizedBox(height: 24),
        ],
      );
    }
    return FigmaScreen(title: l10n.wifiSharedDevice, body: body);
  }
}
