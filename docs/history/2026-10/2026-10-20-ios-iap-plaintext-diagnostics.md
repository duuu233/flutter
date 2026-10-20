# 2026-10-20 iOS 支付诊断日志支持验单参数明文输出

> 类型：Historical Diagnostic Record
> 环境：work；main；开始前已显式同名 pull 成功，工作区干净。
> 依据：用户要求直接在 APP 苹果支付日志中输出真实 `responseData` 与完整请求入参明文，便于复制提供给后端自测定位。

## 变更与实现

1. `lib/src/features/star/apple_iap.dart`：
   - `AppleReceiptVerification` 增加 `rawResponseData` 与 `exceptionMsg` 解析字段。
   - `verify.request` 阶段诊断中增加完整 `receiptData` 明文字段。
   - `verify.response` 阶段诊断中增加 `responseData`（后端返回原始数据）与 `exceptionMsg`（异常信息）明文字段。
2. `lib/src/features/star/apple_iap_diagnostics.dart`：
   - 区分商品预检脱敏与验单调试字段，在 `verify.request` 与 `verify.response` 阶段显式放行 `receiptData`、`responseData` 与 `exceptionMsg` 的明文输出及完整长度展示，不进行通用 600 字符截断或掩码，确保可直接复制给后端用于调试。
   - 保留商品预检阶段、系统错误异常中的敏感字段掩码保护。
3. `test/apple_iap_reorder_test.dart`：
   - 同步更新测试断言，验证 `verify.request` 中包含明文凭证。

## 验证与测试

- Flutter 3.44.6 本机运行 `flutter test test/apple_iap_test.dart test/apple_iap_product_diagnostics_test.dart test/apple_iap_reorder_test.dart --no-pub` 全部 57 项测试通过。
- `flutter analyze` 静态分析通过，0 error，0 warning。
- CodeGraph 同步完成。