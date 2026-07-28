# 项目目录结构说明（BoltStar）— 2026-07 历史快照

> 文档类型：Historical Architecture Snapshot  
> 状态：Historical  
> 归档日期：2026-07-28  
> 当前架构以 `../../architecture/PROJECT_STRUCTURE.md` 和 CodeGraph 为准。本文保留当时的改造进度、
> 待办和操作日志，不再作为当前目录或模块清单。

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
    │   └── widgets/
    │       ├── app_widgets.dart       # PageLoading / PageLoadError / AppLoadingDialog（加载三件套）
    │       ├── app_toast.dart         # 全局 toast
    │       ├── figma_common.dart      # Figma 还原页面公共控件（手机外框/状态栏/按钮/输入框…）
    │       └── home_figma_common.dart # Figma 首页 & 绑定设备流程的公共控件
    │   （2026-07-17 清理：shared.dart 桶文件、dialogs/prompt_text、background、
    │     scaffolds 及 app_widgets 内 8 个旧首页组件均为 0 引用死代码，已删除）
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
| `cast_preview_page.dart` | `CastPreviewPage` | 真实投屏预览：多图、裁剪、旋转、原图还原、按设备分辨率裁切+缩放（`coverCropToSize`，480×720/680×960） |
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
  `AlbumPage`(`/album`)、`CastManagementPage`(`/cast-management`)、
  `ProfileBound/UnboundEmailPage`、各 `PhotoPreview*` 与
  `Casting/CastSuccess/CastFailed` 等。
  （已过时项已剔除：`/devices` 死路由 2026-07 已删除，`DevicesPage` 类仍经 `figmaMyDevices` 使用、非孤儿；
  `ModifyPassword` 已由个人信息页「修改密码」入口接入、非孤儿；`UpdateBoltStarPage` 已由设置页
  「检测更新」入口接入、非孤儿。）
- **同领域的“真实数据版 vs Figma 版”**仍并存（如 `DevicesPage` vs `MyDevicesPage`、
  `CastManagementPage` vs `CastManagementFigmaPage`），建议后续各保留一个。

---

## 改造进度（对照微信小程序 `photo-album` 还原）

> 背景：本 App 与微信小程序 `D:\Work\learn\photo-album` 功能一致，登录流程按平台区分
> （App 为邮箱密码 + 移动应用微信授权，小程序为微信小程序快捷登录）。两个项目 `assets/images/` 资源**完全同名同图**，
> 以小程序为视觉基准逐页精准还原。换算约定：小程序 1rpx ≈ 0.5 逻辑像素（750rpx=屏宽）。
> 每完成一项在此追加记录。

### 首页 `home`（对照 `photo-album/pages/home`）— ✅ 已完成（2026-06-02）
- **根因修复**：此前首页引用的是一批已删除的旧命名资源（`Group 194746.png`、
  `Rectangle 10457.png`、`Group 19452x.png`、`Frame.png` 等），运行时全部走 `errorBuilder`
  手绘兜底，与设计稿偏差大。现已全部改用与小程序一致的真实资源。
- **资源对齐**：
  - 头像 `mine-header.jpg`（36，白底圆形）、右上「+」`home-add-icon.png`；
  - 已绑定设备卡底图 `home-bg01.png`（当前卡片 654×298rpx）+ 圆环 `home-icon02.png`（166rpx）+
    蓝牙图标 `bluetooth-icon.png` + 电量图标 `BatteryLevel/battery-{档}.png`（就近取整，
    逻辑同小程序 `utils/battery.js`）；
  - 投屏卡底图 `home-camera-card-bg.png` / `home-album-card-bg.png`（366×358rpx），
    素材 `camera_material.png` / `album_material.png`（132rpx），箭头
    `home-camera-card-right-icon.png` / `home-album-card-right-icon.png`（118rpx）；
  - 选择投屏方式弹层素材改 `home-media-mini01/02.png` + 圆形箭头；
  - 底部 Tab 改用 `tabbar-home02.svg` / `tabbar-mine01.svg`（白色半透明胶囊 + 柔和投影）。
- **样式/交互对齐**：新增顶部居中「首页」标题栏；问候语使用 `logo.png`；字号颜色按小程序
  wxss 重设（见 `home_text_styles.dart`）。设备区按全部已绑定设备循环轮播（17×4 指示点、间距 12、
  选中 #ff6922），断连卡隐藏电量并显示蓝色「连接蓝牙」按钮；点卡片进入设备列表，点头像可即时更新。
- **配置**：`pubspec.yaml` 补充声明 `assets/images/BatteryLevel/`（Flutter 资源目录不递归）。
- **涉及文件**：`home_main_view.dart`、`home_widgets.dart`、`home_text_styles.dart`、
  `home_sheets.dart`、`home_page.dart`（引入 `flutter_svg`）、`pubspec.yaml`。
- **校验**：`flutter analyze lib` 通过（仅 2 条与本次无关的既有 info 提示）。

### 「我的」`mine`（对照 `photo-album/pages/mine`）— ✅ 已完成（2026-06-02）
- **根因修复**：此前引用已删除的旧命名资源（`Group 194925/194926/194927/194799/194928.png`、
  头像用 `logo.png`），全部走手绘兜底；现改用与小程序一致的真实资源。
- **资源对齐**：
  - 背景改 `bg01.png`（小程序 mine 用 bg01，非 bg02）；
  - 资料卡底图 `mine-header-bg01.png` + 头像 `mine-header.jpg`（112rpx≈56 圆形）；
  - 常用功能卡底图 `mine-bg02.png` + 112rpx 圆形底托 + `mine-icon06/07/08.png`（68rpx≈34）；
  - 服务行图标 `mine-icon05.png`（操作指南）/ `mine-icon04.png`（设置）（52rpx≈26）；
  - 底部 Tab 改 `tabbar-home01.svg` / `tabbar-mine02.svg`（与首页同款胶囊）。
- **样式对齐**：资料卡高 89、圆角 18；昵称改「江江江」(20/w700)、ID(12/#808690)；
  常用功能宫格整宽 space-evenly、卡片 102×148、圆角 20；服务行高 54、圆角 11；
  右侧箭头改用「›」字形（#777e88）；字号颜色按 wxss 重设（见文件内 `_MineTextStyles`）。
- **涉及文件**：`mine_page.dart`（引入 `flutter_svg`）。
- **校验**：`flutter analyze lib/src/features/mine` 通过（No issues）。

### 个人资料 `profile`（对照 `photo-album/subpackages/settings/profile`）— ✅ 已完成（2026-06-02）
- **共享脚手架对齐**（`shared/widgets/figma_common.dart`，惠及所有用 `FigmaScreen` 的
  设置/账户/设备/投屏页面）：
  - `FigmaScreenBackground` 改用 `bg01.png` 铺满（小程序 `.mock-bg__image`，回退渐变）；
  - 导航标题 `navigationTitle` 改 #111111 / 17 / w700（`.mock-nav__title`）；
  - `FigmaPrimaryButton` 改胶囊（圆角全圆）+ 渐变 #ff8b3d→#ff641f + 文案 17/w700（`.settings-primary`）；
  - `FigmaGlassCard` 改圆角 14、白 0.55 + 柔和投影（`.glass-panel`）；
  - `FigmaAccountField` 新增可选 `trailing`（供昵称行放编辑图标）。
- **profile 专属**：头像行用 `mine-header.jpg`（64rpx≈32 圆形）；昵称行加 `edit-icon01.png`
  编辑图标；右侧箭头色 #777e88。结构（头像/昵称/ID/邮箱 + 保存资料）本就对齐，未改路由逻辑。
- **涉及文件**：`figma_common.dart`、`profile_page.dart`。
- **校验**：`flutter analyze lib` 通过（仅 2 条与本次无关的既有 info）。
- **附带收益**：因共享层已对齐，注册/忘记密码/改密/改邮箱/绑定邮箱/各 `settings` 子页的
  背景、主按钮、玻璃卡、导航标题已同步贴近小程序；后续这些模块主要核对**专属图标与文案**即可。

### 设备列表 `device/list`（对照 `photo-album/subpackages/device/list`）— ✅ 已完成（2026-06-02）
- **资源对齐**：设备卡 Logo 用 `device-list-icon04.png`（已连接）/ `device-list-icon05.png`（离线，92rpx≈46）；
  重命名 `edit-icon01.png`；连接状态 `bluetooth-icon.png` / `bluetooth-icon-not.png`（11×14）；
  电量 `BatteryLevel/battery-{档}.png`；操作栏 `carousel-settings-icon01.png`（轮播设置）、
  `disconnect-icon01.png`（断开）/ `bluetooth-connection.png`（连接）；添加按钮 `home-add-icon.png`（64rpx≈32）。
- **样式对齐**：添加按钮移到导航下方右对齐工具栏；卡片圆角 20、设备名 20/w700/#2a2d32；
  连接态文案 #287dff、离线 #9ba2ad、电量 #737b86；底部操作栏胶囊（白渐变 + 1px 描边）、
  分隔线 #dadddf、断开 #eb5f1b / 连接 #2079fc；整卡点击进详情、重命名/操作用独立点击区。
- **涉及文件**：`my_devices_page.dart`（顺手修一处 `unnecessary_underscores` lint）。
- **校验**：`flutter analyze lib/src/features/devices` → No issues。

### 设备详情 `device/detail`（对照 `photo-album/subpackages/device/detail`）— ✅ 已完成（2026-06-02）
- **资源对齐**：摘要卡图标 `device-list-icon01.png`（橙底圆角盒）+ 名称编辑 `edit-icon01.png` +
  连接 `bluetooth-icon.png` + 电量 `BatteryLevel/battery-80.png`；信息行图标
  `device-detail-icon01~04.png`（轮播设置/设备ID/设备内存/OTA升级，20）；操作行图标
  `device-detail-icon05.png`（一键清空 #ff6a20）/ `device-detail-icon06.png`（删除设备 #ff3045）。
- **样式对齐**：移除原多出的「MAC地址」行（小程序无）；信息行标题 #33373d/14/w600、取值 #777e88、
  「轮播设置」带箭头可点；两个确认弹窗改为小程序版式——彩色图标盒 + 左对齐标题(19/w700)/说明 +
  「取消(#eee)/确认(橙渐变)」胶囊按钮（取消/确认抽成共享 `DeviceConfirmDialog`）。
- **涉及文件**：`device_details_page.dart`（新增 `DeviceConfirmDialog`）、
  `device_delete_confirm_page.dart`、`device_clear_confirm_page.dart`。
- **校验**：`flutter analyze lib/src/features/devices` → No issues。

### 轮播设置 `device/slideshow`（对照 `photo-album/subpackages/device/slideshow`）— ✅ 已完成（2026-06-02）
- **样式对齐**：标题「开启轮播 / 轮播方式」改 #33373d/15/w700；开关改橙色轨道 #ff6a20；
  提示行用圆圈「i」徽标 + #8a9099 文案；新增中间细分割线；轮播方式单选项改**胶囊样式**
  （未选灰底 #eee/0.84，选中白底 0.1 + 橙描边）+ **自定义圆点**（未选空心环、选中橙环+实心点）、
  文案 14/w700。
- **涉及文件**：`carousel_settings_page.dart`（纯样式，保留 enabled/mode 回调逻辑）。
- **校验**：`flutter analyze lib/src/features/devices` → No issues。

### 绑定流程 `device/bind`（对照 `photo-album/pages/home` 绑定场景）— ✅ 已完成（2026-06-02）
- **资源对齐**：雷达插画按状态切换——搜索中 `search-devices.gif`（动图）、已发现
  `device_found_art.png`、未发现 `device_not_found_art.png`（移除原失败角标叠加）；
  附近设备项图标按序用 `device-list-icon01~03.png`、选中标记 `selected-icon.png`、
  刷新按钮 `refresh-icon.png`。
- **样式对齐**：雷达区 250×250；标题 scan-title 20/w700/#2a2d32、说明 #737a84；
  附近设备项改小程序 `.nearby-device`（高 64、半透明白底、选中橙描边 + 橙底浅底）、
  名称 16/w700。
- **涉及文件**：`home_bind_device_view.dart`、`home_widgets.dart`（`_BluetoothRadar` /
  `_FoundDeviceTile` 重做，移除 `_FailBadge`）、`home_text_styles.dart`（scan 样式 + 清理未用）。
- **校验**：`flutter analyze lib/src/features/home` → No issues。
- **说明**：App 内可达的绑定流程即首页内 `_BindDeviceView`；`devices/bind_device_*`、
  `bind_device_scan_help` 为未接入导航的 Figma 原型页，保持现状未动。

> ✅ **设备模块（列表 / 详情 / 轮播设置 / 绑定流程）整体完成。**

### 投屏结果 `projection/result`（对照 `photo-album/subpackages/projection/result`）— ✅ 已完成（2026-06-02）
- **说明**：小程序 `result` 一页含 progress/success/fail 三态；Flutter 拆成 `casting_progress_page`
  / `cast_success_page` / `cast_failed_page` 三页，统一对照还原。
- **资源对齐**：顶部插画按状态用 `upload-icon01.png`（进行中）/ `upload-icon03.png`（成功）/
  `upload-icon02.png`（失败），替换原手绘 `FigmaCastResultIcon`；信息卡两行图标
  `projection-result-icon01.png`（投屏设备）/ `projection-result-icon02.png`（投屏管理 + 箭头）。
- **样式对齐**：标题 40rpx(=20)/w700/#2a2d32、说明 #828a95/13/1.5；成功+失败均显示信息卡
  （小程序失败态也有）；进度条改小程序内联版式（左条 #e6ebf2 + 橙渐变填充，右侧 当前/总数）；
  主按钮胶囊（已对齐）、次按钮「返回首页」改白 0.86 胶囊 + 描边（`FigmaSecondaryButton` 一并对齐）。
- **新增**：`cast/presentation/cast_result_common.dart`（`ProjectionResultArt` / `ProjectionInfoCard`
  / `ProjectionProgress` + 标题/说明样式），三页复用。
- **涉及文件**：`cast_result_common.dart`（新）、`cast_success_page.dart`、`cast_failed_page.dart`、
  `casting_progress_page.dart`、`figma_common.dart`（`FigmaSecondaryButton` 胶囊化）。
  注：原手绘 `FigmaCastResultIcon` / `FigmaProgressBar` 已不再被这些页引用。
- **校验**：`flutter analyze lib/src/features/cast` → No issues。

### 投屏预览 `projection/preview`（对照 `photo-album/subpackages/projection/preview`）— ✅ 已完成（2026-07-14 复核）
- **真实链路**：`cast/presentation/cast_preview_page.dart`。`photo_preview_saved_page.dart` 和
  `photo_preview_adjust_image_page.dart` 仅为历史 Figma 演示页，不参与真实投屏。
- **资源对齐**：工具栏图标改 `preview-icon01/02/03.png`（裁剪/旋转/原图，22），替换 Material 图标。
- **样式对齐**：计数改图片上方浅灰胶囊（rgba(42,43,43,0.08) 底 / 文字 0.8 / 15 w600，原为图上黑色浮层）；
  图片区圆角 20、底色 #e6ecf4、占位「图片占位」#9aa1ab；工具栏玻璃面板圆角 20、文案 #777e88；
  「开始投屏」沿用胶囊主按钮。
- **功能对齐**：多图滑动、设备比例预览、裁剪、90° 旋转、还原原图、未编辑图片中心裁切、
  JPEG 92% 导出均已实现。App 用原生 `image_cropper`；上传源超过 400KB 时在 isolate 中按设备长边
  2 倍、JPEG 80 兜底压缩，接口固定 `isCompress=1`。
- **涉及文件**：`cast_preview_page.dart`、`cast_image_editor.dart`、`projection_service.dart`。
- **校验**：`flutter analyze lib/src/features/cast` → No issues。

### 投屏记录 `projection/records`（对照 `photo-album/subpackages/projection/records`）— ✅ 已完成（2026-06-02）
- **对应**：`cast/cast_management_figma_page.dart`（`/我的 → 投屏管理` 入口）。
- **样式对齐**：
  - 分段切换改**单胶囊 + 滑动指示器**（成功橙 #ff6a20 / 失败红 #ff4350，激活白字、未激活 #858b94），
    替换原两枚独立胶囊；
  - 记录卡用玻璃卡（圆角 14），缩略图 72×72/圆角 7；状态徽标改胶囊（成功 #35b856/底 #e9f8ef、
    失败 #ff3045/底 #fff0f1，11号）；时间行加 `date-icon01.png`、失败原因行加 `warning-icon01.png`
    （#ef5b50）；操作区前加细分割线，「再次/重新投屏」(#ff6a20) 与「删除」(#8b9098) 间加竖线；
  - 空态改玻璃卡 + 标题/说明（文案随成功/失败 tab 变化）。
- **涉及文件**：`cast_management_figma_page.dart`（保留 state 记录数据与 recast/delete 逻辑）。
- **校验**：`flutter analyze lib/src/features/cast` → No issues。

> ✅ **投屏模块（结果 / 预览 / 记录）整体完成。**

### 我的图库 `album/list`（对照 `photo-album/subpackages/album/list`）— ✅ 已完成（2026-06-02）
- **对应**：`gallery/gallery_page.dart`（`/我的 → 我的图库` 入口）。
- **交互模型对齐**：改为小程序的「常驻可选」——去掉原 nav「选择/取消」模式开关，
  工具栏常显「全选 + 共 N 张 + 设备筛选」，每个图块常驻选择圈，选中任意张后底部出现操作栏。
- **资源/样式对齐**：背景改 `bg02.png`（album 用 bg02）；全选 #ff5f1f、数量 #777e88；
  筛选改白 0.78 胶囊；网格 3 列、图块圆角 11、间距 7；选择圈未选空心白环 / 选中 `selected-icon.png`；
  底栏 = `del-icon.png` 圆形删除按钮 + 「已选 N 张」(N 橙) + 投屏橙渐变胶囊；
  删除弹窗改小程序版式（橙图标盒 + 左对齐标题 19/w700 + 说明 + 取消(#eee)/确认(橙渐变)）；
  空态标题 19/w700/#25282d、说明 #777e88、重新投屏胶囊主按钮。
- **涉及文件**：`gallery_page.dart`（保留 state 的相册数据 / 删除 / 投屏逻辑）。
- **校验**：`flutter analyze lib/src/features/gallery` → No issues。
- **说明**：`album/album_page.dart`（`/album`）为未接入导航的孤儿页，未动；小程序 album 子包仅 list。

### 设置 `settings`（对照 `photo-album/subpackages/settings`：index/language/guide/update/privacy/agreement）— ✅ 已完成（2026-06-02）
- **共享返回按钮对齐**（`figma_common.dart`，惠及所有 `FigmaScreen` 页面）：导航返回键由 Material
  箭头改为小程序 `page-nav` 的圆底图 `return-round-icon.png` + 箭头 `return-arrow-icon.png` 叠加
  （新增 `FigmaBackButton`，带兜底）；原 `FigmaRoundIconButton` 保留未删。
- **设置首页 `index`**（`settings_page.dart`）：
  - 拆成两张玻璃卡——第一张仅「语种设置」（橙圈 `set-icon01.png`），第二张「联系方式 / 隐私政策 /
    用户协议」（蓝圈 `set-icon02/03/04.png`，圈底 orange 8% / blue 10%）；行高 62、图标圈 32、
    标题 #2a2d32/14/w600、取值 #808690/14、右箭头改「›」(#777e88/21)；卡内分隔线 #cfd6e0/0.72 内缩 18；
  - 「联系方式」右侧改 `copy-icon01.png`，点按复制并提示「已复制联系方式」（原为弹窗，改 `Clipboard`）；
  - **「检测更新」入口**（第二张卡末行，`set-icon02.png`）：点击**跳转 `UpdateBoltStarPage`**
    （路由 `figmaUpdateBoltStar`，传 `state`），进入即真实检查版本。⚠️ 2026-07 已按需求接入,
    **不要再删**（历史上曾因"小程序该行被注释"而删除,现产品要求保留）；
    页面内保留的 `_checkUpdate` 弹窗式方法已无调用方,是可清理的死代码,与本入口无关。
  - 「退出登录」改胶囊（浅橙底 #fbf2ee/0.8 + 橙描边 #eb5f1b + 橙字 17/w700）、「用户注销」改
    #808690/15，两者移入底部固定区；确认弹窗按 `shared.wxss` 版式（标题 18/w700、说明 12/#636a74、
    取消 #eee / 确定橙渐变胶囊）。
- **语种设置 `language`**（`language_settings_page.dart`）：选中项改用 `selected-icon.png`、未选改
  #bfc4cc 空心环（26）；行高 61、标题 #2a2d32/14/w600；卡内分隔线同上。
- **隐私政策 / 用户协议 `privacy`/`agreement`**（`legal_document_view.dart`）：整篇正文置于玻璃卡，
  居中大标题 20/w700、更新/生效日期左右分布 #7e858f/12、分节标题 15/w700、正文 #2f343b/14/行高 1.55。
- **操作指南 `guide`**（`guide_page.dart`）：搜索框改胶囊 + `search-icon01.png`；FAQ 改单张玻璃卡内堆叠，
  问号图标用 `why-icon01.png`、标题 #4a505a/14；答案面板浅灰底(rgba(42,43,43,0.03))圆角 6、缩进 19、
  文案 rgba(42,43,43,0.6)/12/行高 1.66；补回「如何进行照片投屏?」一项（共 5 项，默认展开首/末）。
- **更新BoltStar `update`**（`update_boltstar_page.dart`）：Logo 用 `logo.png`（123×31）；版本行 #808690/13；
  关于文案 #2a2d32/15/行高 1.58；进度环小程序饼图样式（外圈灰 #dfe5ee + 橙 #ff762f 进度带 8px、
  内圈 #edf6ff 实心盘 180、数字 #ff6421/37 + 小号「%」、说明 #808690/12）。
  **2026-07 已接真实功能**：进入即调 `state.checkAppVersion`（当前版本 `package_info`，
  最新版本/下载地址来自 `getLastVersion`），四态 `checking / upToDate / updateAvailable / downloading`；
  「立即更新」用 `url_launcher` 打开真实下载地址（对齐 pubspec 里 url_launcher 的用途）。
  入参 `previewStage` 仅供两个演示路由(`figmaUpdateBoltStar{Available,Progress}`)占位展示。
  ⚠️ 原"硬编码 1.0.0/1.2.0 + 本地假动画(伪逻辑)"版本已废弃,别照旧描述复原。
- **校验**：本机未安装 Flutter/Dart SDK，无法运行 `flutter analyze`；改动经人工逐文件复核。
  建议在有 SDK 的环境补跑一次 `flutter analyze lib`。
- **说明**：`UpdateBoltStarPage` **已由设置页「检测更新」入口接入导航**（不再是孤儿页）。

> ✅ **设置模块（index / language / guide / update / privacy / agreement）整体完成。**

### 账户 / 邮箱 `account`（对照 `photo-album/subpackages/settings`：profile/forgot-password/change-email/bind-email）— ✅ 已完成（2026-06-02）
- **共享表单控件对齐**（`figma_common.dart`，惠及所有账户/资料页：profile/register/forgot/modify-password/
  modify-email/bind-email）：
  - 表单标签 `formLabel` 由 14/w400 改 **14/w700/#2a2d32**（小程序 `.form-label`/`.email-label`/
    `.profile-label` 均为粗体）；为避免设备详情信息行被一起加粗，`FigmaInfoRow` 标题就地钉死 w600；
  - 占位符 `formHint` 改 **#8b9098**（`.form-placeholder`/`.email-placeholder`）；
  - 只读字段（如「当前邮箱」）取值改灰 **#777e88**（`.current-email`/`.profile-text`），可编辑值保持深色；
  - 表单分隔线 `FigmaFormDivider` 改 **rgba(207,214,224,0.72) / 左右内缩 18**（`.form-row::before`/
    `.thin-divider`），与设置模块一致；
  - 验证码按钮 `FigmaVerificationField` 改小程序 `.code-btn`：橙描边 #ff5f1f / 圆角 8 / 白 0.5 底；
    倒计时态灰底 #f2f2f2 无描边 + #ff7654 文字；
  - `FigmaScreenBackground` 增 `asset` 入参，支持个别页换背景图。
- **绑定邮箱 `bind-email`**（`bind_email_incomplete_page.dart` / `bind_email_complete_page.dart`）：
  「未完成」态补齐为小程序的完整四行（邮箱/验证码/密码/确认密码）+ 提示，仅主按钮置灰（对应 `!canSubmit`）；
  提示行统一改 `FigmaInfoTip`（圆圈「i」+「绑定邮箱可以用于app登录」居中）。
- **修改邮箱 `change-email`**（`modify_email_page.dart`）：背景改 `bg02.png`（小程序 change-email 用 bg02）；
  结构（当前邮箱只读 + 新邮箱/验证码/密码/确认密码 + 确认修改）本就对齐，随共享控件一并贴近。
- **忘记密码 `forgot-password`**（`forgot_password.dart`）：结构/文案本就对齐，随共享控件贴近，无需改动。
- **附带收益**：注册 `register_page.dart`、修改密码 `modify_password.dart`（小程序无对应页，App 特有）
  因复用共享控件已同步获得粗标签/灰占位/新分隔线/新验证码按钮样式。
- **校验**：本机无 Flutter/Dart SDK，未跑 `flutter analyze`；改动逐文件人工复核（导入、未用符号、资源
  声明均确认）。建议在有 SDK 的环境补跑 `flutter analyze lib`。

> ✅ **账户模块（资料 / 忘记密码 / 修改密码 / 修改邮箱 / 绑定邮箱 / 注册）整体完成。**
> 至此「设置 + 账户」两大待还原模块均已完成；微信小程序 `photo-album` 各业务子包（home/mine/device/
> projection/album/settings/account）已逐页对照还原。

### 后续低优先级清理
- `photo_preview_adjust_image_page.dart` 等 Figma 演示页与真实投屏页并存，可后续做死代码/演示路由收敛。
- 「真实数据版 vs Figma 版」并存但只有单一路径在使用的页面可评估合并。
> 注：登录页两端差异较大（App 邮箱密码/移动应用微信授权 vs 小程序微信快捷登录），不做样式对照还原。
> 注：`figma_common.dart` 的共享脚手架（背景/主次按钮/玻璃卡/导航标题/表单行/分隔线/验证码按钮/返回键）
> 已全面对齐小程序，后续无需重复改这些公共件。

---

## 待优化记录

### 布局方案不统一：弹性自适应仅覆盖少数页面 — ✅ 已复核结案（结论：维持现状，复核于 2026-06-05）

- **问题**：`关键约定 → 布局方式` 中声明全项目采用「弹性 / 响应式布局（`SafeArea` + `Flex` + `Spacer`）」，
  但实际只有少数页面真正落地，大多数页面仍是 Figma 直出的**固定像素**布局，两套方案并存。
- **现状摸排**（`flutter/lib` 全量检索）：
  - **真·弹性自适应（`LayoutBuilder` + `Flex`/`Spacer`）只有 3 个页面**：`home_main_view.dart`、
    `home_bind_device_view.dart`、`mine_page.dart`。统一模式为
    `Expanded → LayoutBuilder → SingleChildScrollView → ConstrainedBox(minHeight: maxHeight)
    → IntrinsicHeight → Column(Spacer/Expanded 撑开)`——屏高够则撑开、过矮则滚动，避免溢出。
  - **固定像素（`FigmaScreen` 脚手架 + 硬编码尺寸）约 45 个页面**：全项目硬编码 `width:`/`height:`
    共 **728 处、分布 49 个文件**（如 `device_details_page.dart` 的 `width: 46, height: 46` 等）。
  - 未使用 `flutter_screenutil` / rpx 等按屏宽缩放方案（`MediaQuery` 也几乎无按比例换算的用法），
    固定像素页面**不随屏宽缩放控件尺寸**。
  - 注：`demo_page.dart` 里的 `LayoutBuilder` 用于图片裁剪坐标换算，非页面布局自适应，不计入。
- **影响**：`FigmaScreen` 仍提供 `SafeArea` + 可滚动内容的基本适配（不会溢出/被刘海遮挡），
  但内部尺寸固定，在差异较大的屏宽/系统字号下还原比例会偏差。
- **优化方向（原计划）**：逐页将固定像素内容改造为弹性布局（沿用上述 home/mine 的标准模式），或引入
  统一的尺寸缩放方案；优先级可参考各 feature 的使用频次。
- **复核结论（2026-06-05，决定维持现状、不推广 Flex）**：动手前对全部页面做了核查，结论是
  **当前方案已基本满足自适应，无需推广 Flex 改造**：
  - 34 个页面中 33 个使用 `FigmaScreen`（仅 `shell` 用 `Scaffold` 做导航壳）。`FigmaScreen` 自身已提供
    `SafeArea` + 顶部导航 + **可滚动 body** + 可选固定底部区，已适配屏高/刘海，超长内容滚动不溢出。
  - 设计本就是「顶部对齐 + 底部按钮固定」，非垂直居中分布。对照小程序 `result.wxss`
    （`.result-body { flex:1 }` 内容顶对齐）与 `FigmaScreen`（滚动 body + 固定 `bottom`）产出结构一致；
    强行加 `Spacer` 居中反而会改歪顶对齐的设计。
  - 12 个 `scrollable: false` 页面也不缺自适应：gallery / my_devices / guide / 投屏记录 / 隐私协议 /
    图片预览 均**内部自带 `Expanded + ListView/GridView` 滚动**；`bind_device_*` 为孤儿页（真正在用的
    绑定流程 `home_bind_device_view` 已是弹性、已完成）。
  - `home/mine` 的 `LayoutBuilder + Flex/Spacer` 解决的是**高度分布**，并**不解决宽度缩放**——
    728 处硬编码 `width/height`「不随屏宽缩放」才是真正缺口，需 `flutter_screenutil` 等**宽度缩放方案**
    才能根治，属另一方向，本次不做。
  - **据此结案**：保持现状、不推广 Flex，本条作为「已评估」留档。若将来要彻底解决宽度等比缩放，
    再单列任务评估引入 `flutter_screenutil`。

---

## 操作日志

- 2026-07（本轮）：① 设置页「检测更新」入口已接回并跳转 UpdateBoltStarPage（真实检查），文档原"入口删除/孤儿页"说法已更正；② 孤儿页清单剔除 `/devices`(死路由已删)、`ModifyPassword`、`UpdateBoltStarPage`(均已接入)；③ FigmaInfoRow/_DetailRow 的 value 已去掉 193px 硬限（label 纯 Text + value Expanded）。
