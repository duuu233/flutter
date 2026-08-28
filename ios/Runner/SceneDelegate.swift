import Flutter
import UIKit

/// 微信「URL Scheme 回跳」在 scene 生命周期下的补链。
///
/// 背景（对着 fluwx 6.0.0 / pod fluwx 2.0.5 与 Flutter 引擎 `cc0734ac7` 源码核对）：
///
/// - `FluwxPlugin.h` 声明的是 `<FlutterPlugin, FlutterSceneLifeCycleDelegate>`，但 `.m` 里
///   只实现了 `scene:continueUserActivity:`（Universal Link 那条），URL Scheme 对应的
///   `scene:openURLContexts:` **没有实现**；
/// - 引擎的 `FlutterPluginSceneLifeCycleDelegate` 收到 scene 事件后，先问实现了对应 scene
///   方法的插件，没人认领再走「app 兜底」`sceneFallbackOpenURLContexts:`；而这个兜底会主动
///   跳过所有 `conformsToProtocol:FlutterSceneLifeCycleDelegate` 的插件
///   （`FlutterPluginAppLifeCycleDelegate.pluginSupportsSceneLifecycle:`）—— fluwx 正好中招：
///   声明了已迁移 scene，实际只迁了一半。
///
/// 于是 Universal Link 不可用时（AASA 未部署、抖动、被系统降级），微信按 URL Scheme
/// `wx4cf0c5f38a70d0bc://oauth?code=…` 回跳，事件只落到本方法，scene 链和 app 兜底链都收不到，
/// 最后被引擎当 deep link 推给 Flutter → `AppRoutes` 没有这个路由名 → 「Route not found」页。
///
/// 这里把 URL 原样转回 `UIApplicationDelegate` 链：那条不是 fallback 路径，不跳过 fluwx，
/// 插件即可照常 `WXApi.handleOpenURL:` 把 code 投给 Dart 订阅者
/// （`lib/src/features/account/data/wechat_authorization_client.dart`）。
/// 配套的 `Info.plist` `FlutterDeepLinkingEnabled=false` 负责堵住「兜底推路由」那一步。
///
/// ⚠️ 覆盖范围只到「App 还活着」的回跳，即微信登录的正常路径。App 在用户停留微信期间被系统
/// 回收时，回跳 URL 改走 `scene:willConnectTo:options:` 的 `connectionOptions`，且 Dart 侧
/// 等 code 的 Completer 已随进程消失——那种情况无论怎么转发都补不回这次登录，用户重新点一次
/// 微信登录即可（有 `FlutterDeepLinkingEnabled=false` 兜着，至少不会跳出「Route not found」）。
class SceneDelegate: FlutterSceneDelegate {

  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    let application = UIApplication.shared
    var handled = false

    // 一批可能有多个 URL，逐条转发；任一条被插件消费就不再交给引擎（避免它按 deep link 处理）。
    for context in URLContexts {
      // 按 `UIOpenURLContext.options` 还原 app 侧的 options 字典，与引擎自己的
      // `ConvertOptions()` 对齐；fluwx 本身不读这些字段，保真只是为了不给其他插件挖坑。
      var options: [UIApplication.OpenURLOptionsKey: Any] = [
        .openInPlace: context.options.openInPlace
      ]
      if let sourceApplication = context.options.sourceApplication {
        options[.sourceApplication] = sourceApplication
      }
      if let annotation = context.options.annotation {
        options[.annotation] = annotation
      }

      if application.delegate?.application?(
        application,
        open: context.url,
        options: options
      ) == true {
        handled = true
      }
    }

    if !handled {
      super.scene(scene, openURLContexts: URLContexts)
    }
  }
}
