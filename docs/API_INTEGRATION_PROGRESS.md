# API Integration Progress (App / BoltStar)

接口文档：https://api.boltfox.cn/swagger-ui.html#/

后端地址：https://api.boltfox.cn

当前项目：BoltStar Flutter App（iOS / Android）

## 对接规则

- 只对接用户前端模块：基础功能接口、产品接口、用户接口、设备接口。
- 当前为 App，**走邮箱登录/注册体系**，`/Client/User/setWechatAppLogin`（微信小程序一键登录）不接入。
- App 需要版本更新与安卓下载：`/Client/Basic/getLastVersion`、`/Client/Basic/getAndroidDownload` 接入（与小程序相反）。
- `/Client/User/userOffPC`（PC 注销）跳过。
- 公共参数 `device` / `terminal` / `language` / `userToken` 通过 headers 传递；App `terminal`：iOS=1、Android=2（取值以后端约定为准，见 `lib/src/network/api_config.dart`）。
- BoltFox 响应格式为 `retCode/retMsg/retData`，`retCode=200` 表示成功，由 `ApiClient` 统一解析。
- 网络层位置：`lib/src/network/`（`api_config` / `api_session` / `api_exception` / `api_client` / `boltfox_api`）。
- 新增依赖：`http`（见 `pubspec.yaml`）。**首次拉取后需执行 `flutter pub get`。**

## 模块进度

| 模块 | 状态 | 代码位置 | 说明 |
| --- | --- | --- | --- |
| 网络层基础 | 已完成 | `lib/src/network/api_*.dart` | header 注入 + retCode 解析 + 异常/会话 |
| 用户前端-基础功能接口 | 接口层已接入 | `lib/src/network/boltfox_api.dart` | 邮箱验证码、基础数据、版本更新、安卓下载、文件/设备上传 |
| 用户前端-产品接口 | 接口层已接入 | `lib/src/network/boltfox_api.dart` | 产品列表、FAQ 列表/详情 |
| 用户前端-用户接口 | 接口层已接入 | `lib/src/network/boltfox_api.dart` | 邮箱登录/注册/找回/改密/改邮箱/校验邮箱/用户信息/昵称头像/退出/注销；微信一键登录、PC 注销跳过 |
| 用户前端-设备接口 | 接口层已接入 | `lib/src/network/boltfox_api.dart` | 设备增删改查、图库、一键清空、投屏记录列表/删除 |

> 接入方式：先建立 `lib/src/network` 接口层（本阶段），页面/`PhotoFrameState` 联调时在各 action 方法内部替换为真实接口调用，避免页面直接拼接请求。

## 已接入接口（模块1）

### 基础功能接口

| 方法 | 路径 | `BoltFoxApi` 方法 | Swagger 摘要 |
| --- | --- | --- | --- |
| POST | `/Client/Basic/sendEmail` | `sendEmail()` | 发送邮箱验证码（未登录） |
| POST | `/Client/Basic/sendEmailToken` | `sendEmailToken()` | 发送邮箱验证码（已登录） |
| GET | `/Client/Basic/getBasicData` | `getBasicData()` | 获取基础数据 |
| GET | `/Client/Basic/getLastVersion` | `getLastVersion()` | 获取 App 版本更新状态 |
| GET | `/Client/Basic/getAndroidDownload` | `getAndroidDownload()` | 安卓下载 |
| POST | `/Client/Basic/setFileUpload` | `setFileUpload()` | 基础文件上传（form-data） |
| POST | `/Client/Basic/setUserProductUpload` | `setUserProductUpload()` | 设备上传图片（form-data） |

### 产品接口

| 方法 | 路径 | `BoltFoxApi` 方法 | Swagger 摘要 |
| --- | --- | --- | --- |
| GET | `/Client/Product/getProductList` | `getProductList()` | 产品列表 |
| GET | `/Client/Product/getProductFaqList` | `getProductFaqList()` | 常见问题列表 |
| GET | `/Client/Product/getProductFaqDetail` | `getProductFaqDetail()` | 常见问题详情 |

## 已接入接口（模块2 用户接口）

| 方法 | 路径 | `BoltFoxApi` 方法 | 关键字段 / 说明 |
| --- | --- | --- | --- |
| POST | `/Client/User/userLogin` | `userLogin()` | `email`、`password`；返回登录 token，需 `ApiSession.setToken` |
| POST | `/Client/User/userRegister` | `userRegister()` | `email`、`password`、`emailCode`、`nickName?` |
| POST | `/Client/User/resetPassword` | `resetPassword()` | `email`、`password`、`emailCode`（sendType:2） |
| POST | `/Client/User/chkUserEmailNotExist` | `chkUserEmailNotExist()` | 注册前置校验，邮箱已存在返回异常码 |
| POST | `/Client/User/changePassword` | `changePassword()` | `oldPassword`、`newPassword` |
| POST | `/Client/User/changeUserEmail` | `changeUserEmail()` | `email`、`emailCode`（sendType:3） |
| GET | `/Client/User/getUserInfo` | `getUserInfo()` | userToken 走 header |
| POST | `/Client/User/changeNickName` | `changeNickName()` | 1-10 字 |
| POST | `/Client/User/changeAvatar` | `changeAvatar()` | 头像地址（可先 `setFileUpload`） |
| POST | `/Client/User/loginOut` | `loginOut()` | 成功后 `ApiSession.clear()` |
| POST | `/Client/User/userOff` | `userOff()` | 成功后 `ApiSession.clear()` |

### 用户接口-小程序跳过项（App 不接入）

| 方法 | 路径 | 跳过原因 |
| --- | --- | --- |
| POST | `/Client/User/setWechatAppLogin` | 微信小程序一键登录，App 走邮箱登录 |
| POST | `/Client/User/userOffPC` | PC 版注销 |

## 已接入接口（模块3 设备接口 / UserProduct）

| 方法 | 路径 | `BoltFoxApi` 方法 | 关键字段 / 说明 |
| --- | --- | --- | --- |
| POST | `/Client/UserProduct/addUserProduct` | `addUserProduct()` | `productId`、`productName`、`productSerialNo` |
| GET | `/Client/UserProduct/getUserProductList` | `getUserProductList()` | 分页：pageIndex/pageSize/keyword/startDate/endDate |
| GET | `/Client/UserProduct/getUserProductDetail` | `getUserProductDetail()` | `userProductId`、`productVersionNo?` |
| POST | `/Client/UserProduct/editUserProduct` | `editUserProduct()` | `userProductId`、`productName` |
| POST | `/Client/UserProduct/delUserProduct` | `delUserProduct()` | `id`=userProductId |
| POST | `/Client/UserProduct/clearUserProductImg` | `clearUserProductImg()` | `id`=userProductId（格式化） |
| GET | `/Client/UserProduct/getUserProductImgList` | `getUserProductImgList()` | 分页 + userProductId（我的图库） |
| POST | `/Client/UserProduct/delUserProductImg` | `delUserProductImg()` | `ids`=[uProductImgId]，支持多选 |
| GET | `/Client/UserProduct/getUserProductImgRecordList` | `getUserProductImgRecordList()` | 投屏记录列表 |
| POST | `/Client/UserProduct/delUserProductImgRecord` | `delUserProductImgRecord()` | `id`=upirId |

## 全部接口层已对接 ✅

用户前端 4 个模块（基础公共 / 产品 / 用户 / 设备）接口层已全部接入 `lib/src/network/boltfox_api.dart`。

### 后续待办（页面联调）

- 在 `PhotoFrameState` 的各 action 方法内部，用 `BoltFoxApi` 替换当前的本地 mock 实现（参考 `state.dart` 顶部注释）。
- 登录成功后写入 `ApiSession.instance.setToken(token)`；切换语言时调用 `ApiSession.instance.setLanguage(...)`。
- 跟后端确认 `terminal` 取值（iOS/Android）与是否需要持久化 token。
- 执行 `flutter pub get`（已新增 `http` 依赖），再 `flutter analyze` 校验。
