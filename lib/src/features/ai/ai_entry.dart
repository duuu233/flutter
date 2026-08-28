import 'package:flutter/material.dart';

import '../../routes/app_routes.dart';
import '../../state.dart';
import 'ai_last_session.dart';
import 'presentation/ai_chat_page.dart';

/// AI助手入口开关（对齐小程序 `components/custom-tabbar` 的 `aiEntryEnabled`）。
///
/// 2026-08-19 起**正式开放**（小程序侧 `aiEntryEnabled: true` 已开放在先）：首页/我的的
/// 自绘底部 tab 栏中间多出「AI助手」一格，点它调 [openAiChat]。两个 tab 各画各的栏，
/// 所以入口在 `home_widgets._HomeTabBar` 与 `mine_page._MineTabBar` **两处**。
///
/// 保留这个开关只为后续灰度/应急下线（同小程序注释口径）。改回 `false` 时底栏自动缩回
/// 「首页 / 我的」两格，此时仍可走「硬件联调调试台」底部暗门（口令 [kAiEntryGateCode]）
/// 进入验收——但调试台只在 debug 构建可达（见 `routes/app_routes.dart`），
/// **正式包关掉开关就等于整块功能不可见**。
const bool kAiEntryEnabled = true;

/// 屏蔽期的暗门口令（与小程序调试台 `AI_ENTRY_GATE_CODE` 保持一致）。
const String kAiEntryGateCode = '8866';

/// 进入 AI 对话页（与小程序 `custom-tabbar goAi` 同一目标页）。
///
/// 2026-08-13 起**接着上次那一页**（见 [AiLastSession]）：上次停在某条会话就带着
/// `sessionId` 进去（与从会话列表点进去同一条路），停在默认页则仍是默认空态。
Future<void> openAiChat(BuildContext context, PhotoFrameState state) {
  final lastSessionId = AiLastSession.sessionId;
  return Navigator.of(context).push<void>(
    AppPageRoute<void>(
      builder: (_) => AiChatPage(
        state: state,
        sessionId: lastSessionId.isEmpty ? null : lastSessionId,
        sessionTitle: lastSessionId.isEmpty ? null : AiLastSession.title,
      ),
    ),
  );
}
