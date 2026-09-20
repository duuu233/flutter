# App 与 IoT 功能实现方案（依据协议 V1.3.1）

> 版本：v1.0　日期：2026-09-20  
> 目的：说明各功能**如何通过协议实现**（App → IoT → 设备），确保**闭环、切实可行**。

---

## 0. 总体链路

| 阶段 | 链路 |
|---|---|
| **配网** | App ↔ 设备（蓝牙 BluFi） |
| **运行** | App → IoT 平台 → 设备（MQTT 下行 `/inkjoyap/{clientid}`） |
| **回执 / 上报** | 设备 → IoT 平台（上行 `/device/report/{clientid}`）→ App |

**通用机制**：每次下发带 `msgid`，设备回 `*_ack`（带 `ack_msgid` + `result`）；IoT 记录指令与结果。

---

## 1. 配网（蓝牙 BluFi）

**流程**：
```
① App 蓝牙扫描 → 连接设备（BLE 名 IJ_(MAC)）
② BluFi 下发 WiFi：SSID、密码、BSSID
③ BluFi 自定义消息下发 mqtt_config（服务器 host/port/usr/pwd）
④ 设备连 WiFi + 连 MQTT
⑤ 设备发 login（上报 clientid/stamac/ver/statype）
⑥ IoT 记录设备上线 → 通知 App 配网成功
```
**指令**：BluFi 标准（WiFi）+ `mqtt_config`（XT 自定义）

---

## 2. 绑定 / 解绑

| 操作 | 实现 |
|---|---|
| **绑定** | 设备 `login` 后，App 侧调用 IoT 接口建立「用户-设备」关系（IoT 存 DB）|
| **解绑** | App 调用 IoT 接口删除绑定关系（**不下发设备指令**，设备仍在线）|

---

## 3. 投屏（`play`）

```
① App 选图 → 图片已在 OSS（复用现有上传）
② App 调 IoT 接口：deviceId + 图片地址
③ IoT 下发 play：host/port/imgs[] (imgid, imgurl)
④ 设备从 OSS 下载 → 显示 → 回 play_ack(result)
⑤ IoT 更新设备影子「当前图」→ 可选推送 App
```
**指令**：`play`

---

## 4. 轮播（`strategy`）

```
① App 设置轮播（顺序/随机、更新频率）
② IoT 下发 strategy：idle / strategy / host / port / path / updatedays / updatetimelist
③ 设备保存策略
④ 设备按 updatedays/updatetimelist 定时到 path 拉图（pull）
⑤ 设备下载并轮播 → 回 strategy_ack(result)
```
**关键**：`path` = **IoT 提供的「拉图接口」**（返回该设备的图列表）。平台**不用为每台设备定时下发**，设备自己拉。

**指令**：`strategy`；暂停用 `strategy_stop`

---

## 5. 屏幕刷新（`image_refresh`）

```
① App 点击「刷新屏幕」
② IoT 下发 image_refresh（协议原文：通知设备清空 TF 卡内容）
③ 设备清空本地 → 重新拉图 → 刷新显示 → 回 image_refresh_ack
```
**指令**：`image_refresh`

---

## 6. 照片删除

```
① App 删除图 A
② IoT / 服务器删除云端图 A（OSS）+ 更新 path 列表
③ 标记「列表已变」
④ 择机下发 image_refresh：
   - 若 A 可能正在显示，或用户主动刷新 → 立即下发
   - 否则 → 攒批 / 借 strategy 更新时刻统一下发
⑤ 设备清空重拉 → 不再含 A
```
**说明**：因协议**无「当前显示图」反馈**，无法精确判断，故按「列表变更 → 择机刷新」处理。

---

## 7. 图源切换（APP / TF 卡）

```
切到 TF 卡模式：IoT 下发 play_tf → 设备播放 TF 卡内图 → ack
切到 APP 模式：IoT 下发 play / strategy → 设备播放云端图 → ack
```
**注意**：IoT **需记录设备当前图源**，避免状态错乱。

---

## 8. WiFi 模式 / 定时休眠

| 功能 | 指令 | 参数 |
|---|---|---|
| WiFi 模式 | `wifimode` | mode(1实时/2定时/3休眠)、live、timingtime |
| 定时休眠 | `wifi_sleep` | mode(0关/1一次性/2周期)、开始/截止时间（UTC）|

```
App 设置 → IoT 下发 → 设备执行 → 回 *_ack(result)
```

---

## 9. 固件升级（`ota`）

```
① App 检查版本：读设备影子（version，来自心跳）
② 有新版本 → IoT 下发 ota：host/port/path（固件地址）
③ 设备从服务器下载固件 → 升级 → 回 ota_ack(result)
④ IoT 记录升级结果（成功后设备版本更新）
```
**指令**：`ota`（主控固件）/ `fpga`（FPGA 固件，独立）
**限制**：协议**只有成功/失败，无进度**

---

## 10. 设备信息查询（电量 / 版本 / ID）

- **数据来源**：心跳 `heart`（battery、version、stamac、fpga_ver 等）
- **实现**：IoT 维护「设备影子」→ App 查询接口直接读影子
- **无需额外下发**（数据随心跳更新）

---

## 11. 实时状态（二选一）

| 方案 | 实现 |
|---|---|
| **A. WebSocket** | 设备状态变化（心跳/回执）→ IoT 主动推送给 App |
| **B. 定时轮询** | App 定时调 `GET /device/{id}/status` 拉影子 |

---

## 12. 心跳与在线判定

```
设备周期发 heart → IoT：
  ① 更新设备影子（电量/信号/TF/版本等）
  ② 判定在线（MQTT 连接状态 + 心跳超时）
  ③ 按 ack 标志决定是否回 heart_ack
  ④ 状态变化 → 推送 App（若用 WebSocket）
```

---

## 13. 闭环要点小结

| 环节 | 关键 |
|---|---|
| 配网 | BluFi + `mqtt_config` → 设备 `login` |
| 绑定 | IoT 存「用户-设备」关系（与设备无关）|
| 控制 | 下行指令 + `*_ack` 回执，IoT 记录状态 |
| 轮播 | 下发策略，**设备定时拉图**（pull）|
| 删图 | 云端删除 + 择机 `image_refresh` |
| 状态 | 心跳驱动影子，App 查询/推送 |
| 升级 | `ota` 下发地址 + 结果回执 |
