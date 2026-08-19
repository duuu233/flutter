# BoltStar 接口与服务集成

> 文档类型：Integration Architecture  
> 状态：Active  
> 最后核验：2026-07-28  
> 维护责任：网络层、账号、设备、投屏与 AI 模块维护者  
> 事实来源：`lib/src/network/`、后端 Swagger、跨端对齐结论

## 1. 服务边界

BoltStar 当前使用三套不同的远端服务：

| 服务 | 客户端入口 | 用途 | 响应/鉴权 |
| --- | --- | --- | --- |
| BoltFox API | `BoltFoxApi` / `ApiClient` | 账号、产品、设备、图库、投屏记录、版本、文件上传 | `retCode/retMsg/retData`；业务 token |
| seekink 抖动服务 | `DitheringApi` | 原图转设备六色 `.bin` 帧 | Bearer token；token 由 BoltFox `getXTYUserToken` 获取 |
| BoltStar AI | `BoltStarAiApi` | 星宝会话、图文对话、图片增强 | 独立 `{success,code,data,params,detail}`；不走 `ApiClient` |

三套服务不得因为“都是 HTTP”而合并响应模型。特别是 AI 的 `detail` 只允许写工程日志，不能直接
展示给用户。

## 2. BoltFox 公共规则

- Base URL：`https://api.boltfox.cn`
- 客户端封装：`lib/src/network/api_client.dart`
- 业务接口：`lib/src/network/boltfox_api.dart`
- `retCode=200` 表示成功；鉴权失效由 `ApiException.isAuthError` 识别 401/406。
- 公共参数 `device`、`terminal`、`language`、`userToken` 由网络层注入。
- `terminal`：Android=1、iOS=2、小程序=3。
- App 保留版本检查和 Android 下载接口；`userOffPC` 仅 PC 使用，App 跳过。
- 密码在客户端使用小写 32 位 MD5；服务端参数名仍以 Swagger DTO 为准。

## 3. BoltFox 当前接口

### 基础能力

| 能力 | 接口 | 客户端方法 | 关键规则 |
| --- | --- | --- | --- |
| 邮箱验证码 | `POST /Client/Basic/sendEmail` | `sendEmail` | sendType：1 注册、2 找回/改密、3 改邮箱 |
| 版本检查 | `GET /Client/Basic/getLastVersion` | `getLastVersion` | Android/iOS 均使用 |
| Android 下载 | `GET /Client/Basic/getAndroidDownload` | `getAndroidDownload` | 仅 Android 安装引导 |
| 基础数据 | `GET /Client/Basic/getBasicData` | `getBasicData` | 配置/字典 |
| 抖动 token | `GET /Client/Basic/getXTYUserToken` | `getXTYUserToken` | `isNewLogin=1` 用于 401 后强制刷新 |
| 通用文件上传 | `POST /Client/Basic/setFileUpload` | `setFileUpload` | form-data 字段 `fileParam` |
| 投屏原图上传 | `POST /Client/Basic/setUserProductUpload` | `setUserProductUpload` | 建记录并上传原图 |

### 账号

| 能力 | 接口 | 客户端方法 | 关键规则 |
| --- | --- | --- | --- |
| 微信移动应用登录 | `POST /Client/User/setWechatAuthorizLogin` | `weChatMobileLogin` | 只提交 SDK 一次性 code；**关闭全部自动重试**（超时与连接中断都不重试），业务层还拒收已提交过的 code。小程序的 `setWechatAppLogin` 是另一条链路（授权手机号），App 不用 |
| 邮箱注册 | `POST /Client/User/userRegister` | `userRegister` | `userEmail/verifyCode/password/confirmPassword` |
| 邮箱登录 | `POST /Client/User/userLogin` | `userLogin` | 成功后写入 `ApiSession` |
| 用户资料 | `GET /Client/User/getUserInfo` | `getUserInfo` | 昵称、头像、邮箱、用户 ID |
| 修改昵称/头像 | `POST changeNickName/changeAvatar` | 同名方法 | 头像先走通用上传 |
| 绑定/修改邮箱 | `POST /Client/User/changeUserEmail` | `changeUserEmail` | sendType=3 |
| 忘记密码 | `POST /Client/User/resetPassword` | `resetPassword` | 未登录流程，sendType=2 |
| 已登录改密 | `POST /Client/User/changePassword` | `changePassword` | userToken 定位账号，无邮箱字段 |
| 邮箱存在校验 | `POST /Client/User/chkUserEmailNotExist` | `chkUserEmailNotExist` | 注册前置 |
| 退出登录 | `POST /Client/User/loginOut` | `loginOut` | 随后清会话与图片缓存 |
| 用户注销 | `POST /Client/User/userOff` | `userOff` | 随后清会话与图片缓存 |

`userOffPC` 不属于 App。

### 产品、设备与图库

| 能力 | 接口 | 客户端方法/落点 |
| --- | --- | --- |
| 产品列表/广播白名单 | `GET /Client/Product/getProductList` | `getProductList` / `getProductBroadcastIds` |
| FAQ | `GET /Client/Product/getProductFaqList` | `getProductFaqList` |
| 绑定设备 | `POST /Client/UserProduct/addUserProduct` | `addUserProduct` |
| 设备列表/详情 | `GET getUserProductList/getUserProductDetail` | 同名方法 |
| 修改/删除设备 | `POST editUserProduct/delUserProduct` | 同名方法 |
| 清空设备记录 | `POST clearUserProductImg` | `clearUserProductImg` |
| ~~图库列表/删除~~ | ~~`GET getUserProductImgList` / `POST delUserProductImg`~~ | **2026-08-17 端上删除**（后端接口仍在）。「我的相册」铺的是投屏成功记录，删除只认记录自己的 `imgIndex`、再次投屏直接用记录自己的 `img`；端上删除 = 设备槽位 `0x12` + `delUserProductImgRecord`，图库照片的清理归后端。勿再接回 |
| 投屏记录列表/删除 | `GET getUserProductImgRecordList` / `POST delUserProductImgRecord` | 同名方法 |
| 投屏记录新增/更新 | UserProduct 图片记录接口 | `ProjectionService` 成功/失败回写 |
| 星币余额 | `GET /Client/Order/getUserAccount` | `getUserAccount` → `AiToken.fetchBalance` / `StarCoinApi.fetchAccount` |
| 星币购买/消费记录 | `GET /Client/Order/getUserAccountTrade` | `getUserAccountTrade` → `StarCoinApi.fetchRecords` |
| 星币消耗规则 | `GET /Client/Order/getAiConfigList` | `getAiConfigList` → `StarCoinApi.fetchRules`（`retData` 是**裸数组**，顺序原样保留） |
| 官方图库分类/列表/详情 | `GET /Client/Product/{getImgCategory,getProductImgList,getProductImgDetail}` | 同名方法 → `OfficialGalleryApi` |
| 图片收藏/取消、收藏列表 | `POST /Client/Product/setImgCollected`、`GET /Client/Product/getProductImgCollectionList` | 同上。⚠️ 收藏切换返回的布尔语义未定，端上按**取反当前态**推新状态 |
| 能否发起 AI 对话 | `GET /Client/Order/chkAiDialogue` | `chkAiDialogue` → `AiToken.canDialogue` |

设备扫描、连接、电量、轮播、刷屏、清空物理存储和 OTA 的核心动作是 BLE 端能力，不应在接口
清单中伪装成后端接口。

## 4. FAQ 读取规则

- Client FAQ 接口不带 `productId`，因此按语言读取全局 FAQ，不做设备过滤。
- 必须依据 `recordCount`/`pageCount` 翻页读完，不能用“返回条数小于 pageSize”提前停止。
- `grade` 只存在于后台 DTO，客户端保持后端顺序，不自行重排。
- 切换语言后重新拉取；空结果同样覆盖旧列表，避免旧语种残留。
- FAQ HTML 子集由 `SimpleHtmlText` 渲染。

用户可见内容见 `../content/操作手册与常见问题-四语种.md`。

## 5. 图片槽位与抖动服务

- 投屏成功时把设备物理槽位 `imgIndex` 回写到后端记录。
- 删除与刷屏优先使用真实 `imgIndex`；无索引的旧记录才允许回退推算。
- `imgIndex=0` 是合法槽位，判空只能使用 `<0`/`>=0`。
- seekink token 会话级缓存；抖动接口 401 时只强制刷新一次并重试，防止循环。
- 投屏记录上传与设备帧获取可以并行，但只有 BLE 成功后才能把记录标记为成功。

槽位长期规则见 `IMAGE_SLOT_INDEX.md`。

## 6. BoltStar AI

实现：`lib/src/network/boltstar_ai_api.dart`

- 非流式 Base URL：`https://boltstaat-agent-fwdomalzks.ap-southeast-1.fcapp.run`
- 普通请求超时 15 秒；对话/图片增强 120 秒。
- `user_id` 由 BoltFox 用户 ID 派生；未登录使用受控 demo ID。
- **2026-08-12 起 `/chat` 还带 `usertoken`**（全小写）：值是登录接口下发的 `userToken`
  （BoltFox 公共参数那一枚，**不是** `Authentication` 头里的 `jwtToken`），AI 网关拿它回
  BoltFox 侧核对用户与扣费。名字或取值错了不会报错，只会静默变成「服务端认不出这个用户」。
- 会话：新建、列表、删除。
- 历史：读取、逐条删除。
- 对话：`POST /chat`，支持最多 **5** 张公网图片 URL（2026-08-12 由 4 张放宽；
  ⚠️ BoltStar 文档 §二写的仍是 4 张，若服务端未同步放宽，第 5 张会被回 20012）。
- 图片增强：`POST /image/enhance`。
- 图片先压缩并通过 BoltFox `setFileUpload` 获得公网 URL，再提交 AI。
- 文本、生成提示词和用户图片提交给阿里云百炼前，客户端必须确认当前 BoltFox 用户已同意
  “BoltStar AI服务协议”；拒绝后允许继续输入/浏览，但所有发送入口持续拦截并再次引导。
- 同意状态由 `AiServiceConsent` 按“协议版本 + 用户 ID”写入 `SharedPreferences`，不允许跨账号复用；
  退出、注销成功或 401/406 登录态失效后清除。
- 完整四语种条款位于设置页 `AiServiceAgreementPage`；协议版本当前为 `2026-07-28-v2`。
- 阿里云网关返回固定大写字段错误 `Code=JWTTokenIsMissing`、
  `Message=the jwt token is missing` 时，AI 网络层生成受信用户文案，toast 展示错误码、
  Message 与动态 `RequestId`。其它 `detail` 仍只允许写日志，不得展示。
- 正式用户入口当前由 `kAiEntryEnabled=false` 屏蔽；调试暗门保留。
- 语音输入仍是占位；下载只写应用缓存目录。

### 星币（Order）

支付体系（套餐、下单、支付、购买/消费记录）目前**只有小程序端有页面**，App 侧 IAP 未接，
所以这里只接了 AI 模块用得到的两个：

- `GET /Client/Order/getUserAccount` —— 取 `availableToken`（**String**，端上转数字）作 AI 侧余额展示。
  取不到显示 `--`，**不用 0 兜底**；端上**不得**自减（没有「消费星币」的 Client 端点，扣费在服务端）。
- `GET /Client/Order/chkAiDialogue` —— 发送前的唯一闸。
  ⚠️ **两种答复不对称**：可以发＝`retCode 200` + `retData true`；
  **不能发＝`retCode 403`** + `retMsg"token余额不足，需要最低余额：30.0 token"` + `retData null`，
  也就是否定答复走的是 `ApiException` 那条**失败**路径 —— 只认 `retData==true` 会把它当成
  「接口挂了」而放行。判定与兜底收在 `AiToken.canDialogue`：除 403 外的失败一律**放行**
  （读不到判据就锁死 AI 是更糟的失败模式，`/chat` 侧服务端会再拒一次）。

## 7. 已知待确认

- `getXTYUserToken` 的所有返回字段仍应以真机联调和最新 Swagger 为准。
- 后端需要保证同一设备同一 `imgIndex` 的记录唯一性，避免旧记录幽灵指向已复用槽位。
- AI 接口版本变化必须同时核对会话创建时机、错误码和图片消息结构。
- `setImgCollected`（图库收藏，小程序已接）与 `chkAiDialogue` 返回布尔的语义都要与后端确认；
  后者端上按「403 = 不允许」判定，改码就会失效。
- 发布前必须验证微信、版本检查、图片上传、抖动 token 刷新和注销清理。

## 8. 维护规则

- 当前契约只维护在本文；阶段性接入过程不再写回 Active 文档操作日志。
- 接口方法、DTO 或公共参数变化时更新对应章节，并用 CodeGraph 检查调用方。
- 历史接口表与接入过程位于 `../history/2026-07/`。
