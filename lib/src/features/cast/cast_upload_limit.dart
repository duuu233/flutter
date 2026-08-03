/// 一次投屏可选照片张数的上限（对应小程序 `utils/upload-limit.js`）。
///
/// 常规用户 10 张（2026-08-02 产品要求由 5 张放宽）；白名单用户放宽到 100 张——
/// 2026-08-01 产品要求：登录接口返回的 `userInfo.userNo` 命中 [whitelistUserNos] 时，
/// 该账号用于内部批量压测/展会演示，需要一次投几十上百张。
///
/// ⚠️ 这是**端上放宽选图张数**，不是后端额度：后端若另有单账号图片总数限制，仍以后端为准。
/// ⚠️ 单独成文件（不放进 `CastPhotoPicker`）是为了避开 `state.dart ↔ cast_photo_picker.dart`
///    的循环 import——这里零依赖，两边都能安全引用。
class CastUploadLimit {
  CastUploadLimit._();

  /// 常规上限：与产品「一次最多投 10 张」口径一致（2026-08-02 由 5 张调整）。
  static const int defaultBatch = 10;

  /// 白名单账号的放宽上限。
  static const int whitelistBatch = 100;

  /// 可一次选 [whitelistBatch] 张的账号 `userNo`（登录接口 `UserInfoApiOut.userNo`）。
  /// 与小程序 `utils/upload-limit.js` 的 `WHITELIST` 同值，改要一起改。
  /// （2026-08-03 追加 `GA6473224`。）
  static const Set<String> whitelistUserNos = {'EF7293235', 'GA6473224'};

  /// 当前登录用户的 `userNo`。由 `PhotoFrameState._applyUserInfo` 写入、`logout` 清空——
  /// 选图入口是静态方法、拿不到 BuildContext/状态对象，故用这个单向同步的静态字段承载。
  static String currentUserNo = '';

  /// 本次可选张数上限：白名单账号 [whitelistBatch]，其余 [defaultBatch]。
  static int get batchLimit =>
      whitelistUserNos.contains(currentUserNo) ? whitelistBatch : defaultBatch;
}
