# 星币套餐卡赠送角标位置统一与卡片收窄

> 状态：Historical
> 日期：2026-09-08
> 环境：SSH 开发机
> 分支与起始版本：main / 03c985a
> 范围：APP 星币管理页面的套餐卡

## 变更

### 1. 赠送角标：选中与未选中位置一致

原来两种状态画在两处：未选中走 Column 里那格 `SizedBox` 内的右对齐橙色文字，选中才由
`Positioned` 贴到卡片右上角，点选时角标会跳一下。现在统一由 `Positioned` 渲染
（条件从 `package.gift > 0 && selected` 放宽成 `package.gift > 0`），几何完全相同，
只有 `decoration.color` 与文字颜色跟着 `selected` 变：未选中透明底橙字，选中橙底白字。

⚠️ Column 里那格 `SizedBox(height: _giftSlotHeight)` **保留为纯占位**：角标恒为 `Positioned`、
不占高，而卡片内容是 `MainAxisAlignment.center`，占位一旦删掉，有赠送和无赠送的卡片内容会差半格。

### 2. 卡片收窄，右侧留白变少

卡片宽度 150 → **138**（对应小程序 276rpx）。150 是上一轮为六位金额留的余量，实测右侧空得明显。
主价格整行本来就包在 `FittedBox(scaleDown)` 里，放不下会自动缩、不会截断，所以收窄不影响
「六位整数 + 两位小数完整展示」这条要求；原价行同样在 `FittedBox` 内。

## 同步与验证

修改前在 main 执行 `git pull --ff-only`，结果 Already up to date，未切分支。

⚠️⚠️ **本轮完全没有验证**：SSH 开发机没有 Flutter / Dart SDK，`flutter analyze`、`flutter test`、
`dart format` 一个都没跑。恢复到有 SDK 的机器后必须补跑，尤其 `test/star_purchase_test.dart`
（该用例文件从 2026-09-08 的原价接入起就一直没被执行过）。

真机未验。需要核对：有赠送 / 无赠送 × 选中 / 未选中四种卡片的角标位置与内容对齐、
六位金额在 138 宽下的缩放结果、横向列表的滚动手感。

## 后续与回滚

小程序端同一套改法，见 `photo-album/docs/changes/2026-09-08-星币套餐卡角标与宽度.md`。
需要回滚时 revert 本次提交，仅套餐卡布局受影响。
