# 项目目录结构说明（BoltStar）

BoltStar 是一个 Flutter 智能相框 App。整体采用 **按业务领域分模块（feature-first）** 的结构：
每个业务模块放在 `lib/src/features/<feature>/presentation/` 下，公共能力（状态、设备协议、
通用组件、主题、路由）集中在 `lib/src/` 顶层目录。包名为 `BoltStar`。

> 说明：项目页面以 375×812 Figma 设计稿坐标还原。早期曾把所有还原页面放在一个
> `figma_generated/` 目录里（按“来源”分组），现已 **按业务领域拆分并入各 feature**，
> 同一领域不再出现两套平行目录。Figma 通用控件下沉到 `shared/widgets/`。

---

## 顶层目录（项目根）

| 路径 | 说明 |
| --- | --- |
| `lib/` | Dart 源码（核心，见下文） |
| `assets/images/` | 图片资源（登录背景、Logo、设备插画等） |
| `test/` | 单元测试与 Widget 测试 |
| `android/` `ios/` `web/` `windows/` `macos/` `linux/` | 各平台原生工程 |
| `pubspec.yaml` | 依赖与资源声明 |
| `analysis_options.yaml` | 静态分析（lint）规则 |
| `build/` | 构建产物（自动生成，不纳入版本管理） |
| `PROJECT_STRUCTURE.md` | 本文档 |
| `README.md` | 项目说明 |

---

## `lib/` 源码结构

```
lib/
├── main.dart                     # 程序入口：设置系统状态栏样式并 runApp(BoltStarApp)
└── src/
    ├── app.dart                  # 对外导出 app 层（导出 BoltStarApp）
    ├── state.dart                # 全局业务状态 PhotoFrameState 与数据模型/枚举
    ├── native_device_api.dart    # 与原生层交互的设备/权限 API（蓝牙、相册、相机等）
    │
    ├── app/
    │   ├── bolt_star_app.dart     # 应用根组件：创建全局状态、挂主题、配置 home 与命名路由
    │   └── app_theme.dart         # 全局主题 buildAppTheme()
    │
    ├── routes/
    │   └── app_routes.dart        # 统一命名路由表：路由常量 + onGenerateRoute 分发
    │
    ├── device/
    │   └── frame_device_protocol.dart  # 相框设备 BLE 通信协议（屏型、播放模式、指令/结果码）
    │
    ├── shared/                    # 跨模块复用的通用组件与工具
    │   ├── shared.dart            # 统一导出
    │   ├── dialogs/
    │   │   └── prompt_text.dart   # 文本输入对话框 promptText()
    │   └── widgets/
    │       ├── app_widgets.dart       # 通用面板 AppPanel 等
    │       ├── background.dart        # 氛围渐变背景 AtmosphereBackground
    │       ├── scaffolds.dart         # 通用子页脚手架 SubPageScaffold
    │       ├── figma_common.dart      # Figma 还原页面公共控件（手机外框/状态栏/按钮/输入框…）
    │       └── home_figma_common.dart # Figma 首页 & 绑定设备流程的公共控件
    │
    └── features/                  # 业务模块（按领域划分，见下文）
```

---

## `lib/src/features/` 业务模块

每个模块均为 `features/<domain>/presentation/`。下表列出主要页面（部分模块还含 `widgets/` 子目录）。

### `shell/` — 主导航壳层
| 文件 | 页面 | 说明 |
| --- | --- | --- |
| `shell_page.dart` | `AppShell` | 底部导航在「首页 / 我的 / Demo」之间切换 |

### `home/` — 首页
`HomePage` 拆分为同一 library 下的多个 `part` 文件，按职责浏览；样式以微信小程序
`photo-album/pages/home` 为准精准还原（详见文末「改造进度」）。

| 文件 | 页面/组件 | 说明 |
| --- | --- | --- |
| `home_page.dart` | `HomePage` | 首页主入口：场景状态机（已绑定/未绑定/绑定流程/各弹层）与所有交互逻辑 |
| `home_main_view.dart` | `_HomeMainView`（part） | 首页主视图（已绑定 / 未绑定），含顶部「首页」标题栏、问候语、设备卡、投屏入口 |
| `home_bind_device_view.dart` | `_BindDeviceView`（part） | 绑定设备流程视图（搜索中 / 未发现 / 已发现） |
| `home_sheets.dart` | 各 `_*Sheet`（part） | 底部弹层（提示 / 选择投屏方式 / 扫描帮助） |
| `home_widgets.dart` | 展示型叶子组件（part） | 背景、头像、设备卡、投屏卡、底部 Tab 栏、电量图标映射等 |
| `home_text_styles.dart` | `_HomeTextStyles`（part） | 首页统一文字样式（字号/颜色/字重对齐小程序 rpx÷2） |
| `widgets/draft_picker_sheet.dart` | `DraftPickerSheet` | 草稿选择底部弹层 |
| `widgets/cast_preview_sheet.dart` | `CastPreviewSheet` | 投屏预览底部弹层 |
| `widgets/native_permission_panel.dart` | `NativePermissionPanel` | 原生权限申请面板 |

### `mine/` — 我的
| 文件 | 页面 | 说明 |
| --- | --- | --- |
| `mine_page.dart` | `MinePage` | 个人中心（含调试入口） |

### `account/` — 账户与个人资料
| 文件 | 页面 | 说明 |
| --- | --- | --- |
| `auth_page.dart` | `AuthPage` | **应用唯一登录页**（邮箱密码，路由 `/auth`，退出登录/注销后进入） |
| `register_page.dart` | `RegisterPage` | 创建账户/注册 |
| `forgot_password.dart` | `ForgotPassword` | 忘记密码/重置密码 |
| `modify_password.dart` | `ModifyPassword` | 修改密码 |
| `profile_page.dart` | `ProfilePage` | 账户资料 |
| `profile_unbound_email_page.dart` | `ProfileUnboundEmailPage` | 账户资料（未绑定邮箱） |
| `profile_bound_email_page.dart` | `ProfileBoundEmailPage` | 账户资料（已绑定邮箱） |
| `bind_email_incomplete_page.dart` | `BindEmailIncompletePage` | 绑定邮箱（未填写完整） |
| `bind_email_complete_page.dart` | `BindEmailCompletePage` | 绑定邮箱（已填写完成） |
| `modify_email_page.dart` | `ModifyEmailPage` | 修改邮箱 |

### `devices/` — 设备与绑定
| 文件 | 页面 | 说明 |
| --- | --- | --- |
| `devices_page.dart` | `DevicesPage` | 设备列表（接入真实数据，包装 `MyDevicesPage`） |
| `my_devices_page.dart` | `MyDevicesPage` | 我的设备列表（Figma 还原） |
| `device_details_page.dart` | `DeviceDetailsPage` | 设备详情 |
| `carousel_settings_page.dart` | `CarouselSettingsPage` | 轮播设置 |
| `device_delete_confirm_page.dart` | `DeviceDeleteConfirmPage` | 删除设备确认 |
| `device_clear_confirm_page.dart` | `DeviceClearConfirmPage` | 清空设备内容确认 |
| `bind_device_searching.dart` | `BindDeviceSearching` | 绑定设备-搜索中 |
| `bind_device_found.dart` | `BindDeviceFound` | 绑定设备-发现设备 |
| `bind_device_not_found.dart` | `BindDeviceNotFound` | 绑定设备-未发现设备 |
| `bind_device_scan_help.dart` | `BindDeviceScanHelp` | 绑定设备-扫码帮助 |

### `cast/` — 投屏
| 文件 | 页面 | 说明 |
| --- | --- | --- |
| `cast_management_page.dart` | `CastManagementPage` | 投屏管理（接入真实数据版） |
| `cast_management_figma_page.dart` | `CastManagementFigmaPage` | 投屏管理（图库样式 Figma 版，当前 `/我的` 入口使用） |
| `photo_preview_adjust_image_page.dart` | `PhotoPreviewAdjustImagePage` | 照片预览-裁剪调整 |
| `photo_preview_saved_page.dart` | `PhotoPreviewSavedPage` | 照片预览-已保存 |
| `casting_progress_page.dart` | `CastingProgressPage` | 投屏进行中 |
| `cast_success_page.dart` | `CastSuccessPage` | 投屏成功 |
| `cast_failed_page.dart` | `CastFailedPage` | 投屏失败 |

### `gallery/` — 图库
| 文件 | 页面 | 说明 |
| --- | --- | --- |
| `gallery_page.dart` | `GalleryPage` | 图库：照片网格、筛选、批量操作 |

### `album/` — 相册
| 文件 | 页面 | 说明 |
| --- | --- | --- |
| `album_page.dart` | `AlbumPage` | 相册：浏览/管理本地照片 |

### `settings/` — 设置
| 文件 | 页面 | 说明 |
| --- | --- | --- |
| `settings_page.dart` | `SettingsPage` | 设置（含退出登录 / 注销） |
| `language_settings_page.dart` | `LanguageSettingsPage` | 语种设置 |
| `privacy_policy_page.dart` | `PrivacyPolicyPage` | 隐私政策 |
| `user_agreement_page.dart` | `UserAgreementPage` | 用户协议 |
| `legal_document_view.dart` | `LegalDocumentView` | 协议/政策正文通用展示组件 |
| `update_boltstar_page.dart` | `UpdateBoltStarPage` | 固件/App 更新（多状态） |

### `guide/` — 帮助 / `demo/` — 演示
| 文件 | 页面 | 说明 |
| --- | --- | --- |
| `guide/presentation/guide_page.dart` | `GuidePage` | 使用帮助/引导 |
| `demo/presentation/demo_page.dart` | `DemoPage` | 图片裁剪/编辑能力试验页 |

---

## 关键约定

- **路由**：所有页面在 `lib/src/routes/app_routes.dart` 中以命名路由维护；新增页面补充路由常量
  与 `switch` 分支即可。（注：历史遗留的 `figma*` 路由常量名仅为内部标识，可后续按需重命名。）
- **状态**：全局业务数据由 `PhotoFrameState`（`state.dart`）持有，在 `BoltStarApp` 中创建后
  向下传递；页面不要各自创建状态实例。
- **布局方式**：页面采用**弹性 / 响应式布局**（`SafeArea` + `Column/Row/Flex` + `Spacer`），
  适配不同屏幕、刘海与系统字号；不再使用整页画布缩放（旧的 `FigmaPhoneFrame` / `Transform.scale`
  已移除）。带顶部导航的页面统一用 `shared/widgets/figma_common.dart` 的 `FigmaScreen` 脚手架
  （`title` / `body` / `bottom` / `trailing`），登录页用全屏背景 + `SafeArea` 自定义实现。
- **共享控件**：Figma 通用控件统一放 `shared/widgets/figma_common.dart`、`home_figma_common.dart`，
  跨模块以包导入 `package:BoltStar/src/shared/widgets/...` 引用。
- **测试**：`test/frame_device_protocol_test.dart`（设备协议）、`test/widget_test.dart`（Widget）。

## 待办 / 可继续优化

- **未接入导航的“孤儿”页面**（路由已定义但应用内无入口，多为早期原型，可评估删除或接入）：
  `AlbumPage`(`/album`)、`DevicesPage`(`/devices`)、`CastManagementPage`(`/cast-management`)、
  `ProfileBound/UnboundEmailPage`、各 `PhotoPreview*` 与
  `Casting/CastSuccess/CastFailed`、`ModifyPassword` 等。
- **同领域的“真实数据版 vs Figma 版”**仍并存（如 `DevicesPage` vs `MyDevicesPage`、
  `CastManagementPage` vs `CastManagementFigmaPage`），建议后续各保留一个。

---

## 改造进度（对照微信小程序 `photo-album` 还原）

> 背景：本 App 与微信小程序 `D:\Work\learn\photo-album` 功能一致，仅登录方式不同
> （App 为邮箱密码，小程序为微信快捷登录）。两个项目 `assets/images/` 资源**完全同名同图**，
> 以小程序为视觉基准逐页精准还原。换算约定：小程序 1rpx ≈ 0.5 逻辑像素（750rpx=屏宽）。
> 每完成一项在此追加记录。

### 首页 `home`（对照 `photo-album/pages/home`）— ✅ 已完成（2026-06-02）
- **根因修复**：此前首页引用的是一批已删除的旧命名资源（`Group 194746.png`、
  `Rectangle 10457.png`、`Group 19452x.png`、`Frame.png` 等），运行时全部走 `errorBuilder`
  手绘兜底，与设计稿偏差大。现已全部改用与小程序一致的真实资源。
- **资源对齐**：
  - 头像 `mine-header.png`（36，白底圆形）、右上「+」`home-add-icon.png`；
  - 已绑定设备卡底图 `home-bg01.png`（702×420rpx）+ 圆环 `home-icon02.png` +
    蓝牙图标 `bluetooth-icon.png` + 电量图标 `BatteryLevel/battery-{档}.png`（就近取整，
    逻辑同小程序 `utils/battery.js`）；
  - 投屏卡底图 `home-camera-card-bg.png` / `home-album-card-bg.png`（366×358rpx），
    素材 `camera_material.png` / `album_material.png`（132rpx），箭头
    `home-camera-card-right-icon.png` / `home-album-card-right-icon.png`（118rpx）；
  - 选择投屏方式弹层素材改 `home-media-mini01/02.png` + 圆形箭头；
  - 底部 Tab 改用 `tabbar-home02.svg` / `tabbar-mine01.svg`（白色半透明胶囊 + 柔和投影）。
- **样式对齐**：新增顶部居中「首页」标题栏；问候语「BoltStar」改为橙色加粗文字
  （#ff7a2e/22/w800，非图片）；字号颜色按小程序 wxss 重设（见 `home_text_styles.dart`）；
  轮播指示点按已连接设备数渲染（17×4、间距 12、选中 #ff6922）；横向留白分区设置
  （文字区 24、卡片区 12）。
- **配置**：`pubspec.yaml` 补充声明 `assets/images/BatteryLevel/`（Flutter 资源目录不递归）。
- **涉及文件**：`home_main_view.dart`、`home_widgets.dart`、`home_text_styles.dart`、
  `home_sheets.dart`、`home_page.dart`（引入 `flutter_svg`）、`pubspec.yaml`。
- **校验**：`flutter analyze lib` 通过（仅 2 条与本次无关的既有 info 提示）。
