# main-wifi：WiFi 版 TF 卡本地模式、设备详情改版、简化版分享对齐小程序

> 类型：Historical Implementation Record
> 日期：2026-10-29；环境：远程 SSH 服务器；分支：main-wifi
> 对应小程序：`photo-album` main-wifi e4e1372 / 39fefd0 / 564e4b3 / a8ce496（2026-10-29：前端对接变更说明 TF 卡本地播放、详情改版、投屏进度页图标、简化版设备分享、服务端分享答复）

## 改动

### 状态：本地模式

- `WifiOnlineStatus` 加 `local`：`status=LOCAL_TF` →「本地模式」（紫色，首页卡 / 我的设备卡 / 详情同一套）。按对接说明一.4，**不认识的状态值按「状态未知」**（原按 online 回退）；缺 `status` 仍按 online 回退。
- 本地模式下投屏、轮播设置、TF卡、轮播页「保存」按钮可点，只提示「当前设备状态：本地模式，请恢复设备网络再试」；设备信息、休眠、消息、分享、解绑、删除照常。WiFi 版暂无 OTA 入口。
- 新增 `wifiProjectBlockedTip`（投屏严格口径：离线 / 本地模式 / 查不到 →「设备不在线」，休眠 / 关机沿用原提示）、`wifiQueryBlockedTip`（保存前查，查不到交给接口）、`filterPickableDevices`（选设备列表过滤）。

### 投屏入口

| 位置 | 处理 |
|---|---|
| 官方图库、AI 对话的选设备弹层 | 离线 / 本地模式 / 状态未知的 WiFi 版不进列表；一台都没有提示「暂无可投屏的电子纸设备」 |
| AI 对话选 WiFi 版 | 原未接（会去连蓝牙）；现同官方图库：不连蓝牙、确认在线后进预览，不做蓝牙电量提醒 |
| 我的相册再次投屏 | 离线 / 本地模式 / 状态未知提示「设备不在线」；删除不受影响 |
| 投屏预览页「开始投屏」 | WiFi 版再查一次状态，同上口径 |
| 轮播设置页「保存」 | 保存前查状态，本地模式 / 离线 / 休眠 / 关机直接提示 |
| 我的设备 WiFi 卡「投屏」「轮播设置」 | 本地模式提示同上（「轮播设置」入口收到 `openWifiSlideshow`） |

### WiFi 设备详情改版

- 布局：设备卡（状态 + 电量同栏，电量仅在线）→「投屏 | 轮播设置」→ 功能栏 → 页底「删除设备」。
- 功能栏：设备信息（新页 `wifi_device_info_page.dart`：WiFi信号 / WiFi名称 / 最后上线 / 最后心跳 / 固件版本，去掉国家码）、休眠设置、消息中心、TF卡、分享设备（仅所有者）、解除绑定（红字）。
- 所有者判定：详情页另查 `getUserProductDetail`，`isToHave=1` 是；带 `shareUserId` 的是成员；两者都没有的老记录按所有者。查到前 / 查不到按「否」（不出分享与删除），避免成员误删所有者的云端照片。
- 解除绑定 / 删除设备（`wifi_remove_flow.dart`）：弹窗与蓝牙版同款——解绑一次确认（只删设备记录，照片保留）；删除两道确认（取消 / 继续 → 取消 / 确认），WiFi 版设备端不存图，「先删图片」只处理云端：`clearUserProductImg` → IoT `photo/delete all=true` → `delUserProduct`，任一步失败不删设备。一级确认文案补「已分享的成员也将同时失去这台设备及其照片」（服务端口径：所有者删除连带成员记录与照片；成员只有解绑；解绑不删图）。

### TF 卡

- 详情「TF卡」：未插卡「未插卡」不可点；有卡「已用/总量」（满 1GB 换 GB）+ 箭头；没上报「--」不可点。
- 新页 `wifi_tf_page.dart`（逻辑 `wifi_tf.dart`）：开关「TF卡播放」+ 说明。打开先查设备，在线且插卡才弹二次确认；确认后 `IotApi.playTf` → `WifiCommandResultWaiter` 等 WS `command.result`（`action=play_tf`、按 msgid，推送早于响应也认，30 秒），期间 loading；结果三分支（已切换 / 设备拒绝 result / 超时补查 online，已是本地模式按成功）。错误码 4000 / 4041 / 4045 / 403 有对应提示。开关不存本地，只看状态；关闭只提示到设备上重新入网。本期不做 TF 卡清除。
- 消息类型 `TF_LOCAL_MODE`「设备已进入本地模式」。

### 投屏进度页

- WiFi 投屏结果页中间不再放投屏图片，改为状态图标（同蓝牙版投屏页：`upload-icon01` 进行中 / `03` 全部成功 / `02` 有失败）；多张时下方列表缩略图保留。

### 分享（简化版）

- `BoltFoxApi.addUserProduct` 带 `isToHave` / `shareUserId`，自己绑定（蓝牙 / WiFi 配网）默认 1 / 0；`getUserInfo` 读出数字 `userId`（`UserProfile.userId`，与展示用 `id`=userNo 分开）；新增 `getShareUserProductList`。
- 新页 `wifi_share_page.dart`：所有者固定第一栏（橙色底、「所有者」标签），接收者（头像 / 昵称 / 加入时间 / 移除）；移除二次确认后 `delUserProduct`（成员那条 userProductId）。
- 「分享设备」：App 没有小程序卡片的 `open-type="share"`，改由 fluwx 把**小程序卡片**（`WeChatShareMiniProgramModel`）发到微信会话，路径与小程序分享列表一致（`WifiShareLink.acceptPath`：`d/p/u/n/o`），对方在小程序接受页接受。App 本身没有接受入口（通用链接方案未实施）。
  - 需要 `--dart-define=WECHAT_MINI_PROGRAM_USERNAME=gh_…`（小程序原始 ID，且小程序与 App 须在同一微信开放平台账号下）；**未配置时按钮置灰、点了提示「暂时无法分享」**。低版本微信的兜底网页 `WECHAT_SHARE_WEBPAGE_URL`，默认 `https://badmin.boltfox.cn/`。
  - 已知风险同小程序：无邀请码，卡片被转发即可加入，靠服务端校验。

## 测试

- 新增 `test/wifi_tf_share_test.dart`：本地模式映射 / 未知状态降级 / 本地模式不显示电量、TF 卡文案与错误提示、`command.result` 早到 / 匹配 / 超时、`TF_LOCAL_MODE` 文案、所有者判定、分享列表拆分、卡片路径格式（与小程序 `buildAcceptPath` 同一编码）。
- 本机没有 Flutter 工具链，**未 analyze、未跑测试、未编译、未真机**；请本地 `flutter analyze` + `flutter test`。

## 未同步（小程序同日其它改动）

- 投屏进度条含图片处理阶段（小程序 76487ba）、投屏带产品渲染模式 / 屏幕方向（10-28）未在本轮同步，App 结果页说明仍为「进度为图片上传进度」。
