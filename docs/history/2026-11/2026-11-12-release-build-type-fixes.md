# 修复 release 打包的三处类型编译错误（main）

> 类型：Historical Implementation Record
> 日期：2026-11-12；环境：远程 SSH 服务器；分支：main；修改前：050f028
> 依据：Android `assembleRelease` 在 `compileFlutterBuildRelease`（kernel_snapshot_program）阶段报 3 处类型错误。

## 改动

- `gallery_page.dart` 蓝牙版删除：`recordResult` 的声明类型补上 `failedIds`，与 `PhotoFrameState.deleteCastRecords` 现在的返回值 `({int total, int failed, List<String> failedIds})` 一致。只改类型，后面的逻辑没动。
- `wifi_cast_result_page.dart`：`state` 改为可空 `PhotoFrameState?`，与 `CastPreviewPage.state` 一致，预览页可以直接把自己的 state 传过来。state 为空时屏幕方向和渲染模式都按「产品未配置」处理，也就是回退到按分辨率算的 `type`、不传 renderMode。现有入口都会传 state，所以行为不变。
- `wifi_share_page.dart`：`owner`（`bool?`）判空后先存成非空的 `final isOwner`，再拿到 `setState` 闭包里赋值给 `_isOwner`。闭包里读可空局部变量时不保留判空后的类型提升。

## 验证

本机无 Flutter / Dart / Android SDK，analyze、test、编译和真机都没跑；只对着报错位置逐处核对了改法，`git diff --check` 通过。需要在本地重新执行 release 打包确认。
