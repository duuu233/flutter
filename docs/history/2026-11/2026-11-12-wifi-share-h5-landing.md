# WiFi 版设备共享邀请 H5 落地页（main）

> 类型：Historical Implementation Record
> 日期：2026-11-12；环境：远程 SSH 服务器；分支：main；修改前：c76c09b
> 依据：产品确认分享改为「生成链接 → H5 打开 → App 里调接口与房主建立关系」；微信内只提示「点右上角在浏览器打开」；打开 H5 时先判断是否已安装 App，没装先引导安装，再走分享绑定流程。H5 先写好由产品部署，拿到线上网址后再改 App。

## 改动

- 新增 `deploy/share/share.html`（单文件，App 图标 base64 内联，四语种）：
  - 微信 / 企业微信内：遮罩 + 右上角箭头，引导「在浏览器打开」，不尝试跳转；
  - 浏览器内：进页自动拉起 `boltstar://share/accept?<原 query>`（安卓先 intent://，没装回落 `#no-app`；900ms 后补试朴素 scheme），并保留「打开 App」按钮；2.5 秒仍在本页判定没装 → 「下载 App」+ 三步说明 +「已安装，打开 App」；
  - 下载（同日按产品确认改）：地址取后台版本管理 `getLastVersion`（`appVersionNo=0.0.0`，terminal 安卓 1 / iOS 2，`retData.downloadPath`），安卓没给再试 `getAndroidDownload`；进页后台预取，点「下载」即跳；接口默认相对路径（页面与 API 同域名），`API_BASE` 可改绝对地址（需后端放行 CORS）；
  - 链接缺 `d` / `k` 显示「邀请链接无效」；底部可折叠调试日志（`?debug=1` 展开）。
- 新增 `docs/runbooks/WIFI_SHARE_H5.md`：流程、部署、App 侧待办、已知限制。

## 验证

- 无浏览器 / node，页面未实际打开；脚本括号配平与 DOM id 引用用 python 核对通过。
- App 尚未登记 `boltstar://share/accept`（安卓）与 `boltstar` scheme（iOS），发版前链接拉不起 App。
