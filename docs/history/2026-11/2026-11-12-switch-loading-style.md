# 开关关闭样式同小程序（无描边）、加载转圈统一橙色（main）

> 类型：Historical Implementation Record
> 日期：2026-11-12；环境：远程 SSH 服务器；分支：main；修改前：e16fd03
> 依据：产品反馈：消息中心「只看未读」开关、轮播设置的启用开关，关闭状态要与小程序一致（没有描边）；加载图标统一为橙色。

## 改动

- 新增 `AppSwitch`（`shared/widgets/app_widgets.dart`，基于 `CupertinoSwitch`）：打开 `#FF6A20`（同小程序 `<switch color="#ff6a20">`），关闭浅灰 `#E5E5E5`，圆钮白色，两态都没有描边、圆钮大小不变。Material 3 的 `Switch` 关闭时是白底灰描边、小灰钮，与小程序原生 switch 不一致。
- 换成 `AppSwitch` 的位置：消息中心「只看未读」、轮播设置（简单模式与工作日 / 周末等卡片的启用开关，共用 `_switchHead`）、TF 卡播放开关、投屏预览「同时加入轮播」。原来消息中心与投屏预览外面的 `Transform.scale(0.8)` 去掉，尺寸与小程序原生 switch 相当。开发调试页 `ble_perf_page` 未改。
- 加载转圈：主题加 `progressIndicatorTheme`（`#EB5F1B`），没指定颜色的转圈不再取主题 primary 深青色；新增常量 `kLoadingOrange`。WiFi 消息中心、轮播设置、休眠设置、设备信息、共享设备的首屏加载改用 `PageLoading`（橙色圆环 +「加载中…」，同小程序 `.page-loading`）。官方图库、图库收藏、星币记录的下拉刷新转圈补上橙色（其余下拉刷新原本就是橙色）。

## 验证

- 新增 `test/switch_loading_style_test.dart`：`AppSwitch` 颜色；四处开关都用 `AppSwitch`、不再有 Material `Switch(`；主题转圈色与五个 WiFi 页首屏加载用 `PageLoading`。源码断言部分用 Python 对实际文件核对通过。
- 本机无 Flutter / Dart，analyze / test / 编译 / 真机未跑。
