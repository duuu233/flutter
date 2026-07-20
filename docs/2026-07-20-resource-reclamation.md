# 2026-07-20 回收机制审查 + 缓存治理三项修复

> **📌 文档维护约定**：本文档随代码演进——**每次修复问题 / 改动后，务必回到对应 .md 在文末「操作日志」追加一条**（日期 + 改了什么 + 对应代码符号/文件），防止文档滞后于代码、误导后续把已修的 bug 又改回去。

> ⚠️ 本机无 Flutter 工具链（见 memory `no-toolchain-on-linux-box`），本轮全部为**静态实施，未编译未运行**。
> 合入前必须在开发机执行：`flutter pub get`（**本轮新增了依赖**）→ `flutter analyze` → `flutter test` → 按文末回归清单真机手测。

本轮起因是一次全面审查「打包成 APP 后的回收机制」，分两条线：**进程级回收**（OS 杀进程）与**应用内资源回收**（dispose / 缓存）。
结论：进程级回收机制健全且已定版，**不改**；应用内 dispose 层面零泄漏，**问题全在缓存治理**，本轮修了三项。

---

## 一览

| # | 项 | 结论 | 主要落点 |
|---|---|---|---|
| 1 | 系统低内存告警无人处理 | 已修（新增 `didHaveMemoryPressure` 覆写） | `bolt_star_app.dart` |
| 2 | `imageCache` 从未配置上限 | 已修（60MB / 200 对象） | `main.dart` `_configureImageCache` |
| 3 | 临时图片产物只写不删 | 已修（冷启动清扫） | `temp_cache_sweeper.dart`（新增）、`main.dart` |
| 4 | 退出登录不清图片缓存（**隐私**） | 已修（内存+磁盘双清） | `image_cache_cleanup.dart`（新增）、`state.dart` ×3 |
| 5 | 「切出15分钟/息屏30分钟重启」 | **不改**：现有实现已满足，「重启」= 进程回到可回收状态（产品 2026-07-20 确认） | — |

---

## 一、「回收」的三层含义（先把话说清楚）

这个词在本项目里被用来指三件不同的事，混着说是历次沟通反复绕圈的根源：

1. **进程级回收**：租约到期 → 断开 BLE → 停前台服务 → 释放 wakelock → 进程回到**可回收**状态，
   之后由 Android 按内存压力自然处置。见 `2026-07-19-bugfix-round.md` 第 1 项，本轮**未改动**。
2. **应用内资源回收**：widget 的 `dispose()`、`StreamSubscription.cancel()`、`Timer.cancel()`。
   本轮全量审查结论：**零泄漏**，见下文「三」。
3. **缓存治理**：图片内存缓存、磁盘缓存、临时文件。**本轮修的就是这一层**，原来完全没有治理。

---

## 二、第 5 项：产品确认「保持现状」

反馈原文的期望结果是：

> 1. 蓝牙无活动 10 分钟，断开
> 2. 切出 app 重启时间要 15 分钟，不切出直接息屏重启时间 30 分钟
> 3. 重启不能丢失登录状态

逐条对账现有实现：

| 期望 | 现状 | 代码位置 |
|---|---|---|
| 无活动 10 分钟断开 | ✅ 已实现。且 25s 保活心跳**不**调用 `noteActivity`，所以「无活动」是真的无活动 | `ble_connection_lease.dart:39` `foregroundIdleTimeout` |
| 切出 15 / 息屏 30 | ✅ 时长已实现；「重启」语义见下 | `:40` `backgroundGracePeriod`、`:41` `screenOffGracePeriod` |
| 重启不丢登录态 | ✅ token 落盘，冷启动闪屏期间并行恢复 | `api_session.dart:18`、`bolt_star_app.dart:150-162` |

**关于「重启」**：现有实现到期后**不重启 App**，只是让进程变成**可回收**。差别在于——

- 内存紧张的机器：进程被系统杀掉 → 下次打开是冷启动（= 用户说的「重启」）；
- 内存充裕的机器：进程继续活着 → 下次切回来仍在原页面，只是蓝牙已断。

2026-07-20 与产品确认后**选择保持现状**，不引入自杀式重启（`Process.killProcess`）：
Android 上可做且后台无感，但 iOS 明确禁止（`exit(0)` 会被审核拒），会造成双端行为分裂；
且这与 `2026-07-19-bugfix-round.md:52-54` 的既有判断一致。

> ⚠️ **别再把这条当 bug 反复提**。「切回来还在原页面」不是回收机制失效，是内存充裕时的正常表现。
> 判断回收是否生效，看的是**通知栏前台服务是否消失 + 蓝牙是否断开**，不是「App 有没有看起来重启过」。

---

## 三、应用内 dispose 审查：零泄漏（未改动，仅记录结论）

全量交叉核对 94 个 Dart 文件的资源创建点 vs 释放点：

- 24 个 `TextEditingController` / `AnimationController` / `PageController` **全部释放**；
- `super.dispose()` 在每个 override 里都**排在最后**；3 个 `AnimationController` 全用了 `SingleTickerProviderStateMixin`；
- 全项目**不存在** `FocusNode` / `ScrollController` / `TabController` / `StreamController` / `ValueNotifier` 的构造点，泄漏面本身不存在；
- 5 个 `StreamSubscription`、8 个 `Timer` 全部取消，且多数是「`dispose()` + 方法入口重入」双保险；
- `addListener` / `removeListener` 三对全部对称。

**这块不需要动，也别"顺手优化"**。几处看着奇怪的写法都是修过的坑，注释里记着原因：

- `device_details_page.dart:118` / `my_devices_page.dart:157` 的**延迟 dispose**：弹窗内的 controller
  要活过退场动画，立刻 dispose 会 use-after-dispose 断言，不 dispose 则每次改名泄漏一个 ChangeNotifier。
- `device_ble.dart:297-300` 的订阅取消：`onValueReceived` 是全局流，不取消的话每次重连多挂一个解析器，图传越来越慢。

已知的三处**低优先级**残留，本轮未处理：

- `bind_device_flow.dart` 没有 `dispose()`：扫描中返回上一页，12 秒扫描窗口会跑到自然超时。
  不是泄漏（`device_ble.dart:251-256` 的 `finally` 会收），只是白耗射频。
- `casting_progress_page.dart:124` / `ota_upgrade_page.dart:148` 的 `dispose()` 只置 `bool _aborted`，
  没有硬取消路径，依赖传输循环及时轮询该标志。
- `home_page.dart:109` 的 `Timer? _scanTimer` 声明了、`.cancel()` 了，**但从没赋过值**——
  removed mock-scan 的残留死代码，会误导人以为有个 timer 在管。

---

## 四、第 1+2 项：内存压力与图片缓存上限

**问题**：`_BoltStarAppState` 早就是 `WidgetsBindingObserver`，却没有覆写 `didHaveMemoryPressure()`
——Android 在杀进程**之前**会先发这个信号，本 App 收到后什么都不做，白白浪费唯一一次自救机会。
同时 `imageCache` 从未配置，跑的是 Flutter 默认 **1000 对象 / 100MB**。

图库一页 100 张，每格按 `memCacheWidth = 格宽 × devicePixelRatio` 解码（`gallery_page.dart:722`），
3x 屏上单格约 1MB 起步——填满默认额度就是 100MB **纯解码位图**，叠上原生
`MainActivity.decodeToRgba` 的 `w*h*4` 分配，低端机很容易撞 LMK。
用户侧表现正是「切出去一会儿回来又是冷启动」。

**改法**：

- `main.dart` `_configureImageCache()`：`maximumSizeBytes = 60MB`、`maximumSize = 200`。
  60MB 约存 50~60 格，覆盖一屏加上下各一屏的滚动缓冲，滚动不会明显反复解码。
- `bolt_star_app.dart` `didHaveMemoryPressure()`：`cache.clear()` + `cache.clearLiveImages()`。
  两个都要调——`clear()` 只清「缓存着但没人用」的，正在显示的图仍挂在 live 表上。

> 只调**内存**缓存。磁盘缓存归 `cached_network_image`，内存逐出后从磁盘重建，**不重新下载**。

---

## 五、第 3 项：临时图片产物只写不删

**问题**：两个写入点都用「前缀 + 微秒时间戳」命名，**永不重名也就永不覆盖**，且没有任何删除路径——
装机后一直累积到用户手动清缓存：

- `cast_edit_*.jpg`（`cast_image_editor.dart:80-82`）：每次旋转/裁剪一张设备分辨率 JPEG；
- `recast_*.jpg`（`cast_management_figma_page.dart:211-214`）：每次「重新投屏」下载一张**完整原图**，最占地方。

**改法**：新增 `shared/temp_cache_sweeper.dart`，`main()` 冷启动时 `unawaited` 清扫。

> **为什么不在用完的地方顺手删**：这两个产物产出后都会**交给别的页面继续用**
> （预览页 → 原生裁剪器 → 投屏流程，中途还会来回 push/pop），"谁是最后一个用完的人"
> 在调用链上并不收敛。在任一使用点删，都可能删掉另一个还挂在栈上的页面正在显示的图
> ——`avatar_upload.dart:69-72` 已经记录过同一个坑。
> **冷启动这一刻没有任何页面存活、没有任何 File 句柄挂着**，是唯一能无歧义判定「这些全是垃圾」的时机。

**已知残留（刻意取舍）**：单次运行内产出的文件要等到下次冷启动才清。上限是一次会话的编辑量，
不再是「装机以来的全部」。换来的是零误删风险。

**不在清扫范围**：头像产物 `boltstar_avatar_*.jpg` 落在选图器缓存目录
（`source.parent.path`，随平台/插件变化）而非 `Directory.systemTemp`，且单个 ≤100KB，交给系统回收。

⚠️ **以后新增临时图片写入点，记得把前缀加进 `TempCacheSweeper._prefixes`。**

---

## 六、第 4 项：退出登录不清图片缓存（隐私）

**问题**：`logout` / `deleteAccount` / `_handleSessionExpired` 三条路径原来只清**内存里的业务列表**
（`_devices` / `_albumPhotos` / `_castRecords`），但用户的照片本体留在两层缓存里：

- 内存：`PaintingBinding.imageCache` 里已解码的位图；
- 磁盘：`cached_network_image` 的缓存目录，默认 **30 天 / 200 个对象**。

于是换账号后，B 用户虽然看不到 A 的列表，**A 的照片文件仍完整躺在本机上**；
注销（账号已在服务端删除）后本地照片也还在。共用设备场景下这是实打实的泄露。

**改法**：新增 `shared/image_cache_cleanup.dart`，三条路径统一调 `ImageCacheCleanup.clearAll()`
（内存同步清、磁盘后台清且吞错——登出必须立刻返回让 UI 弹回登录页，不能被几十上百个 IO 拖住）。

**新增依赖**：`flutter_cache_manager: ^3.4.1`。它本来就是 `cached_network_image` 的传递依赖，
这里**显式提升为直接依赖**——`DefaultCacheManager` 只能从这个包导入，
而直接 import 传递依赖会在上游改版本时突然断裂。

---

## 回归清单（开发机 / 真机）

先 `flutter pub get`（**本轮新增依赖，必须先跑**）→ `flutter analyze` → `flutter test`。

真机手测：

1. **临时文件清扫**：投屏预览页反复旋转/裁剪若干次 + 「重新投屏」若干次 → 杀掉 App 重新冷启动
   → 看日志 `[TempCacheSweeper] 已清理…释放 xxMB`，确认 systemTemp 里 `cast_edit_*` / `recast_*` 已清空。
2. **图片缓存上限**：图库快速上下滚动多页 → 不应出现明显的反复白图/闪烁（若有，说明 60MB 偏紧，调大）。
3. **低内存告警**：`adb shell am send-trim-memory <pid> RUNNING_CRITICAL`
   → 看日志 `[MemoryPressure] 系统低内存告警，清空图片缓存（当前 …）`，App 不崩，返回图库能重新加载。
4. **登出清缓存**：A 账号浏览图库若干张 → 退出登录 → 登录 B 账号
   → A 的图不应从缓存瞬显；`adb shell run-as <pkg> ls cache/libCachedImageData` 应已清空。
5. **注销清缓存**：同上，走「用户注销」路径。
6. **登出不卡顿**：退出登录点击后应**立刻**弹回登录页（磁盘清理在后台，不能阻塞）。
7. **租约（复测，本轮未改）**：连上设备 → 切出 App 计时 15 分钟 → 通知栏前台服务应消失、蓝牙应断开；
   息屏 30 分钟同理。**判据是「服务消失 + 蓝牙断开」，不是「App 看起来重启过」**。
8. **登录态**：上一条断开后杀进程重开 → 应直接进首页，**不需要重新登录**。

---

## 操作日志

- 2026-07-20：全面审查「打包成 APP 的回收机制」两条线（进程级 / 应用内）。
  进程级回收机制健全，第 5 项经产品确认**保持现状不改**；应用内 dispose 零泄漏；
  修复缓存治理四项：`didHaveMemoryPressure` 覆写（`bolt_star_app.dart`）、
  `imageCache` 上限 60MB/200（`main.dart` `_configureImageCache`）、
  临时图片冷启动清扫（新增 `shared/temp_cache_sweeper.dart`）、
  登出/注销/会话失效清图片缓存（新增 `shared/image_cache_cleanup.dart`，`state.dart` 三处调用）。
  `pubspec.yaml` 新增直接依赖 `flutter_cache_manager: ^3.4.1`。
