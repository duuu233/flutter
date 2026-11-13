# 投屏后不再全局重拉投屏记录（main）

> 类型：Historical Implementation Record
> 日期：2026-11-14；环境：远程 SSH 服务器；分支：main；修改前：51fbeb1
> 依据：用户反馈 iOS「我的上传」看着还是 100 条分页。

## 原因

「我的上传」页本身每页 21 条（`gallery_page.dart` `_pageSize = 21`，2026-11-10 已同步小程序）。但首页、我的设备、蓝牙设备详情三处投屏返回后会调 `state.refreshCastRecords()`：不带参数，默认每页 100 条，也不带「投屏成功」筛选。它和「我的上传」共用 `castRecords` 列表，所以日志里看到的是 100 条一页的请求，「我的上传」重新加载前列表也会被换成这 100 条（含失败记录）。iOS 与安卓是同一份代码。

## 改动

- 去掉这三处投屏后的全局重拉。「我的上传」与「投屏记录」进页、返回本页（`didPopNext`）时各自按自己的分页重新加载，与小程序一致（小程序投屏后也不全局重拉）。
- 新增 `test/cast_records_paging_test.dart`。

## 验证

本机无 Flutter，未运行测试、未真机。「投屏记录」页（`cast_management_figma_page.dart`）仍按原逻辑每次取 100 条，本次未改。
