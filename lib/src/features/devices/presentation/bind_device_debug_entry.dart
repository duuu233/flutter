import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../../routes/app_routes.dart';

/// 绑定页顶部「硬件联调调试台」入口横幅（对齐小程序 `bind.wxml` 的 `debug-entry`）。
///
/// 开发对接 / 硬件联调用：点进去可逐条测试 BLE 指令、看收发的 16 进制原始字节，
/// 也是「搜索不到设备」时的排查工具（放开过滤扫描核对广播名、断开被占用连接释放设备）。
/// 显示在绑定流程三态（搜索中 / 已发现 / 未发现）顶部。
///
/// **仅 debug 构建可见**：调试台能对设备发任意指令（含删除图片类操作）且整页
/// 未接 i18n，不能暴露给最终用户；release 下本组件渲染为空、路由亦被拦截
/// （见 app_routes.dart）。debug 联调流程不受影响。
class BindDebugEntryCard extends StatelessWidget {
  const BindDebugEntryCard({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const SizedBox.shrink();
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () =>
          Navigator.of(context).pushNamed<void>(AppRoutes.bleDebug),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          // 半透明白底 + 橙色描边，对齐小程序 debug-entry（rgba(255,255,255,.72) / 橙边 .22）。
          color: Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0x38FF6421)),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0x14FF6421),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.build_rounded,
                color: Color(0xFFFF621F),
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '硬件联调调试台',
                    style: TextStyle(
                      color: Color(0xFF2A2D32),
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    '开发对接用 · 一键测试上传/删除/电量等全部指令',
                    style: TextStyle(
                      color: Color(0xFF8B9098),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w400,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFFF621F),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
