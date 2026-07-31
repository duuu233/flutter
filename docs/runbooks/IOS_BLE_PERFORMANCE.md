# iOS BLE 投屏性能与诊断

> 文档类型：Diagnostic Runbook  
> 状态：Active  
> 最后核验：2026-07-28  
> 维护责任：BLE、投屏和 iOS 平台维护者

> 目的：定位「iOS 投屏比 Android 明显慢」的根因，并**判定 0x13 请求的 15ms 连接间隔是否真的生效**。
>
> 埋点已落在 `lib/src/device/ble/device_ble.dart`，日志前缀统一为 `[BLEPerf]`。
> 创建日期：2026-07-20 ｜ 更新：2026-07-22

---

## 当前实现基线

以下能力已经是当前实现的一部分，不再作为“待实施方案”：

- 正式包隐藏入口：设置 → 更新 BoltStar → 3 秒内连点版本号 7 次。
- 自检页展示 MTU、每包字节、写方式、连接间隔请求值、RTT 对照和纯 BLE 吞吐。
- `BleTuning` 可在一个包内切换连接间隔、pace、窗口和写方式，测试后必须恢复默认。
- MTU 在服务发现后协商；iOS 轮询等待 `mtuNow > 23`，失败时保持真实 23 而不臆造。
- release 关闭 flutter_blue_plus 高频日志，debug/profile 保留 warning。
- 空闲连接间隔与图传连接间隔通过串行队列协调，避免空闲档覆盖图传档。
- iOS 工程声明 `UIBackgroundModes: bluetooth-central`。
- `BlePerfLog` 在 release 中保留最近 300 条内存记录并支持复制，不落盘。

⚠️ 自检页顶部的「⓪ 连接对照实验（临时）」卡片与本文无关：它是安卓原生 vs `flutter_blue_plus`
的建连 A/B 探针（iOS 上原生一侧不可用），测完即拆，做 iOS 投屏性能时直接跳过它。
见 `../history/2026-07/2026-07-30-安卓原生连接AB对比.md`。

历史实施背景见
`../history/2026-07/2026-07-22-iOS投屏性能优化.md`；早期性能对比见
`../history/2026-07/2026-07-17-连接投屏性能对比分析.md`。

---

## ⚡ 先看这里（2026-07-22 更新）：现在**不需要 Mac 也能测**

本文档余下章节假设你有 Mac + Xcode。若你的条件是「**只能改代码、只在打好的正式包里体验**」，
直接用应用内的**投屏性能自检页**，本文第 6 节的 A/B/C 三组对照**不必再出三个包**：

> **入口：设置 → 更新 BoltStar → 连点版本号 7 次**（3 秒内）

它在正式包里给出本文档想要的全部答案：

| 本文档章节 | 应用内替代 |
|---|---|
| 第 5 节埋点 / 第 4 节采日志 | 自检页第⑤块「埋点记录」（`BlePerfLog`，**release 也记录**）+ 一键复制 |
| 第 6 节 A/B/C 对照实验 | 自检页第④块旋钮（连接间隔可切 15 / 30 / 100 / 不下发），一个包跑完 |
| 第 7 节主判据 throughput | 自检页第③块「纯 BLE 吞吐测速」（本地彩条帧，不联网、不经后端转码） |
| 第 9 节 PacketLogger | 自检页第②块「**连接间隔自检（RTT 探针）**」——不依赖任何私有 API 的间接判据 |

RTT 探针的原理与判读见
`../history/2026-07/2026-07-22-iOS投屏性能优化.md` 第二章②。
同一份文档还记录了本轮已落地的 iOS 侧优化（MTU 读取时机、FBP 日志级别、空闲档不再阻塞连接、
`UIBackgroundModes`），**其中 MTU 那条极可能就是本次「iOS 特别慢」的真凶**，请先看第 7 节的
`mtu` / `chunk` 两行。

---

## 0. 先看结论：iOS 慢是三个乘数叠加

按 480×720 4bpp ≈ 172KB 一帧估算：

| 因素 | Android | iOS | 倍差 |
|---|---|---|---|
| 连接间隔 | 7.5ms | 15ms（Apple 硬约束，无法更低） | **2.0x** |
| 每包有效载荷 `dataChunk` | 236 B | ~174 B | **1.36x** |
| **合计** | ~2s/帧 | **~5s/帧** | **≈2.7x** |

第二行常被忽略：Android 主动 `requestMtu(512)` 稳拿 chunk=236；iOS 没有该 API，只能读系统协商的
`device.mtuNow`（通常 185）→ chunk=174。而 chunk 上限 236 来自**固件**（PRD 6.8.2，
见 `frame_protocol.dart` 的 `buildImgDataPayload`），不是 MTU 限制——即使 iOS 协商到 527 也吃不满。

**因此本测试要同时回答两件事**：MTU 是否正常、连接间隔是否生效。两者都会表现为「投屏慢」，
但修复方向完全不同，必须先分开。

---

## 1. 硬前提：必须真机，且三样齐全

| 需要 | 能否省 | 原因 |
|---|---|---|
| **Mac** | 否 | 编译 iOS 包只能在 macOS（除非上 Codemagic 之类云 CI） |
| **iPhone 真机** | 否 | **iOS 模拟器完全没有 CoreBluetooth**，`CBCentralManager` 的 state 恒为 `.unsupported`，无任何绕法 |
| **真实相框** | 否 | 测的是私有协议（FF00/FF01/FF02 + 0x20~0x23）的滑窗 ACK 吞吐，没有真设备就收不到 0x23，第一个窗口即卡死 |

> Android 模拟器同样没有 BLE，做双端对照需要两台真机。

---

## 2. Mac 环境准备（一次性）

```bash
# 1) App Store 装 Xcode，装完必须打开一次同意协议
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept

# 2) 确认 iOS toolchain 就绪（"iOS toolchain" 那行要打勾）
flutter doctor -v

# 3) 装 CocoaPods 依赖
cd ios && pod install && cd ..
```

手机侧（**iOS 16+ 必做，漏了 `flutter devices` 根本看不到设备**）：

1. iPhone 插 Mac，手机弹窗点「信任此电脑」
2. iPhone → 设置 → 隐私与安全性 → **开发者模式** → 打开 → **重启手机**

签名：

3. 打开 `ios/Runner.xcworkspace`（**不是 `.xcodeproj`**，本工程有 CocoaPods，开错必编译失败）
4. Runner target → Signing & Capabilities → 勾 **Automatically manage signing** → Team 选自己的 Apple ID
5. Bundle Identifier 若冲突改成唯一值（如 `com.boltfox.boltstar.dev`）
6. 首次运行后手机会拦截：设置 → 通用 → VPN与设备管理 → 信任该开发者证书

> 免费 Apple ID 可跑真机，profile **7 天过期**，到期重装即可；测吞吐足够，但发不了 TestFlight。

---

## 3. ⚠️ 两个必须知道的坑

### 坑 1：debug 模式测出来的吞吐不作数

Flutter debug 是 JIT + assertions 全开。每张图要跑 `crc32(≈172KB)` 并预组约 1000 个数据帧，
都是实打实的 Dart CPU 活。debug 下这部分被显著拖慢，测出的 KB/s 偏低，
**并会把连接间隔造成的差异整个淹没**——你会看到 15ms 和 30ms 两组数据差不多，误判成「0x13 没生效」。

**必须用 `--profile`。**

### 坑 2：profile 下 `kDebugMode == false`

工程里原有的 BLE 日志都 gate 在 `kDebugMode`，切到 profile 会**一条都不输出**。
本次埋点因此统一走 `_perfLog()`，gate 在 `!kReleaseMode`（debug + profile 都输出，release 闭嘴）。
新增埋点时请沿用 `_perfLog`，不要退回 `kDebugMode`。

> 另注：`CrashLogger` 是原生实现且**只有 Android 侧有**（`AppDelegate.swift` 的 switch 对
> `getLastCrashLog` 落到 `FlutterMethodNotImplemented`），**iOS 目前没有任何应用内日志文件**，指望不上。

---

## 4. 采集日志的四种方式

### 方式 1：`flutter run --profile`（开发期首选）

```bash
flutter devices                              # 拿 device id
flutter run --profile -d <device-id>
flutter logs -d <device-id>                  # app 已在跑时事后挂载
```

`debugPrint` 直接流到终端。建议过滤：

```bash
flutter run --profile -d <device-id> 2>&1 | grep --line-buffered "BLEPerf"
```

### 方式 2：macOS「控制台」App（能看 release / TestFlight 包）

iPhone 连 Mac → 打开**控制台 (Console.app)** → 左侧选中 iPhone → 搜索框过滤进程 `Runner`。
这是唯一能看**已分发包**日志的办法。

### 方式 3：`idevicesyslog`（**可在 Linux 机上收**）

libimobiledevice 支持 Linux，iPhone 可直接插到日常那台 Linux 机：

```bash
sudo apt install libimobiledevice-utils
idevicesyslog | grep -i BLEPerf
```

构建仍需 Mac，但**装好后收日志不需要构建链**，符合本项目「Linux 机不装 Flutter/SDK」的约定，
多机型跑对比时日志统一落到一台机器上分析很方便。

### 方式 4：应用内展示（现场/无线测试）

`lib/src/features/devices/presentation/ble_debug_page.dart` 已挂 `_client.onMonitor = _onMonitor`，
是现成展示位。把汇总推一条进该列表即可做到不连线、不要 Mac、测试同事截图回传。
（工程未引入 `path_provider` / `share_plus`，**先只做屏显不落盘可零新依赖**。）

---

## 5. 埋点位置（已实现）

均在 `lib/src/device/ble/device_ble.dart`：

> **2026-07-22 变更**：`_perfLog` 改为 `_perfLog(tag, message)`，**两个出口**——
> 一路仍是 `debugPrint`（gate 在 `!kReleaseMode`，理由见坑 2），另一路写进 `BlePerfLog`
> **任何构建都记录**，供自检页显示/复制。埋点①的位置也从「connect 里 MTU 协商后」
> 挪到了「服务发现之后」（iOS 的 `mtuNow` 要等原生推上来，读早了拿到初值 23，
> 见 `../history/2026-07/2026-07-22-iOS投屏性能优化.md` 第三章 A）。

| # | 位置 | 输出 |
|---|---|---|
| ① | `connect()` 服务发现 + MTU 协商后 | `[BLEPerf] connected platform=ios mtu=… chunk=…` |
| ①' | `dataChunk < 100` 时 | `[BLEPerf] MTU 异常偏低…`（tag=`warn`，自检页标红） |
| ④ | 自检页 RTT 探针 | `[BLEPerf] connInterval self-test idle(100ms) … | fast(15ms) … | ratio=…` |
| ② | `uploadImage()` 0x22 之后 | `[BLEPerf] upload done mtu=… chunk=… packets=… bytes=… dataMs=… endMs=… throughput=…KB/s retries=… finalPace=…ms reqInterval=…ms ok=…` |
| ③ | `optimizeConnectionIntervalForTransfer()` | `[BLEPerf] connInterval requested=…ms readback=…ms` |

实现上的两个关键决定：

- **吞吐只按 `dataMs`（0x21 数据段）算。** 0x22 是设备侧 CRC 校验 + Flash 落盘（超时给到 20s），
  与链路速度无关，混进来会污染数据，因此 `endMs` 单独报。
- **`totalRetries` 单独累加。** 循环里的 `retries` 每次窗口推进都会清零，统计不到整张图的累计丢包次数，
  而这个数正是判断「iOS 无应答写有没有背压」的依据。

---

## 6. 对照实验

控制变量：**同一台 iPhone、同一台相框、同一张图、距离 <1m、关掉周围其它蓝牙设备**
（BLE 是 2.4G 共享频段，旁边有设备在传会直接改变结果）。

| 组 | 改动 | 次数 |
|---|---|---|
| **A（现状）** | 不动，请求 15ms | 3 |
| **B（阴性对照）** | 注释掉 `optimizeConnectionIntervalForTransfer()` 里的 `await setConnectionIntervalMs(target)` | 3 |
| **C（阳性对照）** | 把 `transferConnIntervalMs` 的 iOS 值临时改成 `30.0` | 3 |

取**中位数**，勿取平均（BLE 偶发重传会拖出离群值）。每组之间杀掉 app 重连一次。

> **C 组最容易被跳过，但最值得做。** 若 A ≈ C，说明 0x13 在 iOS 上压根没起作用，
> 问题在固件侧，App 怎么调都没用。**A ≈ B ≈ C 三组齐平 = 0x13 完全无效**，这是最干净的判据。

---

## 7. 字段含义与判定基线

| 字段 | iOS 预期 | 异常时说明什么 |
|---|---|---|
| `mtu` | **185**（部分新机 527） | **=23 → MTU 读早了**，`_mtu` 停在初值 |
| `chunk` | **174**（mtu=185 时） | **=12 → 同上**，包数暴涨 20 倍，这才是「慢」的真凶 |
| `packets` | 172800/174 ≈ **994** | 比 Android（≈733）多 36% 属正常；突然翻倍即 chunk 掉了 |
| **`throughput`** | **30–35 KB/s 生效**<br>**15–18 KB/s 未生效** | ← **主判据**，A 组 vs B 组差 ≈2x 即 15ms 生效 |
| `dataMs` | ≈5s | 计算吞吐用，**不含 0x22** |
| `endMs` | 设备侧耗时 | 若这项就占几秒 → 固件落盘慢，优化连接间隔无用 |
| **`retries`** | **0** | **>0 → iOS 无应答写在丢包**，见第 8 节 |
| `finalPace` | AIMD 探到 **0** | 一直停在高值 → 链路吃不消，配合 `retries` 看 |
| `readback`(0x05) | 15.0 | **不可作为生效证据**，仅参考，原因见下 |

### 为什么 0x05 回读不能当证据

`getConnectionIntervalMs()` 读回的可能是**固件保存的配置值**，而非链路实时参数。
iOS 上尤其危险：若固件下发的参数违反 Apple 规范被系统拒绝，链路停在 30ms，而 0x05 照样回 15。
**CoreBluetooth 没有任何 API 能读连接间隔**——App 内唯一可信的判据是吞吐对照。

### 判定路径

```
先看 mtu / chunk
  ├ 异常(23 / 12) → 问题在 MTU，先修这个，连接间隔的事往后放
  └ 正常(185 / 174) → 看 retries
       ├ >0 → iOS 无应答写丢包，去查 FBP darwin 背压（第 8 节）
       └ =0 → 看 A/B/C 三组 throughput
            ├ A ≈ 2×B 且 A > C → 15ms 生效 ✅
            └ A ≈ B ≈ C        → 0x13 在 iOS 上无效，查固件参数范围（第 8 节）
```

---

## 8. 已知待验证项（测出结果后按此跟进）

> **2026-07-22 进度**：④ 已修（`Info.plist` 补了 `UIBackgroundModes: bluetooth-central`）；
> ① 无需再翻插件源码——自检页第④块把「数据包写方式」切成**有应答写**再测一次即可证伪
> （有应答写天然有背压、绝不静默丢包，若 `retries` 由此归零就是无应答写在丢包），
> 并且 `paceFloor` 也做成了可调（0/1/2ms）；② ③ 仍在固件侧，App 改不了。
> 另外本轮补了一条本节没写到的 iOS 独有开销：**flutter_blue_plus 默认逐包打日志**，
> release 已关（见 `../history/2026-07/2026-07-22-iOS投屏性能优化.md` 第三章 B）。

### ① iOS 的 `writeWithoutResponse` 是否有背压

`_writePacket()` 靠 `catch` 异常重试，但 CoreBluetooth 的 `writeValue(type: .withoutResponse)`
是 fire-and-forget——**队列满时静默丢包，不抛异常**，正确做法是 gate 在
`canSendWriteWithoutResponse` / `peripheralIsReadyToSendWriteWithoutResponse`。

若插件未实现，AIMD 把 pace 探到 0（`paceFloor = 0.0`）时 iOS 会大量丢包 → 600ms ACK 超时
→ 窗口缩到 1 → 极慢，体感正是「传一段停一下」。

在 **Mac 上**验证：

```bash
grep -rn "canSendWriteWithoutResponse" ~/.pub-cache/hosted/pub.dev/flutter_blue_plus_darwin-*/
```

- 有命中 → 插件已处理，pace 探到 0 安全
- 无命中 → iOS 的 `paceFloor` 必须给非 0 下限（建议 1.0ms）

### ② 0x13 下发的参数范围是否符合 Apple 规范（最隐蔽）

Apple Accessory Design Guidelines 要求外设发起的连接参数更新满足：

- Interval Min ≥ 15ms
- **Interval Max ≥ Interval Min + 15ms**
- Slave Latency ≤ 30，Supervision Timeout ≤ 6s

App 的 0x13 只下发**单个值**（`connectionIntervalMsToUnits`），min/max 由固件自行组装。
**若固件发的是 min=max=15ms，违反第二条，iOS 直接拒绝**，链路停在默认 30ms——又是一个 2x。

→ 请固件确认发的是 `min=15ms / max=30ms`。

### ③ 固件接收缓冲 10 包 → 30+ 包

窗口被固件缓冲卡死在 10。每 10 包要停等一次 ACK，这个停等在 iOS 上是整整一个 15ms 连接事件。
窗口翻到 30，停等次数降到 1/3——**这是不动连接间隔就能拿到的最大一块 iOS 收益**。

### ④ `Info.plist` 缺 `UIBackgroundModes: bluetooth-central`

`ios/Runner/Info.plist` 只有权限描述，没有后台模式。投屏中切后台/锁屏，iOS 会挂起
CoreBluetooth，整批必断。若产品要求「投屏中可锁屏」，此项必须加。

---

## 9. 终极判据：PacketLogger（Mac only）

前面都定不了论时用这个。Apple 官方 HCI 抓包，直接看链路层实际参数，不依赖固件也不依赖推算：

1. developer.apple.com → More Downloads → 下 **Bluetooth 调试 profile**，装到 iPhone 并重启
2. Xcode → **Additional Tools for Xcode** → 内含 **PacketLogger**
3. 手机连 Mac，PacketLogger 选设备开始抓包，跑一次投屏
4. 过滤 `LE Connection Update Complete`

事件里的 **Conn Interval** 字段就是答案：`12` units = 15ms 即生效；`24` units = 30ms
说明请求被拒（大概率命中第 8 节 ②）。同时能看到 `LE Connection Complete` 的初始参数，
以及**是否根本没有 update 请求发出**（那就是固件没发 0x13 对应的参数更新）。

---

## 10. 测试结果记录

| 日期 | 机型 / iOS 版本 | 组 | mtu | chunk | packets | dataMs | throughput | retries | 结论 |
|---|---|---|---|---|---|---|---|---|---|
| | | A | | | | | | | |
| | | B | | | | | | | |
| | | C | | | | | | | |
