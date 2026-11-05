# WiFi 版「共享设备」接收者可见（对齐小程序 main-wifi）

> 类型：Historical Implementation Record
> 日期：2026-11-05；环境：远程 SSH 服务器；分支：main-wifi；修改前：d570d33（已合入 main 的 iOS 权限文案本地化）
> 对应小程序：`subpackages/device/wifi-detail`、`subpackages/device/wifi-share`（同日同口径）

## 需求

设备详情「分享设备」改叫「共享设备」；接收者也要能看到这个入口；进去显示的内容与所有者一致，只是没有移除按钮、没有分享设备按钮。

## 改动

- `wifi_l10n.dart`：新增 `wifiSharedDevice`（共享设备 / Device sharing / デバイス共有），用作详情入口与共享设备页标题；底部按钮仍用 `wifiShareDevice`（分享设备）。
- `WifiDeviceDetailPage`：「共享设备」入口去掉 `_isOwner` 限制，所有者与接收者都显示；「删除设备」仍仅所有者。
- `WifiSharePage`：进页面自己查 `getUserProductDetail` 按 `wifiIsOwner` 判断身份（查不到按加载失败，不猜），再查成员列表。接收者：所有者栏 + 已分享成员照常显示；不显示每行「移除」、底部「分享设备」按钮和提示语，`_remove` / `_share` 内也按身份拦；不刷新个人资料；成员接口没有所有者那条时不拿自己兜底（所有者栏不显示）。所有者本人行为不变。

## 验证

- `test/wifi_tf_share_test.dart` 新增接收者分组用例（成员照常、无所有者时不兜底）；页面渲染未加 widget 测试。
- 本机无 Flutter/Dart，`flutter analyze`、`flutter test` 未运行；未真机。
- 接收者账号调 `getShareUserProductList` 是否返回完整成员列表未联调。
- `git diff --check` 通过。
