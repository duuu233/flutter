# 绑定设备页雷达各状态尺寸不变（main-wifi）

> 类型：Historical Implementation Record
> 日期：2026-11-10；环境：远程 SSH 服务器；分支：main-wifi；修改前：2693ba6
> 依据：产品反馈勾选搜到的设备后，上方搜索 gif 换成「已搜到」图标时又缩小，要求只按状态换图标、宽高不变。与小程序 main-wifi 同日改动一致。

## 原因

- 发现页（`bind_device_found.dart`）2026-11-05 只让搜索中不缩：搜索结束后雷达按「列表优先凑满 4.5 张卡」的账算，夹在 150~280 之间，
  常规屏上会明显小于 280。勾选设备 / 结束搜索 / 立即绑定都会停扫，停扫那一下 gif 换静态图同时缩小。
- 搜索结束的「已搜到」与未发现页用的是代码画的雷达（`FigmaBluetoothRadar` / `FigmaDeviceRadar`），与 gif 的视觉大小也不一样。

## 改动

- 发现页雷达尺寸不再看 `scanning`：一律 `(可用高度 - 统计行等固定高度).clamp(150, 280)`，常规屏即 280（与搜索中页同尺寸），
  只在分屏 / 横屏连 280 都放不下时兜底缩小（搜索中 / 搜索结束一致）。列表拿剩下的高度，最多 4.5 张，不够就短一些（可滚动）。
- 搜索结束换成 `assets/images/device_found_art.png`，未发现页换成 `assets/images/device_not_found_art.png`（与小程序同图），
  和搜索中 `search-devices.gif` 同为 280 框、`BoxFit.contain`，只换图片。
- 首页内嵌的绑定视图（`home_bind_device_view.dart`，仅调试场景用）本来就是固定 250 框 + 同样三张图，未改。
- 新增 `test/bind_radar_fixed_size_test.dart`（源码静态核对）。

## 验证

- 本机无 Flutter / Dart，未 analyze / test / 真机；新测试的正则用 python 对实际源码核对通过，git diff --check 通过。
- 列表可见张数会比原来少（原搜索结束后约 4.5 张，现在由 280 雷达之后的剩余高度决定），需真机确认观感。
