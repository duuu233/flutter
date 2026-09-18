# 投屏横向导出角改取后端 `rotationDegree`——App 写死的 270° 与后台配的 90° 差了 180°

> 文档类型：Historical Change Record
> 日期：2026-09-18
> 环境：SSH
> 分支与起始版本：`main` / `7cd1f98`
> 范围：新增 `lib/src/features/cast/device_rotation.dart`、`lib/src/state.dart`、
> `lib/src/features/cast/presentation/cast_preview_page.dart`、`lib/src/features/cast/cast_image_editor.dart`（注释）、
> 新增 `test/device_rotation_test.dart`
> 口径来源：小程序 `utils/device-rotation.js`（测试反馈小程序这条链路没问题）

## 根因

后台这个产品配的是 **横向旋转度数 90°、竖向旋转度数 180°**。

| | 小程序 | App（改之前） |
|---|---|---|
| 横向 landscape | 后端 `rotationDegree`（缺失才回退 270） → **90°** | **写死 270°** |
| 竖向 portrait | 后端 `verticalRotation`（缺失 0） → 180° | 同左 → 180° ✔ |

**横向差了整整 180°**，也就是「投到设备上正好反过来」。竖向那条两端一致，本来就没问题。

这条差异**不是新出现的**：`cast_preview_page.dart` 里 2026-08-04 就写着
「⚠️ 小程序侧横向角取的是后端设备字段 `rotationDegree`（缺失才回退 270°），App 仍写死 270°，
两端在这一点上尚未对齐」。在后台把这个值配成 90 之前，两端算出来都是 270，看不出来；
配成 90 的那一刻，App 就开始倒着投。

⚠️ **为什么预览看不出来**：导出角是给设备屏朝向做的补偿，预览侧会按同一角度**反向转回来**，
所以不管角度配多少，预览永远是正的——只有设备上能看出来。这也是为什么反馈是
「预览是对的、设备上反了」。（与此无关的圆形改动已按要求回滚，见上一条记录。）

## 改法：把两个角的取值收进一处，与小程序同源

新增 `lib/src/features/cast/device_rotation.dart`，1:1 对应小程序的 `utils/device-rotation.js`：

- `landscapeDegreeFrom(json)` → `rotationDegree`，**缺省 270**；
- `verticalDegreeFrom(json)` → `verticalRotation` / `verticalRotationDegree` / `verticalrotation`
  三个兼容名按序命中，**缺省 0**；
- `hasLandscapeKey` / `hasVerticalKey`：只看**键在不在**，给详情接口合并用。

⚠️ **两个方向的缺省值不一样**（横向 270、竖向 0），⚠️ **0 是合法角度**（明确不旋转），
判空只能判 null / 空串——原来竖向那条用的是 `_asInt`（缺失返回 0），横向要是照抄就会把
「后端没下发」当成「不旋转」，把历史兜底角 270 丢掉。

配套：

- `DeviceItem` 新增 `rotationDegree`（可变，缺省 270），`_deviceFromJson` 两个角都走 `DeviceRotation`；
- 详情接口合并时两个角都补（仍然只在**详情真的带了这个键**时才覆盖）；
- 预览页 `_kLandscapeExportRotateDeg`（常量 270）→ `_landscapeExportRotateDeg(device)`，
  `_exportRotateDegOf` 的横向分支改走它；进页面那行排查日志的「横向导出角」跟着变成实际值。

**烘焙、反向预览、缓存指纹三处仍然共用 `_exportRotateDegOf` 一个出口**，
所以横向角一变，三处一起变，不会出现「设备上正了、预览里倒了」。

## 影响面

- 后台**没配**横向角的产品：`DeviceRotation` 回退 270，与改动前**逐度一致**；
- 后台配了的产品：按配置走（本例 90）；
- 竖向、未编辑图（`coverCropToSize` 恒取竖向角）、导出画布尺寸、帧字节数：**一个字没动**。

## 验证

- 新增 `test/device_rotation_test.dart`：横向配 90/180 照用、0 不被当缺失顶回 270、
  缺失/null/空串/非数字回退 270、字符串与小数照解；竖向缺省 0 而不是 270、三个兼容名按序命中；
  `hasXxxKey` 对值为 0 仍判「给了」。
- ⚠️ **本机无 Flutter 工具链**，`flutter analyze` / `flutter test` 跑不了，用例**未运行**。
  做了人工核对 + 括号配平 + `git diff` 逐行复核。
- **待真机确认**：横向投一张，设备上应与小程序一致；竖向仍旧正常。
