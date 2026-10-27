# 绑定页搜索列表尺寸没配显示「--寸」

> 类型：Historical Implementation Record
> 日期：2026-10-27；环境：远程 SSH 服务器；分支：main；修改前：c415d92
> 对应小程序：`subpackages/device/bind/bind.wxml`（同日同口径）

## 需求

搜索列表副标题的尺寸自 2026-10-23 起按广播名匹配产品列表、显示 `sizeModel`，匹配不到或没配时不显示。产品口径改为：直接显示 `sizeModel`，没配显示「--寸」，与小程序一致。

## 改动

- `bind_device_flow.dart` `_entryOf`：副标题第一段由「有 sizeModel 才加」改为 `sizeModel` 为空时显示 `l10n.bindSizeUnknown`，电量、信号不变。产品列表拉到前同样显示「--寸」，拉到后照旧重建列表。
- `AppL10n.bindSizeUnknown`：中文 `--寸`，英文 `-- in`，日文 `--インチ`。
- 匹配口径（`ProductBroadcastId.sizeModelOfScan`）、设备详情「屏幕尺寸」（没配整行不显示）均未改。

## 验证

- 本机无 Flutter/Dart，`flutter analyze`、`flutter test` 未运行；未真机。
- `git diff --check` 通过。
