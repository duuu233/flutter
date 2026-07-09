import 'api_client.dart';

/// BoltFox 业务接口（App 版），对齐小程序端 `utils/api.js`。
///
/// 每个方法对应一个后端接口，统一通过 [ApiClient] 发起；公共参数
/// `device` / `terminal` / `language` / `userToken` 由 [ApiClient] 经 header 注入，
/// 业务方法只传业务字段。返回值为后端 `retData`（动态类型，由调用方按接口解析）。
///
/// App 与小程序差异：
/// - App 走邮箱登录/注册体系，不接入 `setWechatAppLogin`（微信一键登录）。
/// - App 需要版本更新与安卓下载接口（小程序跳过）。
class BoltFoxApi {
  BoltFoxApi._();

  static final ApiClient _http = ApiClient.instance;

  // ==================== 基础功能接口 ====================

  /// 发送邮箱验证码（未登录）。[sendType]：1=注册、2=找回密码/改密、3=改邮箱。
  static Future<dynamic> sendEmail({
    required String userEmail,
    required int sendType,
  }) {
    return _http.postJson(
      '/Client/Basic/sendEmail',
      body: {'userEmail': userEmail, 'sendType': sendType},
      auth: false,
    );
  }

  /// 发送邮箱验证码（已登录，userToken 走 header）。
  static Future<dynamic> sendEmailToken({String? userEmail, int? sendType}) {
    return _http.postJson('/Client/Basic/sendEmailToken', body: {
      if (userEmail != null) 'userEmail': userEmail,
      if (sendType != null) 'sendType': sendType,
    });
  }

  /// 获取基础数据（配置/字典等），具体字段以后端返回为准。
  static Future<dynamic> getBasicData([Map<String, dynamic>? params]) {
    return _http.getJson('/Client/Basic/getBasicData', query: params);
  }

  /// 获取 App 版本更新状态。App 端「检查更新」使用。
  static Future<dynamic> getLastVersion({String? appVersionNo}) {
    return _http.getJson(
      '/Client/Basic/getLastVersion',
      query: {if (appVersionNo != null) 'appVersionNo': appVersionNo},
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
    // 是否压缩图片：1=压缩(后端压到约300-400KB) / 0=不压缩传原图，缺省压缩。
    // ⚠️ 字段名 isCompress 为约定假设，待后端确认（与小程序 api.js 同一处约定，确认后只改这一处）。
    int isCompress = 1,
  }) {
    return _http.upload(
      '/Client/Basic/setUserProductUpload',
      filePaths: filePaths,
      query: {
        if (userProductId != null) 'userProductId': userProductId,
        if (deviceUploadState != null) 'deviceUploadState': deviceUploadState,
        if (targetWidth != null) 'targetWidth': targetWidth,
        if (targetHeight != null) 'targetHeight': targetHeight,
        'isCompress': isCompress == 0 ? 0 : 1,
      },
    );
  }

  // ==================== 产品接口 ====================

  /// 产品列表。[params]：pageIndex、pageSize、keyword、startDate、endDate。
  static Future<dynamic> getProductList([Map<String, dynamic>? params]) {
    return _http.getJson('/Client/Product/getProductList', query: params);
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
      body: {'email': email, 'password': password},
      auth: false,
    );
  }

  /// 邮箱注册。[emailCode] 为 `sendEmail(sendType:1)` 收到的验证码。
  static Future<dynamic> userRegister({
    required String email,
    required String password,
    required String emailCode,
    String? nickName,
  }) {
    return _http.postJson(
      '/Client/User/userRegister',
      body: {
        'email': email,
        'password': password,
        'emailCode': emailCode,
        if (nickName != null) 'nickName': nickName,
      },
      auth: false,
    );
  }

  /// 忘记密码-重置密码（未登录）。[emailCode] 为 `sendEmail(sendType:2)` 验证码。
  static Future<dynamic> resetPassword({
    required String email,
    required String password,
    required String emailCode,
  }) {
    return _http.postJson(
      '/Client/User/resetPassword',
      body: {'email': email, 'password': password, 'emailCode': emailCode},
      auth: false,
    );
  }

  /// 校验邮箱是否不存在（注册前置校验，邮箱已存在则后端返回异常码）。
  static Future<dynamic> chkUserEmailNotExist({
    required String email,
    String? emailCode,
  }) {
    return _http.postJson(
      '/Client/User/chkUserEmailNotExist',
      body: {'email': email, if (emailCode != null) 'emailCode': emailCode},
      auth: false,
    );
  }

  /// 修改密码（已登录）。
  static Future<dynamic> changePassword({
    required String oldPassword,
    required String newPassword,
  }) {
    return _http.postJson(
      '/Client/User/changePassword',
      body: {'oldPassword': oldPassword, 'newPassword': newPassword},
    );
  }

  /// 绑定 / 修改邮箱（已登录）。[emailCode] 为 `sendEmail(sendType:3)` 验证码。
  static Future<dynamic> changeUserEmail({
    required String email,
    required String emailCode,
  }) {
    return _http.postJson(
      '/Client/User/changeUserEmail',
      body: {'email': email, 'emailCode': emailCode},
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
  static Future<dynamic> addUserProduct({
    required int productId,
    required String productName,
    required String productSerialNo,
  }) {
    return _http.postJson('/Client/UserProduct/addUserProduct', body: {
      'productId': productId,
      'productName': productName,
      'productSerialNo': productSerialNo,
    });
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
    return _http.getJson('/Client/UserProduct/getUserProductDetail', query: {
      'userProductId': userProductId,
      if (productVersionNo != null) 'productVersionNo': productVersionNo,
    });
  }

  /// 编辑设备信息。[productName] 传入即重命名；[isClearImg] 传入即复位一键清除标记
  /// （对齐小程序 `editUserProduct({userProductId, isClearImg:0})`：确认「重新上传」提醒后置 0，
  /// 后端不再返回「已清除」，避免每次进入图库都弹）。两者可单独或同时传。
  static Future<dynamic> editUserProduct({
    required Object userProductId,
    String? productName,
    int? isClearImg,
  }) {
    return _http.postJson('/Client/UserProduct/editUserProduct', body: {
      'userProductId': userProductId,
      if (productName != null) 'productName': productName,
      if (isClearImg != null) 'isClearImg': isClearImg,
    });
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

  /// 编辑投屏记录（设备图传成功后置设备上传状态）。
  ///
  /// 对齐小程序 `editUserProductImgRecord`：设备 BLE 图传成功后调用，把 [upirId] 对应记录的
  /// [deviceUploadState] 置为 1（0=失败,1=成功）；[taskId] 为 [setUserProductUpload] 返回的任务 id。
  static Future<dynamic> editUserProductImgRecord({
    required Object upirId,
    Object? taskId,
    int deviceUploadState = 1,
  }) {
    return _http.postJson('/Client/UserProduct/editUserProductImgRecord', body: {
      'upirId': upirId,
      if (taskId != null) 'taskId': taskId,
      'deviceUploadState': deviceUploadState,
    });
  }

  /// 新增投屏记录（再次/重新投屏用 imgBle 直传设备后调用）。
  ///
  /// 对齐小程序 `addUserProductImgRecord`：投屏记录页「再次投屏」直接用记录里的设备帧
  /// [imgBle] 图传，不再走后端上传/转码；设备图传成功([deviceUploadState]=1)/失败(0)后
  /// 都新增一条投屏记录。[taskId] 再次投屏链路没有，为空时不传（后端沿用旧记录不需要）。
  static Future<dynamic> addUserProductImgRecord({
    Object? upirId,
    Object? userProductId,
    String? img,
    String? imgBle,
    Object? taskId,
    int deviceUploadState = 1,
  }) {
    return _http.postJson('/Client/UserProduct/addUserProductImgRecord', body: {
      if (upirId != null) 'upirId': upirId,
      if (userProductId != null) 'userProductId': userProductId,
      if (img != null) 'img': img,
      if (imgBle != null) 'imgBle': imgBle,
      if (taskId != null) 'taskId': taskId,
      'deviceUploadState': deviceUploadState,
    });
  }
}
