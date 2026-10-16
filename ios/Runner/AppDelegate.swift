import Flutter
import UIKit
import CoreBluetooth
import CoreLocation
// PHPhotoLibrary / PHAssetChangeRequest 在 Photos 里（PhotosUI 只给 PHPicker 那套）。
// 靠 PhotosUI 的伞头间接带出来能不能编过依赖模块的 re-export 规则，显式写一行不留悬念。
import Photos
import PhotosUI
import AVFoundation
import StoreKit
import Darwin

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var deviceApi: DeviceApiHandler?
  private var appleIap: AppleIapHandler?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BoltStarAppleIap") {
      let channel = FlutterMethodChannel(
        name: "com.boltfox.boltstar/apple_iap", binaryMessenger: registrar.messenger()
      )
      let handler = AppleIapHandler(channel: channel)
      appleIap = handler
      channel.setMethodCallHandler { call, result in
        handler.handle(call, result: result)
      }
    }

    // 注册与 Android MainActivity.kt 行为对齐的原生设备通道（权限 / 蓝牙状态 / 相册 / 图片解码）。
    // 缺了它，iOS 上 NativeDeviceApi 的任一方法都会抛 MissingPluginException，绑定/投屏链路不可用。
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BoltStarDeviceApi") {
      let channel = FlutterMethodChannel(
        name: "com.boltfox.boltstar/device_api",
        binaryMessenger: registrar.messenger()
      )
      let handler = DeviceApiHandler()
      deviceApi = handler
      channel.setMethodCallHandler { call, result in
        handler.handle(call, result: result)
      }
    }
  }
}

/// iOS 侧「设备 API」通道实现，逐一对齐 `android/.../MainActivity.kt`：
/// getStatus / requestBluetoothPermissions / requestLocationPermission /
/// requestCameraPermission / openGallery /
/// decodeImageRgba / openBluetoothSettings / openAppSettings。
///
/// 返回给 Dart 的状态字段与 `DevicePermissionStatus.fromMap` 完全一致：
/// bluetoothAvailable / bluetoothEnabled / bluetoothPermissionGranted /
/// locationPermissionGranted / cameraPermissionGranted。
final class DeviceApiHandler: NSObject {
  // 蓝牙适配器状态只能通过 CBCentralManager 实例读取；ShowPowerAlert=false 避免系统弹「请开蓝牙」。
  // 首次创建/使用会触发系统蓝牙权限弹窗（即 requestBluetoothPermissions 的语义）。
  private lazy var centralManager: CBCentralManager = {
    return CBCentralManager(
      delegate: self,
      queue: nil,
      options: [CBCentralManagerOptionShowPowerAlertKey: false]
    )
  }()
  private lazy var locationManager: CLLocationManager = {
    let manager = CLLocationManager()
    manager.delegate = self
    return manager
  }()

  /// 等用户回答系统权限弹窗的兜底上限。
  ///
  /// ⚠️ 这**不是**「等多久算超时」，而是「回调万一永不触发时兜底多久」——正常路径下
  /// 用户一作答，didUpdateState / didChangeAuthorization 立刻回调并把 pending 置空，
  /// 这个计时器随即变成空转，等多久都不影响体验。
  ///
  /// 原值 4s/5s 太短，制造了「首次安装要点两次」：首次安装的系统弹窗用户常要读几秒才点
  /// 「允许」，超过 4s 兜底就先带着 `.notDetermined`（即 granted=false）返回了 →
  /// Dart 侧 PermissionGate 判定为「被拒绝」弹出「去设置」引导框 → 用户懵了关掉、
  /// 再点一次才连上。而用户真正点「允许」后到来的那次回调，因 pending 已被置空被直接丢弃。
  private static let permissionAnswerTimeout: TimeInterval = 30

  private var pendingBluetoothResult: FlutterResult?
  private var pendingLocationResult: FlutterResult?
  private var pendingGalleryResult: FlutterResult?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getStatus":
      result(buildStatus())
    case "requestBluetoothPermissions":
      requestBluetooth(result)
    case "requestLocationPermission":
      requestLocation(result)
    case "requestCameraPermission":
      requestCamera(result)
    case "openGallery":
      openGallery(result)
    case "saveImageToGallery":
      saveImageToGallery(call, result: result)
    case "decodeImageRgba":
      decodeImageRgba(call, result: result)
    case "openBluetoothSettings", "openAppSettings":
      openAppSettings(result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - 保存到系统相册

  /// 把本地文件写进系统相册（AI 生成图的「下载」，2026-08-28；对齐 Android 的
  /// `saveImageToGallery` → MediaStore）。
  ///
  /// 权限用 **addOnly**（iOS 14+）：只往相册里加照片，不读用户已有的照片 ——
  /// 系统弹窗的措辞也随之从「访问所有照片」变成「添加照片」，用户更容易点同意。
  /// iOS 14 以下没有 addOnly，只能退回整库读写授权。
  /// Info.plist 里对应的是 `NSPhotoLibraryAddUsageDescription`（与选图用的
  /// `NSPhotoLibraryUsageDescription` 是两条，缺了会在请求授权时直接崩）。
  private func saveImageToGallery(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let path = (args?["path"] as? String) ?? ""
    guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
      result(FlutterError(code: "not_found", message: "文件不存在", details: path))
      return
    }
    let url = URL(fileURLWithPath: path)

    func finish(_ success: Bool, _ error: Error?) {
      DispatchQueue.main.async {
        if success {
          result(true)
        } else {
          result(FlutterError(
            code: "save_failed",
            message: error?.localizedDescription ?? "写入相册失败",
            details: nil
          ))
        }
      }
    }

    func performSave() {
      PHPhotoLibrary.shared().performChanges({
        PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
      }, completionHandler: finish)
    }

    func denied() {
      DispatchQueue.main.async {
        result(FlutterError(code: "permission_denied", message: "相册权限未授予", details: nil))
      }
    }

    if #available(iOS 14, *) {
      PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
        // .limited 也能加照片（受限访问只限制「读」）。
        if status == .authorized || status == .limited {
          performSave()
        } else {
          denied()
        }
      }
    } else {
      PHPhotoLibrary.requestAuthorization { status in
        if status == .authorized {
          performSave()
        } else {
          denied()
        }
      }
    }
  }

  // MARK: - 状态汇总

  private func buildStatus() -> [String: Bool] {
    let btState = centralManager.state
    let btAvailable = btState != .unsupported
    let btEnabled = btState == .poweredOn
    var btPermission = true
    if #available(iOS 13.1, *) {
      btPermission = CBManager.authorization == .allowedAlways
    } else if #available(iOS 13.0, *) {
      btPermission = centralManager.authorization == .allowedAlways
    }
    return [
      "bluetoothAvailable": btAvailable,
      "bluetoothEnabled": btEnabled,
      "bluetoothPermissionGranted": btPermission,
      "locationPermissionGranted": isLocationGranted(),
      "cameraPermissionGranted": AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
    ]
  }

  // MARK: - 蓝牙

  private func requestBluetooth(_ result: @escaping FlutterResult) {
    // 访问 centralManager 触发创建（首次使用会弹权限）。状态是异步的：state==.unknown 时
    // 等 didUpdateState 回调后再返回真实状态；兜底计时器避免永远不回。
    if centralManager.state == .unknown {
      pendingBluetoothResult = result
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.permissionAnswerTimeout) { [weak self] in
        guard let self = self, let pending = self.pendingBluetoothResult else { return }
        self.pendingBluetoothResult = nil
        pending(self.buildStatus())
      }
    } else {
      result(buildStatus())
    }
  }

  // MARK: - 定位

  private func isLocationGranted() -> Bool {
    let status: CLAuthorizationStatus
    if #available(iOS 14, *) {
      status = locationManager.authorizationStatus
    } else {
      status = CLLocationManager.authorizationStatus()
    }
    return status == .authorizedWhenInUse || status == .authorizedAlways
  }

  private func requestLocation(_ result: @escaping FlutterResult) {
    let status: CLAuthorizationStatus
    if #available(iOS 14, *) {
      status = locationManager.authorizationStatus
    } else {
      status = CLLocationManager.authorizationStatus()
    }
    if status == .notDetermined {
      pendingLocationResult = result
      locationManager.requestWhenInUseAuthorization()
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.permissionAnswerTimeout) { [weak self] in
        guard let self = self, let pending = self.pendingLocationResult else { return }
        self.pendingLocationResult = nil
        pending(self.buildStatus())
      }
    } else {
      result(buildStatus())
    }
  }

  // MARK: - 相机权限

  private func requestCamera(_ result: @escaping FlutterResult) {
    AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
      DispatchQueue.main.async { result(self?.buildStatus()) }
    }
  }

  // MARK: - 系统设置

  private func openAppSettings(_ result: @escaping FlutterResult) {
    // iOS 无公开 API 直达「蓝牙设置」；统一跳到本 App 的系统设置页，用户在此开启蓝牙/定位权限。
    if let url = URL(string: UIApplication.openSettingsURLString) {
      UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
    result(nil)
  }

  // MARK: - 选择相册图片

  private func openGallery(_ result: @escaping FlutterResult) {
    if pendingGalleryResult != nil {
      result(FlutterError(code: "busy", message: "Another gallery request is running.", details: nil))
      return
    }
    guard let presenter = topViewController() else {
      result(FlutterError(code: "no_vc", message: "无可用的视图控制器", details: nil))
      return
    }
    pendingGalleryResult = result
    if #available(iOS 14, *) {
      var config = PHPickerConfiguration()
      config.filter = .images
      config.selectionLimit = 1
      let picker = PHPickerViewController(configuration: config)
      picker.delegate = self
      presenter.present(picker, animated: true)
    } else {
      let picker = UIImagePickerController()
      picker.sourceType = .photoLibrary
      picker.delegate = self
      presenter.present(picker, animated: true)
    }
  }

  /// 把选中的 UIImage 写到临时目录，返回 {uri(文件路径), title, width, height(像素)}，
  /// 供 Dart 端随后调 decodeImageRgba 解码裁剪。
  private func saveTempImage(_ image: UIImage) -> [String: Any]? {
    guard let data = image.jpegData(compressionQuality: 0.95) else { return nil }
    let stamp = Int(Date().timeIntervalSince1970 * 1000)
    let filename = "boltstar_pick_\(stamp).jpg"
    let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
    do {
      try data.write(to: url)
    } catch {
      return nil
    }
    return [
      "uri": url.path,
      "title": filename,
      "width": Int(image.size.width * image.scale),
      "height": Int(image.size.height * image.scale),
    ]
  }

  // MARK: - 解码 + 中心裁剪覆盖到设备分辨率 → RGBA

  private func decodeImageRgba(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let uri = args["uri"] as? String,
          let width = args["width"] as? Int,
          let height = args["height"] as? Int,
          width > 0, height > 0 else {
      result(FlutterError(code: "bad_args", message: "uri/width/height 必填且需 > 0", details: nil))
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      guard let image = self.loadImage(uri: uri),
            let data = self.imageToRgba(image, targetW: width, targetH: height) else {
        DispatchQueue.main.async {
          result(FlutterError(code: "decode_failed", message: "图片解码失败", details: nil))
        }
        return
      }
      DispatchQueue.main.async {
        result(FlutterStandardTypedData(bytes: data))
      }
    }
  }

  private func loadImage(uri: String) -> UIImage? {
    if uri.hasPrefix("file://"), let url = URL(string: uri) {
      return UIImage(contentsOfFile: url.path)
    }
    return UIImage(contentsOfFile: uri)
  }

  /// 等比放大到盖满目标、中心裁剪出 targetW×targetH，输出 RGBA（每像素 R,G,B,A 共 4 字节，
  /// 行序自上而下，与 Android decodeToRgba 对齐）。UIImage.draw 会自动应用 EXIF 方向。
  private func imageToRgba(_ image: UIImage, targetW: Int, targetH: Int) -> Data? {
    let imgW = image.size.width
    let imgH = image.size.height
    guard imgW > 0, imgH > 0 else { return nil }

    // 1) 中心裁剪覆盖并缩放到目标尺寸，得到一张正立的位图。
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(
      size: CGSize(width: targetW, height: targetH),
      format: format
    )
    let rendered = renderer.image { _ in
      let scale = max(CGFloat(targetW) / imgW, CGFloat(targetH) / imgH)
      let drawW = imgW * scale
      let drawH = imgH * scale
      let dx = (CGFloat(targetW) - drawW) / 2
      let dy = (CGFloat(targetH) - drawH) / 2
      image.draw(in: CGRect(x: dx, y: dy, width: drawW, height: drawH))
    }
    guard let cg = rendered.cgImage else { return nil }

    // 2) 抽 RGBA 字节。CGContext 原点在左下，绘制前做垂直翻转，使 buffer 行 0 = 图片顶部，
    //    与 Android getPixels 的自上而下行序一致（否则上屏会上下颠倒）。
    var buffer = [UInt8](repeating: 0, count: targetW * targetH * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
      data: &buffer,
      width: targetW,
      height: targetH,
      bitsPerComponent: 8,
      bytesPerRow: targetW * 4,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
      return nil
    }
    ctx.translateBy(x: 0, y: CGFloat(targetH))
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
    return Data(buffer)
  }

  // MARK: - 工具

  private func keyWindow() -> UIWindow? {
    let scenes = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
    for scene in scenes {
      if let win = scene.windows.first(where: { $0.isKeyWindow }) {
        return win
      }
    }
    return scenes.first?.windows.first
  }

  private func topViewController() -> UIViewController? {
    var top = keyWindow()?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}

// MARK: - CBCentralManagerDelegate

extension DeviceApiHandler: CBCentralManagerDelegate {
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if let pending = pendingBluetoothResult {
      pendingBluetoothResult = nil
      pending(buildStatus())
    }
  }
}

// MARK: - CLLocationManagerDelegate

extension DeviceApiHandler: CLLocationManagerDelegate {
  // 该（在 iOS 14 已弃用但仍会触发）回调覆盖全部系统版本；notDetermined 首帧忽略，等用户作答后再返回。
  func locationManager(
    _ manager: CLLocationManager,
    didChangeAuthorization status: CLAuthorizationStatus
  ) {
    if status == .notDetermined { return }
    if let pending = pendingLocationResult {
      pendingLocationResult = nil
      pending(buildStatus())
    }
  }
}

// MARK: - PHPickerViewControllerDelegate（iOS 14+）

@available(iOS 14, *)
extension DeviceApiHandler: PHPickerViewControllerDelegate {
  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    picker.dismiss(animated: true)
    let callback = pendingGalleryResult
    pendingGalleryResult = nil
    guard let provider = results.first?.itemProvider,
          provider.canLoadObject(ofClass: UIImage.self) else {
      callback?(nil) // 用户取消或不可加载
      return
    }
    provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
      let image = object as? UIImage
      let info = image.flatMap { self?.saveTempImage($0) }
      DispatchQueue.main.async { callback?(info) }
    }
  }
}

// MARK: - UIImagePickerControllerDelegate（iOS 13 及以下兜底）

extension DeviceApiHandler: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
  func imagePickerController(
    _ picker: UIImagePickerController,
    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
  ) {
    picker.dismiss(animated: true)
    let callback = pendingGalleryResult
    pendingGalleryResult = nil
    let image = info[.originalImage] as? UIImage
    callback?(image.flatMap { saveTempImage($0) })
  }

  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true)
    let callback = pendingGalleryResult
    pendingGalleryResult = nil
    callback?(nil)
  }
}


/// Original StoreKit API is intentional: the server accepts Base64 app receipts,
/// not StoreKit 2 JWS. Successful consumables stay unfinished until delivery is
/// confirmed. Failed transactions are finished, and their result is retained
/// until Dart acknowledges it, including across a process restart.
private final class AppleIapHandler: NSObject, SKPaymentTransactionObserver,
  SKProductsRequestDelegate, SKRequestDelegate {
  private let channel: FlutterMethodChannel
  private let queue = SKPaymentQueue.default()
  private var observing = false
  private var products: [String: SKProduct] = [:]
  private var productRequests: [ObjectIdentifier: SKProductsRequest] = [:]
  private var productResults: [ObjectIdentifier: FlutterResult] = [:]
  private var productIds: [ObjectIdentifier: String] = [:]
  private var receiptRequest: SKReceiptRefreshRequest?
  private var receiptResult: FlutterResult?
  private static let requestKey = "boltstar.appleIap.requests.v1"
  private static let failureKey = "boltstar.appleIap.failures.v1"

  init(channel: FlutterMethodChannel) { self.channel = channel; super.init() }
  deinit { if observing { queue.remove(self) } }

  private var requests: [String: String] {
    get { UserDefaults.standard.dictionary(forKey: Self.requestKey) as? [String: String] ?? [:] }
    set { UserDefaults.standard.set(newValue, forKey: Self.requestKey) }
  }

  private var failures: [[String: String]] {
    get { UserDefaults.standard.array(forKey: Self.failureKey) as? [[String: String]] ?? [] }
    set { UserDefaults.standard.set(newValue, forKey: Self.failureKey) }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "initialize":
      if !observing { observing = true; queue.add(self) }
      var info = utsname()
      uname(&info)
      let model = Mirror(reflecting: info.machine).children.reduce(into: "") { value, child in
        guard let byte = child.value as? Int8, byte != 0 else { return }
        value.append(String(UnicodeScalar(UInt8(bitPattern: byte))))
      }
      result(["canMakePayments": SKPaymentQueue.canMakePayments(),
        "device": model.isEmpty ? UIDevice.current.model : model,
        "bundleId": Bundle.main.bundleIdentifier ?? ""])
    case "product":
      guard let id = args["productId"] as? String, !id.isEmpty else {
        result(productError("product_unavailable", message: "Missing Apple product ID",
          details: ["reason": "apple_product_id_empty"])); return
      }
      let request = SKProductsRequest(productIdentifiers: [id])
      let key = ObjectIdentifier(request)
      productRequests[key] = request; productResults[key] = result
      productIds[key] = id
      logProduct("request", ["productId": id, "timeoutSeconds": 30])
      request.delegate = self; request.start()
      DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
        guard let self = self, let callback = self.productResults.removeValue(forKey: key) else { return }
        self.productRequests.removeValue(forKey: key)?.cancel()
        let id = self.productIds.removeValue(forKey: key) ?? ""
        callback(self.productError("product_timeout", message: "StoreKit product request timed out",
          details: ["reason": "storekit_product_timeout", "productId": id, "timeoutSeconds": 30]))
      }
    case "buy":
      guard let id = args["productId"] as? String,
        let token = args["accountToken"] as? String, UUID(uuidString: token) != nil else {
        result(error("invalid_arguments")); return
      }
      guard SKPaymentQueue.canMakePayments() else { result(error("payment_not_allowed")); return }
      guard let product = products[id] else { result(error("product_unavailable")); return }
      // The persisted UUID prevents duplicate add(payment) after a lost reply.
      guard requests.isEmpty && queue.transactions.isEmpty else {
        result(error("payment_busy")); return
      }
      var saved = requests; saved[token] = id; requests = saved
      let payment = SKMutablePayment(product: product)
      payment.quantity = 1; payment.applicationUsername = token
      queue.add(payment)
      result(nil)
    case "pendingTransactions":
      var rows = queue.transactions.map(summary)
      let seen = Set(rows.compactMap { ($0["accountToken"] as? String)?.lowercased() })
      for (token, product) in requests where !seen.contains(token.lowercased()) {
        rows.append(["accountToken": token, "productId": product, "state": "requested"])
      }
      rows.append(contentsOf: failures.map { $0 as [String: Any] })
      result(rows)
    case "acknowledgeFailure":
      if let token = args["accountToken"] as? String {
        failures = failures.filter { $0["accountToken"]?.lowercased() != token.lowercased() }
      }
      result(nil)
    case "receipt":
      if let receipt = readReceipt() { result(receipt); return }
      guard args["refreshIfMissing"] as? Bool == true else {
        result(error("receipt_missing")); return
      }
      guard receiptRequest == nil else { result(error("receipt_busy")); return }
      let request = SKReceiptRefreshRequest()
      receiptRequest = request; receiptResult = result
      request.delegate = self; request.start()
      DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self, weak request] in
        guard let self = self, let request = request, self.receiptRequest === request else { return }
        request.cancel(); self.completeReceipt(self.error("receipt_timeout"))
      }
    case "finish":
      guard let id = args["transactionId"] as? String,
        let token = args["accountToken"] as? String, !id.isEmpty else {
        result(error("invalid_arguments")); return
      }
      if let transaction = queue.transactions.first(where: { $0.transactionIdentifier == id }) {
        guard let owner = transaction.payment.applicationUsername,
          let ownerId = UUID(uuidString: owner), let expectedId = UUID(uuidString: token),
          ownerId == expectedId,
          transaction.transactionState == .purchased || transaction.transactionState == .restored else {
          result(error("transaction_mismatch")); return
        }
        queue.finishTransaction(transaction)
      }
      // No queue entry can mean finish succeeded before Dart persisted removal.
      requests = requests.filter { $0.key.lowercased() != token.lowercased() }
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func error(_ code: String) -> FlutterError {
    FlutterError(code: code, message: nil, details: nil)
  }

  /// Product diagnostics exclude userInfo, receipts and payment/account identifiers.
  private func productText(_ text: String) -> String {
    var safe = text.replacingOccurrences(of: #"https?://\S+"#, with: "[url]", options: [.regularExpression, .caseInsensitive])
    safe = safe.replacingOccurrences(of: #"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}"#, with: "[email]", options: .regularExpression)
    safe = safe.replacingOccurrences(
      of: #"(?i)(receiptData|latestReceipt|responseData|userToken|jwtToken|authorization|authentication|accountToken|password|token)\s*[:=]\s*("[^"]*"|\S+)"#,
      with: "[redacted]", options: .regularExpression)
    return String(safe.prefix(600))
  }

  private func logProduct(_ stage: String, _ fields: [String: Any]) {
    #if DEBUG
    var details = fields
    details["bundleId"] = Bundle.main.bundleIdentifier ?? ""
    if let data = try? JSONSerialization.data(withJSONObject: details, options: [.sortedKeys]),
      let text = String(data: data, encoding: .utf8) {
      NSLog("[AppleIAP][native] product.%@: %@", stage, text)
    }
    #endif
  }

  private func productError(_ code: String, message: String, details: [String: Any]) -> FlutterError {
    var fields = details
    fields["code"] = code
    fields["bundleId"] = Bundle.main.bundleIdentifier ?? ""
    fields["message"] = productText(message)
    logProduct("failed", fields)
    return FlutterError(code: code, message: productText(message), details: fields)
  }

  private func readReceipt() -> String? {
    guard let url = Bundle.main.appStoreReceiptURL,
      let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
    return data.base64EncodedString()
  }

  private func completeReceipt(_ value: Any?) {
    let callback = receiptResult; receiptResult = nil; receiptRequest = nil
    callback?(value)
  }

  func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      let key = ObjectIdentifier(request)
      guard let callback = self.productResults.removeValue(forKey: key) else { return }
      self.productRequests.removeValue(forKey: key)
      let id = self.productIds.removeValue(forKey: key) ?? ""
      let details: [String: Any] = [
        "requestedProductId": id,
        "returnedProductIds": response.products.map { $0.productIdentifier },
        "invalidProductIds": response.invalidProductIdentifiers,
      ]
      self.logProduct("response", details)
      guard let product = response.products.first else {
        callback(self.productError("product_unavailable", message: "StoreKit returned no product",
          details: details.merging(["reason": "storekit_empty_products"]) { _, new in new })); return
      }
      self.products[product.productIdentifier] = product
      let formatter = NumberFormatter()
      formatter.numberStyle = .currency; formatter.locale = product.priceLocale
      let price = formatter.string(from: product.price) ?? ""
      self.logProduct("loaded", ["productId": product.productIdentifier,
        "localizedPrice": price, "priceLocale": product.priceLocale.identifier])
      callback(["productId": product.productIdentifier, "localizedPrice": price])
    }
  }

  func requestDidFinish(_ request: SKRequest) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, self.receiptRequest === request else { return }
      if let receipt = self.readReceipt() { self.completeReceipt(receipt) }
      else { self.completeReceipt(self.error("receipt_missing")) }
    }
  }

  func request(_ request: SKRequest, didFailWithError error: Error) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      if self.receiptRequest === request {
        let native = error as NSError
        self.completeReceipt(FlutterError(code: "receipt_failed",
          message: self.productText(native.localizedDescription), details: [
            "reason": "storekit_receipt_request_failed", "nativeErrorDomain": native.domain,
            "nativeErrorCode": native.code,
          ]))
        return
      }
      let key = ObjectIdentifier(request)
      self.productRequests.removeValue(forKey: key)
      let id = self.productIds.removeValue(forKey: key) ?? ""
      guard let callback = self.productResults.removeValue(forKey: key) else { return }
      let native = error as NSError
      var underlying: [[String: Any]] = []
      var next = native.userInfo[NSUnderlyingErrorKey] as? NSError
      while let item = next, underlying.count < 3 {
        underlying.append(["domain": item.domain, "nativeErrorCode": item.code,
          "nativeMessage": self.productText(item.localizedDescription)])
        next = item.userInfo[NSUnderlyingErrorKey] as? NSError
      }
      callback(self.productError("product_unavailable", message: "StoreKit product request failed", details: [
        "reason": "storekit_request_failed", "productId": id,
        "nativeErrorDomain": native.domain, "nativeErrorCode": native.code,
        "nativeMessage": self.productText(native.localizedDescription), "underlyingErrors": underlying,
      ]))
    }
  }

  private func summary(_ transaction: SKPaymentTransaction) -> [String: Any] {
    let state: String
    switch transaction.transactionState {
    case .purchasing: state = "purchasing"
    case .purchased: state = "purchased"
    case .restored: state = "restored"
    case .deferred: state = "deferred"
    case .failed:
      let code = (transaction.error as NSError?)?.code
      state = code == SKError.Code.paymentCancelled.rawValue ? "canceled" : "failed"
    @unknown default: state = "unknown"
    }
    return ["state": state, "productId": transaction.payment.productIdentifier,
      "accountToken": transaction.payment.applicationUsername ?? "",
      "transactionId": transaction.transactionIdentifier ?? ""]
  }

  func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      for transaction in transactions {
        let row = self.summary(transaction)
        if transaction.transactionState == .failed {
          var saved = self.requests
          if let token = transaction.payment.applicationUsername {
            saved = saved.filter { $0.key.lowercased() != token.lowercased() }
            var failed = self.failures.filter { $0["accountToken"]?.lowercased() != token.lowercased() }
            failed.append(row.compactMapValues { $0 as? String }); self.failures = failed
          }
          self.requests = saved
          queue.finishTransaction(transaction)
        }
        self.channel.invokeMethod("transactionUpdated", arguments: row)
      }
    }
  }
}
