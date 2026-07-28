# BoltStar Flutter App

> 文档类型：Project Overview  
> 状态：Active  
> 最后核验：2026-07-28

BoltStar 是一款面向智能相框的 Flutter App，产品目标平台为 Android 与 iOS。当前工程已接入
BoltFox 后端、真实 BLE 设备链路、图片上传与设备投屏，不再是本地模拟原型。

主要能力：

- 账号：邮箱注册/登录、移动应用微信登录、资料、密码、邮箱、退出与注销。
- 设备：扫描、绑定、完整设备 ID 验身、连接、轮播、一键清空、解绑、OTA。
- 投屏：拍照/相册、多图预览、常驻编辑层、后端六色帧转换、BLE 图传与结果回写。
- 内容：图库、投屏记录、FAQ/操作指南和简中、繁中、英文、日文四语种。
- 工程诊断：BLE 调试台、正式包内 iOS 投屏性能自检、Android 崩溃现场记录。
- AI：星宝对话与图片增强代码已接入；正式用户入口当前由功能开关屏蔽，调试入口保留。

Android 的投屏选图、AI 选图与头像更换统一使用系统 Photo Picker，仅读取用户主动选择的图片；
应用不申请整个相册的媒体读取权限。

## 文档与代码知识

- [项目架构](architecture/PROJECT_STRUCTURE.md)
- [文档目录与维护规则](README.md)
- [打包发布](runbooks/BUILD_RELEASE.md)

查询当前符号、调用链和改动影响时使用 CodeGraph；产品决策、协议语义和人工操作步骤以
Active Markdown 为准。

## 运行

```bash
flutter pub get
flutter run
```

分析与测试：

```bash
dart analyze lib test
flutter test
```

正式构建所需的签名、微信参数和平台前置条件统一见发布 Runbook。仓库包含 Flutter 默认生成的
Web、Windows、macOS、Linux 平台壳，但这些不是当前产品发布目标；OpenHarmony/HAP 尚未接入。
