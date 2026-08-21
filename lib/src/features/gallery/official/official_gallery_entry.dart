import 'package:flutter/material.dart';

import '../../../routes/app_routes.dart';

/// 官方图库入口开关（对齐小程序 `components/custom-tabbar` 的 `galleryEntryEnabled`）。
///
/// 2026-08-19 起入口挪到**底部 tab 栏第三格**（与小程序同位），原来「我的 → 服务与帮助」
/// 里那一行同步删掉 —— 小程序 `pages/mine/mine.wxml` 的原话：两个入口指同一个页面
/// 只会让人犹豫点哪个。别再在「我的」里加回来。
///
/// 与 `kAiEntryEnabled`（`features/ai/ai_entry.dart`）同理，保留开关只为灰度/应急下线；
/// 改回 `false` 时底栏自动缩格，但**正式包里再没有别的入口**
/// （不像 AI 还留着 debug 构建才可达的调试台暗门）。
const bool kGalleryEntryEnabled = true;

/// 进入官方图库列表页（与小程序 `custom-tabbar goGallery` 同一目标页）。
///
/// 它和 AI 对话页一样**不是 tab**：push 到根 Navigator，返回即回到发起的那个 tab。
void openOfficialGallery(BuildContext context) {
  Navigator.of(context).pushNamed<void>(AppRoutes.officialGallery);
}
