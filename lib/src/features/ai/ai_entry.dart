import 'package:flutter/material.dart';

import '../../routes/app_routes.dart';
import '../../state.dart';
import 'ai_last_session.dart';
import 'presentation/ai_chat_page.dart';

/// AI生图入口开关（对齐小程序 `components/custom-tabbar` 的 `aiEntryEnabled`）。
///
/// 当前需求：**入口整体屏蔽，后续再开放**。小程序侧是 tabbar 中间那颗「AI生图」按钮隐藏
/// （用空占位保住三栏布局）；App 侧首页/我的的底部 tab 栏同样先不放这颗按钮。
/// 屏蔽期间可走「硬件联调调试台」底部暗门（口令 [kAiEntryGateCode]）临时进入验收。
///
/// 开放时：把这里改 `true`，并在 `home_page` / `mine_page` 的自绘 tab 栏中间调 [openAiChat]
/// （两处都要，两个 tab 各画各的栏）。
const bool kAiEntryEnabled = false;

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
