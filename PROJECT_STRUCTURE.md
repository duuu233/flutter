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
| 文件 | 页面/组件 | 说明 |
| --- | --- | --- |
| `home_page.dart` | `HomePage` | 首页：设备绑定与投屏核心流程 |
| `home_device_pages.dart` | `FigmaHomeUnboundDevicePage` / `FigmaHomeBoundDevicePage` | 首页（未绑定 / 已绑定）的 Figma 还原页 |
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
- **设计基准**：页面以 375×812 设计稿坐标还原，登录页等用背景全屏铺满 + 表单等比缩放适配。
- **共享控件**：Figma 通用控件统一放 `shared/widgets/figma_common.dart`、`home_figma_common.dart`，
  跨模块以包导入 `package:BoltStar/src/shared/widgets/...` 引用。
- **测试**：`test/frame_device_protocol_test.dart`（设备协议）、`test/widget_test.dart`（Widget）。

## 待办 / 可继续优化

- **未接入导航的“孤儿”页面**（路由已定义但应用内无入口，多为早期原型，可评估删除或接入）：
  `AlbumPage`(`/album`)、`DevicesPage`(`/devices`)、`CastManagementPage`(`/cast-management`)、
  `FigmaHomeUnbound/BoundDevicePage`、`ProfileBound/UnboundEmailPage`、各 `PhotoPreview*` 与
  `Casting/CastSuccess/CastFailed`、`ModifyPassword` 等。
- **同领域的“真实数据版 vs Figma 版”**仍并存（如 `DevicesPage` vs `MyDevicesPage`、
  `CastManagementPage` vs `CastManagementFigmaPage`），建议后续各保留一个。
