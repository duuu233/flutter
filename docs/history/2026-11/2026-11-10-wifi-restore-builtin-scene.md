# restore-builtin 新增 scene，一键清空与我的相册全删后恢复内置图片（main-wifi）

> 类型：Historical Implementation Record
> 日期：2026-11-10；环境：远程 SSH 服务器；分支：main-wifi；修改前：c55af45
> 依据：接口文档口径——`POST /api/device/restore-builtin` 新增选填参数 `scene`，原入参与返回不变；删除设备流程可不传。与小程序 main-wifi 同日改动一致。

## 改动

- `IotApi.restoreBuiltin` 加选填 `scene`（有值才带、原样传）；新增常量 `IotApi.restoreSceneDeleteAllPhotos = 'DELETE_ALL_PHOTOS'`，
  body 拼装抽成 `IotApi.restoreBuiltinBody`（也用于请求日志）。
- 删除设备（`wifi_remove_flow.dart`）不变：① clearUserProductImg 清相册记录 → ② photo/delete all=true → ③ restore-builtin（不传 scene）
  → ④ delUserProduct。
- 一键清空：同一个 `_wipePhotos`，第 ③ 步传 `scene=DELETE_ALL_PHOTOS`；其余（出错只有 401 / 403 停下）不变。
- 我的相册 WiFi 版删除（`gallery_page.dart` 的 `_deleteWifiPhotos`）：**全删**时，在记录与云端删除之后新调 restore-builtin
  （`renderMode` 同投屏、取不到不传，`scene=DELETE_ALL_PHOTOS`），由 `_restoreBuiltinAfterDeleteAll` 发起。
  - 全删 = 删除前当前设备列表已加载完（`castRecordsHasMore=false`）且全部选中，记录一条不剩地删掉、云端删除也成功；
    部分选中、还有下一页、有记录没删掉、云端删除失败都不调。
  - 照片已删，这一步不影响删除结果：`SENT` 提示「已删除，相框将恢复显示内置图片」（新文案 `wifiDeleteRestoredBuiltin`，四语种走 `pick`），
    `SKIPPED` 或出错只记日志（401 由接口层引导重登），照原提示收场。请求与返回带 `[相册删除][WiFi]` 前缀打日志。

## 验证

- 新增 `test/wifi_restore_scene_test.dart`（body 带 / 不带 scene）。页面流程没有现成的 widget 测试覆盖，未补。
- 本机无 Flutter/Dart，`flutter analyze`、`flutter test` 未运行；未真机、未与服务端联调 `scene`。
- 改动的 Dart 文件括号配平、`git diff --check` 通过。
