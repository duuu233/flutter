# 星币管理原价字段接入

> 状态：Historical
> 日期：2026-09-08
> 环境：SSH 开发机
> 分支与起始版本：main / 5d5bb1e（本轮提交 9ccc387）
> 范围：APP 星币管理页面套餐卡的划线原价

## 变更

套餐卡的划线金额由上一轮的静态 `￥0.01` 改为接口下发的原价。`StarPackage` 新增可空字段 `marketAmount` 与展示文本 `marketAmountText`（`currencySymbol` + 两位小数），页面删除常量 `_referencePriceText`，改渲染 `package.marketAmountText`。原价**只用于展示，不参与支付金额计算**，`price` 仍是唯一下单依据。

取值口径（`StarPackage._readMarketAmount`）：

- 按解析时的语种码取字段，0/1 英文 `marketAmountEnglish`、2 简中 `marketAmount`、3 繁中 `marketAmountFan`、4 日文 `marketAmountJapanese`；语种专属字段不存在时回落 `marketAmount`，兼容服务端已按语种投影的响应。
- 语种专属字段存在但为空/非法时**不跨语种回退**，避免把别的币种金额贴到当前语种上。
- `0` 是有效金额照常展示；缺失、非数值、负数、非有限数一律为 `null`，卡片留空位不显示虚构金额。

展示上把原价行包进固定高度 `SizedBox(height: 11)` + `FittedBox(scaleDown)`：无原价时保留占位、卡片内容不跳动，长金额按需缩放完整展示，沿用原灰色与删除线。

## 同步与验证

修改前在 main 执行 `git pull --ff-only`。

⚠️ **本轮在 SSH 开发机上补写本记录，该机器没有 Flutter / Dart SDK**：`flutter test test/star_purchase_test.dart`、`flutter analyze` 与 `dart format` **均未执行**，代码级验证结果未知，不能视为通过。`test/star_purchase_test.dart` 随 9ccc387 一并提交，覆盖四语种、零值、非法值、缺失值与六位金额，但**尚未在任何机器上跑过本轮版本**，恢复到有 SDK 的环境后必须补跑。

真机与视觉验收未执行；需核对原价缺失、0、999999.99、四语种与卡片选中态。

## 后续与回滚

服务端一次返回四语种原价、还是按语种投影到 `marketAmount`，端上两种都兼容；接口契约明确后可收敛为实际形态。小程序端采用同一展示口径，见 `photo-album/docs/changes/2026-09-08-星币管理原价字段接入.md`。需要回滚时 revert 9ccc387，接口与支付数据未被修改。
