# WiFi 表单行取值改为主题橙（main）

> 类型：Historical Implementation Record
> 日期：2026-11-14；环境：远程 SSH 服务器；分支：main；修改前：7ca5360
> 依据：用户要求轮播设置「简单模式」右侧文字按小程序改成橙色（APP 原为黑色）。

## 改动

- `WifiFormRow`（`wifi_widgets.dart`）取值颜色由 `0xFF2A2D32` 改为 `0xFFFF6A20`，同小程序 `.ws-row__value` / `.sl-row__value`。
- 影响范围：轮播设置页全部表单行（简单模式与高级卡片的开始 / 结束时间、每隔、播放频率、轮播照片），以及休眠设置页（入口目前隐藏）。小程序这两页本来就是橙色。
- `test/switch_loading_style_test.dart` 补断言。

## 验证

本机无 Flutter，未运行测试、未真机。
