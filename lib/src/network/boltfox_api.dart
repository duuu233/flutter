import 'api_client.dart';
import 'api_rows.dart';
import 'crypto_util.dart';

/// BoltFox 业务接口（App 版），对齐小程序端 `utils/api.js`。
///
/// 每个方法对应一个后端接口，统一通过 [ApiClient] 发起；公共参数
/// `device` / `terminal` / `language` / `userToken` 由 [ApiClient] 经 header 注入，
/// 业务方法只传业务字段。返回值为后端 `retData`（动态类型，由调用方按接口解析）。
///
/// App 与小程序差异：
/// - App 同时支持邮箱密码登录和微信开放平台「移动应用微信登录」；后者只提交移动应用 SDK
///   返回的一次性 code，不提交小程序手机号授权的 encryptedData / iv。
/// - App 需要版本更新与安卓下载接口（小程序跳过）。
class BoltFoxApi {
  BoltFoxApi._();

  static final ApiClient _http = ApiClient.instance;

  // ==================== 基础功能接口 ====================

  /// 发送邮箱验证码（未登录）。[sendType]：1=注册、2=找回密码/改密、3=改邮箱。
  ///
  /// 关闭超时重试：超时时服务端可能已发信，静默重试会连发多封；若后端「新码作废旧码」，
  /// 用户输入先到的那封就恒报验证码错误。连接失败（未送达）仍会自动重试。
  static Future<dynamic> sendEmail({
    required String userEmail,
    required int sendType,
  }) {
    return _http.postJson(
      '/Client/Basic/sendEmail',
      body: {'userEmail': userEmail, 'sendType': sendType},
      auth: false,
      retryOnTimeout: false,
    );
  }

  /// 获取基础数据（配置/字典等），具体字段以后端返回为准。
  static Future<dynamic> getBasicData([Map<String, dynamic>? params]) {
    return _http.getJson('/Client/Basic/getBasicData', query: params);
  }

  /// 获取 App 版本更新状态。App 端「检查更新」使用。
  static Future<dynamic> getLastVersion({String? appVersionNo}) {
    return _http.getJson(
      '/Client/Basic/getLastVersion',
      query: {'appVersionNo': ?appVersionNo},
    );
  }

  /// 获取安卓新版下载地址。安卓 App 内更新引导使用。
  static Future<dynamic> getAndroidDownload() {
    return _http.getJson('/Client/Basic/getAndroidDownload');
  }

  /// 基础文件上传（与设备业务无关，如头像等通用文件），form-data 字段名 fileParam。
  static Future<dynamic> setFileUpload(List<String> filePaths) {
    return _http.upload('/Client/Basic/setFileUpload', filePaths: filePaths);
  }

  /// BLE 图片转换上传：form-data 上传原图，后端按设备宽高([targetWidth]×[targetHeight])
  /// 转换成设备六色 4bpp 帧(.bin)并存 OSS，返回 `{ url, taskId, upirId }`。
  ///
  /// 对齐小程序 `setUserProductUpload`：投屏时先调本接口把原图转成设备帧，再下载 `.bin` 走 BLE 图传；
  /// 设备图传成功后再用 [editUserProductImgRecord] 把投屏记录置为成功。
  static Future<dynamic> setUserProductUpload({
    required List<String> filePaths,
    Object? userProductId,
    Object? deviceUploadState,
    int? targetWidth,
    int? targetHeight,
  }) {
    return _http.upload(
      '/Client/Basic/setUserProductUpload',
      filePaths: filePaths,
      query: {
        'userProductId': ?userProductId,
        'deviceUploadState': ?deviceUploadState,
        'targetWidth': ?targetWidth,
        'targetHeight': ?targetHeight,
        // 对齐小程序 2026-07-13：产品已取消压缩开关，后端压缩恒开。
        'isCompress': 1,
      },
    );
  }

  // ==================== 产品接口 ====================

  /// 产品列表。[params]：pageIndex、pageSize、keyword、startDate、endDate。
  static Future<dynamic> getProductList([Map<String, dynamic>? params]) {
    return _http.getJson('/Client/Product/getProductList', query: params);
  }

  /// 拉取产品列表里每个产品的 broadcastId（广播名），供蓝牙搜索按它过滤目标相框。
  ///
  /// 对齐小程序 `utils/api.js getProductBroadcastIds`：后端新增/调整支持的机型时前端无需改动，
  /// 白名单跟着产品列表走。返回去重后的非空字符串数组；拉取失败由调用方兜底（不在此处吞错）。
  static Future<List<String>> getProductBroadcastIds() async {
    final data = await getProductList({'pageIndex': 1, 'pageSize': 100});
    // 必须走 extractApiRows：后端分页字段是 `retData.pageData`（swagger `BasePageOutput`），
    // 这里原先手写的取行链只找 list/rows/records/data/items，唯独漏了 pageData，
    // 于是白名单永远解析成空、蓝牙搜索一路回落到硬编码机型。
    final ids = <String>[];
    for (final row in extractApiRows(data)) {
      final id = (row['broadcastId'] ?? '').toString().trim();
      if (id.isNotEmpty && !ids.contains(id)) {
        ids.add(id);
      }
    }
    return ids;
  }

  /// 常见问题列表。[params]：pageIndex、pageSize、keyword、startDate、endDate。
  static Future<dynamic> getProductFaqList([Map<String, dynamic>? params]) {
    return _http.getJson('/Client/Product/getProductFaqList', query: params);
  }

  /// 常见问题详情。
  static Future<dynamic> getProductFaqDetail(Object faqId) {
    return _http.getJson(
      '/Client/Product/getProductFaqDetail',
      query: {'faqId': faqId},
    );
  }

  // ==================== 用户接口（邮箱登录体系）====================

  /// 邮箱登录。成功后返回 retData（含登录 token，字段以后端为准）。
  ///
  /// 拿到 token 后请调用 `ApiSession.instance.setToken(token)` 写入登录态，
  /// 后续接口才会带上 `userToken` / `Authorization` header。
  static Future<dynamic> userLogin({
    required String email,
    required String password,
  }) {
    return _http.postJson(
      '/Client/User/userLogin',
      // 后端登录接口的邮箱字段名为 userEmail（与 sendEmail / changeUserEmail 一致）；
      // 若误传 email，服务端会认为邮箱为空并返回 “Please enter the correct email address”。
      body: {'userEmail': email, 'password': md5Hex(password)},
      auth: false,
    );
  }

  /// 微信开放平台「移动应用微信登录」。
  ///
  /// [code] 来自移动端微信 SDK 的 `snsapi_userinfo` 授权回调。AppSecret、code 换
  /// access_token 以及用户身份合并都必须在服务端完成；客户端只接收业务 userToken。
  /// 后端可根据公共 header 中的 terminal（Android=1 / iOS=2）与小程序（3）区分流程。
  static Future<dynamic> weChatMobileLogin({required String code}) {
    return _http.postJson(
      '/Client/User/setWechatAppLogin',
      body: {'code': code},
      auth: false,
    );
  }

  /// 邮箱注册。[emailCode] 为 `sendEmail(sendType:1)` 收到的验证码。
  ///
  /// 字段名以 swagger `UserRegisterApiIn` 为准：`userEmail / verifyCode / password /
  /// confirmPassword`（原来发 email/emailCode 且缺 confirmPassword，后端收不到邮箱，
  /// 恒报 “Please enter the correct email address”，注册从未成功过）。
  /// UI 已校验两次密码一致，confirmPassword 与 password 同值；DTO 无 nickName 字段。
  static Future<dynamic> userRegister({
    required String email,
    required String password,
    required String emailCode,
  }) {
    final md5Password = md5Hex(password);
    return _http.postJson(
      '/Client/User/userRegister',
      body: {
        'userEmail': email,
        'password': md5Password,
        'confirmPassword': md5Password,
        'verifyCode': emailCode,
      },
      auth: false,
    );
  }

  /// 忘记密码-重置密码（未登录）。[emailCode] 为 `sendEmail(sendType:2)` 验证码。
  /// 字段名以 swagger `ResetPasswordApiIn` 为准（同注册：userEmail/verifyCode/confirmPassword）。
  static Future<dynamic> resetPassword({
    required String email,
    required String password,
    required String emailCode,
  }) {
    final md5Password = md5Hex(password);
    return _http.postJson(
      '/Client/User/resetPassword',
      body: {
        'userEmail': email,
        'password': md5Password,
        'confirmPassword': md5Password,
        'verifyCode': emailCode,
      },
      auth: false,
    );
  }

  /// 修改密码（**已登录**）。[emailCode] 为 `sendEmail(sendType:2)` 验证码
  /// （swagger sendType 描述：2=找回密码邮件/修改密码，两者共用同一验证码类型）。
  ///
  /// 字段名以 swagger `SetPasswordApiIn` 为准：`verifyCode / password / confirmPassword`
  /// （均 md5 32 位小写）。**没有 userEmail 字段**——后端按公共参数里的 userToken 定位
  /// 账号，验证码须发到该账号绑定的邮箱。未登录的忘记密码走 [resetPassword]，勿混用。
  static Future<dynamic> changePassword({
    required String password,
    required String emailCode,
  }) {
    final md5Password = md5Hex(password);
    return _http.postJson(
      '/Client/User/changePassword',
      body: {
        'password': md5Password,
        'confirmPassword': md5Password,
        'verifyCode': emailCode,
      },
    );
  }

  /// 校验邮箱是否不存在（注册前置校验，邮箱已存在则后端返回异常码）。
  /// 字段名以 swagger `SetUserEmailApiIn` 为准（userEmail/verifyCode）。
  static Future<dynamic> chkUserEmailNotExist({
    required String email,
    String? emailCode,
  }) {
    return _http.postJson(
      '/Client/User/chkUserEmailNotExist',
      body: {'userEmail': email, 'verifyCode': ?emailCode},
      auth: false,
    );
  }

  /// 绑定 / 修改邮箱（已登录）。[emailCode] 为 `sendEmail(sendType:3)` 验证码。
  ///
  /// 契约与小程序 `api.js changeUserEmail` 完全一致：body = `userEmail / verifyCode /
  /// password(md5) / confirmPassword(md5)`。同时设置 App 登录密码：[password] 非空时
  /// 以 md5(32位小写) 传输（后端账号体系存 md5）；为空则传空串（仅换邮箱、不改密码）。
  static Future<dynamic> changeUserEmail({
    required String email,
    required String emailCode,
    String? password,
  }) {
    final md5Password = (password == null || password.isEmpty)
        ? ''
        : md5Hex(password);
    return _http.postJson(
      '/Client/User/changeUserEmail',
      body: {
        'userEmail': email,
        'verifyCode': emailCode,
        'password': md5Password,
        'confirmPassword': md5Password,
      },
    );
  }

  /// 获取用户信息（昵称、头像、ID 等），userToken 走 header。
  static Future<dynamic> getUserInfo() {
    return _http.getJson('/Client/User/getUserInfo');
  }

  /// 修改昵称（1-10 字）。
  static Future<dynamic> changeNickName(String nickName) {
    return _http.postJson(
      '/Client/User/changeNickName',
      body: {'nickName': nickName},
    );
  }

  /// 修改头像。[avatar] 为头像地址（可先经 [setFileUpload] 上传取地址）。
  static Future<dynamic> changeAvatar(String avatar) {
    return _http.postJson(
      '/Client/User/changeAvatar',
      body: {'avatar': avatar},
    );
  }

  /// 退出登录。建议成功后调用 `ApiSession.instance.clear()` 清除本地登录态。
  static Future<dynamic> loginOut() {
    return _http.postJson('/Client/User/loginOut');
  }

  /// 用户注销（销户）。建议成功后调用 `ApiSession.instance.clear()`。
  static Future<dynamic> userOff() {
    return _http.postJson('/Client/User/userOff');
  }

  // ==================== 设备接口（UserProduct）====================

  /// 添加 / 绑定用户设备。
  ///
  /// 关闭超时重试：超时时后端可能已建绑定记录，重试是否重复绑定取决于后端去重，不赌。
  static Future<dynamic> addUserProduct({
    required int productId,
    required String productName,
    required String productSerialNo,
  }) {
    return _http.postJson(
      '/Client/UserProduct/addUserProduct',
      body: {
        'productId': productId,
        'productName': productName,
        // 硬件序列号：完全对齐已通过测试的小程序 `api.bindDevice` —— 用字段名 `deviceId` 提交（同一后端）。
        'deviceId': productSerialNo,
      },
      retryOnTimeout: false,
    );
  }

  /// 获取用户设备列表。[params]：pageIndex、pageSize、keyword、startDate、endDate。
  static Future<dynamic> getUserProductList([Map<String, dynamic>? params]) {
    return _http.getJson(
      '/Client/UserProduct/getUserProductList',
      query: params,
    );
  }

  /// 获取用户设备详情。
  static Future<dynamic> getUserProductDetail({
    required Object userProductId,
    Object? productVersionNo,
  }) {
    return _http.getJson(
      '/Client/UserProduct/getUserProductDetail',
      query: {
        'userProductId': userProductId,
        'productVersionNo': ?productVersionNo,
      },
    );
  }

  /// 编辑设备信息。[productName] 传入即重命名；[isClearImg] 传入即复位一键清除标记
  /// （对齐小程序 `editUserProduct({userProductId, isClearImg:0})`：确认「重新上传」提醒后置 0，
  /// 后端不再返回「已清除」，避免每次进入图库都弹）。两者可单独或同时传。
  static Future<dynamic> editUserProduct({
    required Object userProductId,
    String? productName,
    int? isClearImg,
  }) {
    return _http.postJson(
      '/Client/UserProduct/editUserProduct',
      body: {
        'userProductId': userProductId,
        'productName': ?productName,
        'isClearImg': ?isClearImg,
      },
    );
  }

  /// 获取设备一键清除状态，id=userProductId。retData：0=未清除、1=已清除。
  ///
  /// 对齐小程序 `getUserProductClearImg`：图库页进入 / 切换设备筛选时后台查询——
  /// 设备在别处被执行过清空时（图库照片已不在设备上）弹「请重新上传图片」提醒。
  /// 小程序侧 `showError:false` 静默失败；App 端由调用方 catch 忽略异常（下次进入/切换再查）。
  static Future<dynamic> getUserProductClearImg(Object userProductId) {
    return _http.getJson(
      '/Client/UserProduct/getUserProductClearImg',
      query: {'id': userProductId},
    );
  }

  /// 删除设备，id=userProductId。
  static Future<dynamic> delUserProduct(Object userProductId) {
    return _http.postJson(
      '/Client/UserProduct/delUserProduct',
      body: {'id': userProductId},
    );
  }

  /// 一键清除设备图片（格式化），id=userProductId。
  static Future<dynamic> clearUserProductImg(Object userProductId) {
    return _http.postJson(
      '/Client/UserProduct/clearUserProductImg',
      body: {'id': userProductId},
    );
  }

  /// 用户产品图片列表（我的图库）。[params] 支持分页与 userProductId 过滤。
  static Future<dynamic> getUserProductImgList([Map<String, dynamic>? params]) {
    return _http.getJson(
      '/Client/UserProduct/getUserProductImgList',
      query: params,
    );
  }

  /// 删除产品图片，支持多选，id=uProductImgId。
  /// 后端约定的字段名是 `idList`（不是 `ids`），与小程序 `api.js` 对齐。
  static Future<dynamic> delUserProductImg(List<Object> ids) {
    return _http.postJson(
      '/Client/UserProduct/delUserProductImg',
      body: {'idList': ids},
    );
  }

  /// 产品投屏记录列表（成功/失败投屏）。[params] 支持分页、keyword、userProductId。
  static Future<dynamic> getUserProductImgRecordList([
    Map<String, dynamic>? params,
  ]) {
    return _http.getJson(
      '/Client/UserProduct/getUserProductImgRecordList',
      query: params,
    );
  }

  /// 删除产品投屏记录，id=upirId。
  static Future<dynamic> delUserProductImgRecord(Object upirId) {
    return _http.postJson(
      '/Client/UserProduct/delUserProductImgRecord',
      body: {'id': upirId},
    );
  }

  /// 设备图片槽位索引 → 接口入参（swagger 约定 String）。
  ///
  /// 传 null 或负数表示「本次没有索引可上报」，返回 null 后由 `?` 展开丢弃该键，后端按不传处理。
  /// ⚠️ 0 是合法槽位（相框第一个位置），必须原样上报——不能当空值丢掉，
  /// 否则第一个位置上的照片在图库里永远删不掉、刷不到。见 docs/图片索引-imgIndex方案.md 问题 E。
  /// （小程序 api.js 的 `imgIndexParam` 还要挡 undefined/''，Dart 有 `int?` 不需要那层。）
  static String? _imgIndexParam(int? index) {
    return (index == null || index < 0) ? null : index.toString();
  }

  /// 编辑投屏记录（设备图传成功后置设备上传状态）。
  ///
  /// 对齐小程序 `editUserProductImgRecord`：设备 BLE 图传成功后调用，把该条记录的
  /// [deviceUploadState] 置为 1（0=失败,1=成功）；[taskId] 为 [setUserProductUpload] 返回的任务 id。
  ///
  /// ⚠️ **后端按 [taskId] 定位记录，不是 [upirId]**（小程序 result.js:561 同）。
  /// [setUserProductUpload] 的响应 DTO `BaseUploadApiOut` 压根没有 upirId 字段
  /// （只有 base64Img/formatColors/name/taskId/url），所以正常投屏链路这里恒为 null。
  /// **null 必须用 `?` 丢掉整个键**，绝不能 `?? ''` 兜底成空串——swagger
  /// `ClientUserProductImgRecordEditApiIn.upirId` 是 **integer**，空串会让后端反序列化 400，
  /// 整个请求作废 → 记录永远停在 deviceUploadState=0 → 图库（仅显示成功上传的照片）就没有这张。
  /// 小程序侧靠 JS 的 `undefined` 被 JSON.stringify 自动丢弃躲过了这个坑（2026-07-19 修）。
  ///
  /// [imgIndex]=这张图实际写入设备的物理槽位索引，供图库删除/刷新屏幕定位
  /// （见 docs/图片索引-imgIndex方案.md）。设备上没有这张图时不传。
  static Future<dynamic> editUserProductImgRecord({
    Object? upirId,
    Object? taskId,
    int deviceUploadState = 1,
    int? imgIndex,
  }) {
    return _http.postJson(
      '/Client/UserProduct/editUserProductImgRecord',
      body: {
        'upirId': ?upirId,
        'taskId': ?taskId,
        'deviceUploadState': deviceUploadState,
        'imgIndex': ?_imgIndexParam(imgIndex),
      },
    );
  }

  /// 新增投屏记录（再次/重新投屏用 imgBle 直传设备后调用）。
  ///
  /// 对齐小程序 `addUserProductImgRecord`：投屏记录页「再次投屏」直接用记录里的设备帧
  /// [imgBle] 图传，不再走后端上传/转码；设备图传成功([deviceUploadState]=1)/失败(0)后
  /// 都新增一条投屏记录。[taskId] 再次投屏链路没有，为空时不传（后端沿用旧记录不需要）。
  ///
  /// [imgIndex] 同 [editUserProductImgRecord]：再次/重新投屏也会占用一个新槽位，必须一并上报，
  /// 否则这条新记录在图库里没有索引、删不掉。图传失败(0)的补记不传——设备上没有这张图。
  static Future<dynamic> addUserProductImgRecord({
    Object? upirId,
    Object? userProductId,
    String? img,
    String? imgBle,
    Object? taskId,
    int deviceUploadState = 1,
    int? imgIndex,
  }) {
    return _http.postJson(
      '/Client/UserProduct/addUserProductImgRecord',
      body: {
        'upirId': ?upirId,
        'userProductId': ?userProductId,
        'img': ?img,
        'imgBle': ?imgBle,
        'taskId': ?taskId,
        'deviceUploadState': deviceUploadState,
        'imgIndex': ?_imgIndexParam(imgIndex),
      },
      // 关闭超时重试：超时时记录可能已写入，重试会产生重复投屏记录。
      retryOnTimeout: false,
    );
  }
}
