# 资源生命周期与缓存策略

> 文档类型：Architecture Decision  
> 状态：Active  
> 最后核验：2026-07-28  
> 维护责任：应用生命周期、图库、投屏、账号与 BLE 维护者

## 1. 目标

- 控制图库和图片处理的内存峰值，降低低端机被系统杀进程的概率。
- 不让临时投屏文件在安装期内无限累积。
- 退出、注销或会话失效后清除上一账号的照片本体。
- BLE 保活只覆盖产品需要的宽限期，不把进程永久锁在前台服务状态。

## 2. Flutter 图片内存缓存

`main.dart::_configureImageCache()`：

- `maximumSizeBytes = 60MB`
- `maximumSize = 200`

默认 100MB/1000 对象对一页 100 张图片的图库过高。60MB 约覆盖当前屏幕及上下滚动缓冲；
内存淘汰后仍可从磁盘缓存重建，不等于重新下载。

系统触发内存压力时，`BoltStarApp.didHaveMemoryPressure()` 同时执行：

```text
imageCache.clear()
imageCache.clearLiveImages()
```

只清 `clear()` 不足以释放仍登记为 live 的图片。

## 3. 磁盘图片缓存与账号隔离

以下三条路径统一调用 `ImageCacheCleanup.clearAll()`：

- `PhotoFrameState.logout`
- `PhotoFrameState.deleteAccount` 成功后
- `PhotoFrameState._handleSessionExpired`

清理范围：

- Flutter 已解码图片内存缓存；
- `cached_network_image` / `DefaultCacheManager` 磁盘缓存。

磁盘清理后台执行且吞掉清理异常，不能阻塞退回登录页。业务列表、选中设备和加载状态必须同步
复位，避免下一账号先看到上一账号的数据或缓存图。

注销接口失败时账号仍有效，不执行本地资产清理；只有服务端注销成功后才清。

## 4. AI 服务协议同意缓存

`AiServiceConsent` 使用 `SharedPreferences` 保存“协议版本 + BoltFox 用户 ID”维度的同意状态：

- A 用户同意不能让 B 用户跳过确认；
- 缓存缺失视为未同意；
- 协议发生实质更新时修改版本，旧记录自然失效；
- `logout`、`deleteAccount` 成功后和 `_handleSessionExpired` 都在用户 ID 被重置前清除当前记录。

持久化失败按“未同意”处理，不能以内存布尔值绕过缺失的用户缓存。

## 5. 临时文件

投屏编辑和再次投屏会产生带唯一时间戳的临时图片。当前策略是在冷启动由
`TempCacheSweeper.sweepOnColdStart()` 清扫已登记前缀：

- `cast_edit_*`
- `recast_*`

不在业务链路中“用完即删”，因为文件会跨页面、异步上传和预览继续使用，调用点无法可靠判断
最后一个消费者。冷启动时没有存活页面或文件消费者，是无歧义的回收时机。

新增临时文件前缀时，必须同步加入 `TempCacheSweeper`，并在本文登记。

单次运行产生的临时文件会保留到下一次冷启动，这是为避免误删做出的有意取舍。

## 6. BLE 与进程生命周期

`BleConnectionLease` 管理的是外层会话寿命，不修改 GATT、协议或图传策略：

| 场景 | 策略 |
| --- | --- |
| 前台 | 保持活动连接 |
| 切出 App、屏幕仍亮 | 15 分钟宽限 |
| 息屏 | 30 分钟宽限 |
| 连接/图传/OTA 活跃 | 不在任务中途回收 |
| 断开/宽限到期 | 停止保活服务并清会话 |

Android 连接期间使用前台服务提高进程优先级；断开后必须撤销。所谓“重启/回收”是让进程回到
系统可回收状态，不是主动杀进程或清除登录态。

## 7. 启动与异常

`main()` 启动时执行 best-effort 清理：

- 停止热重启/异常退出可能残留的 Android BLE 保活服务；
- 清扫上次运行的临时投屏文件；
- 加载 BLE 调优参数；
- 配置图片缓存上限。

Android 原生崩溃和 Dart 未捕获异常写入受限额的崩溃现场；下次启动展示并允许复制/清除。

## 8. 变更检查

新增以下代码时必须复核资源归属：

- 图片文件写入；
- `ImageProvider` 或大图解码；
- `StreamSubscription`、Timer、AnimationController；
- BLE 通知/连接；
- 账号退出路径；
- 长期缓存或 SharedPreferences。
- 第三方 AI 服务、用户授权或协议版本。

验证重点：

- 图库长时间滚动无异常白图和持续内存上涨；
- 低内存告警后页面可重新加载；
- 冷启动清掉旧临时文件；
- A 账号退出后 B 账号不会瞬显 A 的缓存图片；
- BLE 宽限到期后连接和前台服务均消失。

历史审查见 `../history/2026-07/2026-07-20-resource-reclamation.md`。
