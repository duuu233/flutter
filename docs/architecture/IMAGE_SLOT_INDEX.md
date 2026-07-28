# 设备图片槽位索引（imgIndex）

> 文档类型：Protocol Decision  
> 状态：Active  
> 最后核验：2026-07-28  
> 维护责任：投屏、图库、后端设备图片记录维护者

> 方案背景、协议依据、已知问题（A~E）以小程序仓库 `photo-album/docs/图片索引-imgIndex方案.md` 为准，本文只记 **App 侧的落点与差异**。

## 决策沿革

- **2026-07-18**：App 接入 imgIndex，与小程序 2026-07-18 那版对齐。投屏成功时上报设备物理槽位，图库「删除图片」「刷新屏幕」改为按该索引定位。

---

## 一、为什么需要它

设备只用 12 字节位掩码管理图片，**位索引就是图片的唯一身份**，设备侧不存任何元数据。谁在哪个位置完全靠 App 记住。

改之前索引在投屏时是已知的（`firstFreeIndex` 选出的槽位），传完就丢了；图库删除/刷屏只能靠「上传先后 ↔ 升序占用槽位」反推——一旦中间删过图、槽位被复用，推算就错位，表现为「删错图」「指定刷新的图不对」。

这正是此前排查结论里记的「App 代码已与小程序一致，残留是共有的槽位推断缺陷，需后端返回真实槽位」——后端已在 `ClientUserProductImgApiOut` 下发 `imgIndex`，前提条件成立。

## 二、字段链路（swagger 已确认四处齐备）

| DTO | 方向 | 用途 |
| --- | --- | --- |
| `ClientUserProductImgRecordEditApiIn` | 入参 | 正常投屏成功 → `editUserProductImgRecord` |
| `ClientUserProductImgApiOut` | 出参 | 图库列表 → `AlbumPhoto.imageIndex` |
| `UserProductImgRecordApiOut` | 出参 | 投屏记录 → `CastRecord.imageIndex`（仅透传备查，页面不读） |

后端类型是 **String**；App 内部统一用 **int，-1 表示无索引**。

`UserProductImgRecordAddApiIn` / `addUserProductImgRecord` 仍保留在 API 封装中，但属于旧
`imgBle` 设备帧直传链路，当前业务流程不调用。

## 三、代码落点

**写**（`features/cast/projection_service.dart`）：

- 普通投屏与再次/重新投屏最终都进入 `castImages`。
- 每张图先通过 `setUserProductUpload` 创建一条新记录并取得 `taskId`，同时由 seekink
  生成新的设备帧。
- BLE 图传成功后调用 `editUserProductImgRecord(taskId, deviceUploadState: 1,
  imgIndex: index)`。
- 再次/重新投屏先下载历史记录的服务器图片，进入预览编辑，然后走上述同一链路；
  不再下载历史 `imgBle`，也不再调用 `_addRetryRecord` /
  `addUserProductImgRecord`。

**序列化**（`network/boltfox_api.dart`）：`_imgIndexParam(int?)` → `String?`，null/负数返回 null 由 `?` 展开丢弃该键。

**解析**（`state.dart`）：`_parseImgIndex(Object?)` → int，无索引/非法值/越界（≥容量）统一 -1。

**读**（`state.dart` `_resolveDeviceImageIndex`）——删除(0x12)与刷屏(0x24)共用：

1. **优先真实索引**，且要求该槽位在固件掩码里确实有图；指向空位说明设备侧早被删掉，返回 -1 跳过。
2. 无索引才**回退推算**，且推算前剔除「已被其它照片真实索引钉住」的槽位，排队的也只剩同样无索引的照片。

## 四、⚠️ 0 是合法槽位

相框第一个位置就是 0。判空一律 `>= 0` / `< 0`，**绝不能用真假值**（`if (!index)`、`index || 默认值`）——否则每台相框第一个位置上的照片永远删不掉、刷不到，而且「投三张删后两张」完全测不出来。Dart 这边靠 `int?` + 显式 -1 表达，比小程序的 `undefined/null/''` 三重判定干净。

## 五、与小程序的有意差异

| 点 | 小程序 | App | 理由 |
| --- | --- | --- | --- |
| 真实索引是否校验掩码 | 直接返回 | 要求 `occupied` 含该槽位，否则 -1 | 空槽位塞进 0x12 可能被固件按「图片不存在」整批拒掉，导致用户一张都删不掉 |
| `claimed` 取值范围 | 全部在库照片 | 只取**同一设备**的照片 | 跨设备槽位号互不相干，混进来会误剔除本机候选（多设备下小程序会偏） |
| 候选为空时 | `return pos` | `occupied` 空才回退 `pos`，否则 -1 | 有图但槽位全被钉住 = 本张在设备上没有立足之处，硬套 `pos` 会撞上别人的图 |
| 设备匹配 | userProductId → 设备名 → 退化全部 | 只按 `deviceId` | App 每行都有后端 `userProductId`，不需要按名兜底 |

## 六、未处理（与小程序一致，有意保留）

问题 A（删除半成功产生幽灵记录 → 删错图）、B（记账失败 → 孤儿占位）、C（回滚失败 → 孤儿占位）、D（幽灵记录刷错图）**本轮均未处理**，两端同源。

其中 **A 是唯一解在后端**：需要「同一设备下一个位置号只能属于一条记录，新记录写入某 imgIndex 时清空旧的同位置记录」的唯一性规则，前端不需要任何配合。App 侧的掩码校验（见差异表第一行）能挡住幽灵指向**空位**的情况，但挡不住幽灵指向**已被新图占用**的位置——那种情况仍会删错，等后端唯一性规则。
