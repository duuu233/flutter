# Android 纯 Photo Picker 迁移

> 文档类型：Historical Change Record  
> 状态：Historical  
> 日期：2026-07-28

## 背景

此前相册入口虽然使用系统选择界面，但会在打开前调用
`PermissionGate.ensurePhotoAccess`，并在 Android 申请 `READ_MEDIA_IMAGES`、
`READ_MEDIA_VISUAL_USER_SELECTED` 或 `READ_EXTERNAL_STORAGE`。该行为扩大了应用可读取的
照片范围，也使相册选择不属于纯 Photo Picker 模式。

本记录替代 `APP_VS_MINIPROGRAM_SYNC_LOG.md` 中“照片权限前置授权”作为当前实现结论；
旧文档仍保留为当时的历史行为。

## 本次调整

- `main()` 在 `runApp()` 前全局设置
  `ImagePickerAndroid.useAndroidPhotoPicker = true`。
- 投屏、AI、首页头像和资料头像不再经过照片权限门禁。
- 删除 Dart、Android 和 iOS 原生通道中的 `requestPhotoPermission` 状态与请求逻辑。
- Android Manifest 删除 `READ_MEDIA_IMAGES`、
  `READ_MEDIA_VISUAL_USER_SELECTED` 和 `READ_EXTERNAL_STORAGE`。
- Android 相册入口仅获得用户主动选中图片的访问权；不直接读取整个 MediaStore 图片库。

## 保留行为

- 投屏相册仍支持最多 5 张，AI 对话按剩余名额最多选择 4 张。
- 选图阶段的尺寸和 JPEG 质量控制保持不变。
- 拍照仍由系统相机权限控制。
- Android 旧系统由 AndroidX Photo Picker 契约选择可用的系统回退界面，仍保持选择范围授权，
  不恢复媒体整库读取权限。

## 验收

- `dart analyze lib test` 无编译错误，仍有项目既有的 40 项 warning/info。
- Android Debug APK 构建成功，合并及打包后的 Debug Manifest 均不含媒体整库读取权限。
- 自动化测试为 49 项通过、1 项首页恢复时序断言在全量并行执行时失败；该用例单独复跑通过，
  与相册链路无关。
- CodeGraph 已同步且状态为 up to date。
- Android 13/14 的权限弹窗与多选上限仍需 release 真机回归。
