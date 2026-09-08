# 星币管理套餐价格展示

> 状态：Historical
> 日期：2026-09-08
> 环境：公司电脑
> 分支与起始版本：main / d20c591
> 范围：APP星币管理页面，与另一客户端同步展示要求

## 变更

套餐卡原“约单价/星币”改为静态 ￥0.01 并加删除线，保留原灰色、字号和上下间距。该金额仅为展示占位，不参与套餐售价或支付计算；后续按确认的接口字段替换，不猜测字段名。

卡片加宽为150dp，主价格整行使用 FittedBox 按需缩小，用于完整展示至少六位整数及两位小数。保留横向滚动、选中样式及赠送角标占位。确认购买页和支付逻辑保持原有规则。

## 同步与验证

修改前已在 main 执行 git pull --ff-only，结果 Already up to date，并同步本机 CodeGraph。
`flutter analyze --no-pub lib/src/features/star/presentation/star_coin_page.dart`：无问题。
`flutter test test/star_purchase_test.dart`：31 项通过。
真机视觉验收未执行；需核对 999999.99、普通金额、选中与未选中卡片及窄屏横滑。

## 后续与回滚

静态划线金额等待正式接口字段。另一客户端采用相同展示需求，各自维护代码及文档。用户已授权完成后 commit 和 push；交付结果以 Git 提交及任务回复为准。需要回滚时 revert 本次提交，接口与支付数据未被修改。
