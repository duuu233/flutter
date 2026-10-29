# main-wifi：补齐与小程序 main-wifi 的剩余差异

> 类型：Historical Implementation Record
> 日期：2026-10-29；环境：远程 SSH 服务器；分支：main-wifi
> 对应小程序：`photo-album` main-wifi 2ea6572 之后、上一轮（[TF 卡本地模式等](2026-10-29-wifi-tf-local-detail-share-sync.md)）之外的全部代码改动：25699db / 5a0be2d（2.4G 提示去掉又恢复，净变化为恢复）、d168bef（renderMode）、5d35774（screenType）、76487ba（进度条含处理阶段）、0d1bc5f（重新配网按钮高度）；以及前两轮记录的「未做 / 差异」。

## 改动

### 选择 WiFi 页：恢复 2.4G 提示

- 顶部恢复「设备仅支持 2.4G WiFi 配网」提示条（`WifiTipRow`，与账号密码页同款），列表标题「设备附近的2.4G WiFi」；列表一直只留 2.4G、搜不到提示本来就写 2.4G，未变。

### 投屏 type 改取产品屏幕方向、WiFi 投屏带渲染模式

- `PhotoFrameState.resolveScreenType` / `resolveRenderMode`（同小程序 `api.resolveScreenType` / `resolveRenderMode`）：按 productId 查产品列表（与设备图回查共用会话缓存，最多等 3 秒），没有再按设备ID查 `getProductByDevice`；取不到返回空串。只读产品接口字段，`DeviceItem.screenType` 是固件 / 广播型号字节，不用。
- `type`：蓝牙版抖动出帧（`ServerImageProjectionService.castImages` 新增 `screenType`，与第一张出帧并行查、整轮共用）、WiFi 投屏结果页、WiFi 轮播保存后投第一张，三处同口径原样传产品 `screenType`（0=竖屏、1=横屏）；产品没配才按分辨率回退旧口径（480×720 传 1，其余 0）。
- `renderMode`：`IotApi.play` 新增 `renderMode`（有值才带、原样传）；WiFi 投屏结果页首轮投屏前取一次、每张带上、重试复用；轮播投第一张同样带。结果页投屏日志记 `type` 来源与 `renderMode`。

### WiFi 投屏进度条含图片处理

- `WifiProjection.projectOne`：真实上传进度折算到 0~50%；上传完进入「图片处理中」，每 200ms 按 `1-e^(-t/3s)` 从 50 渐近爬向 99；接口返回 SENT / UPLOADED 才到 100%，FAILED / 报错停在当时位置；接口返回或报错即停表。
- 结果页：写「我的相册」记录时不再把文案改成「正在存入我的上传」，100% 一直显示「已发送，屏幕即将刷新」；说明改「进度含图片上传与处理；…」。

### 配网全程屏幕常亮

- 原生通道 `com.boltfox.boltstar/device_api` 新增 `setKeepScreenOn`（Android `FLAG_KEEP_SCREEN_ON`，iOS `isIdleTimerDisabled`），`NativeDeviceApi.setKeepScreenOn` best-effort；配网状态页开始配网时打开、离开页面关闭（同小程序 `setKeepScreenOn`）。不引入新依赖。

### 进后台退订状态推送

- `WifiWatch`：页面在用时跟随 App 前后台——进后台（paused）退订自己订阅的、摘掉监听；回前台（resumed）按上次的设备重新订阅并全部重查一次（同小程序首页 / 我的设备 `onHide` 含进后台）。页面已 `stop` 的不受影响。

### 无需改动

- 重新配网按钮高度（0d1bc5f）：小程序 CSS flex 列方向的问题，App 用固定高度的主按钮，没有这个问题。

## 仍有差异（有意保留，待用户决定）

- 小程序调试台「IoT 联调」卡、全页面左下角联调日志浮窗（只在开发版 / 体验版出现的开发工具）未移植；App 只有 WiFi 投屏结果页的投屏日志，其它接口过程看控制台。
- 配网第 1 步「手机网络」：小程序用网络类型 API，App 用解析 IoT 域名判断（平台能力不同，结论一致）。
- 消息中心触底加载阈值不同（等价）。

## 测试

- 新增 `test/wifi_projection_progress_test.dart`：处理阶段从 50 起只增不减、不到 100，1 秒 63、3 秒 80；status 归一。
- 本机没有 Flutter 工具链，**未 analyze、未跑测试、未编译（含 Kotlin / Swift）、未真机**；请本地 `flutter analyze` + `flutter test`，并在 Android / iOS 各编一次。
