# App 新版本红点（main）

> 类型：Historical Implementation Record
> 日期：2026-11-14；环境：远程 SSH 服务器；分支：main；修改前：a23f800
> 依据：产品要求 App 升级也要有红点提示。

## 改动

- `PhotoFrameState.checkAppVersion`（`GET /Client/Basic/getLastVersion`）每次都记下结果（`_appVersion`）并通知刷新；`appUpdateDot` = 有新版本（`isUpdate=1`）且升级类型不是 4（不提示升级）。
- 红点位置：「我的」页「设置」行、设置页「检查更新」行，箭头前一个 8px 红点。
- 何时有数据：登录后（含冷启动恢复登录、闪屏结束后）的强制升级检查会查一次；进「检查更新」页也会刷新。查询失败不亮。
- 强制升级弹窗规则不变：只有 `compulsory=1` 且有新版本、下载地址不为空时，登录后弹出关不掉的弹窗；其它类型不弹，由用户点「检查更新」。
- 新增 `test/app_update_dot_test.dart`。

## 验证

本机无 Flutter，未运行测试、未真机。
