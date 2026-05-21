import 'package:flutter/material.dart';

import '../../../state.dart';

class DemoPage extends StatefulWidget {
  const DemoPage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '这个顶部导航栏的文字1',
      home: Scaffold(
        // 💡 核心改动 1：最外层使用 Stack 建立上下层级关系
        body: Stack(
          children: [
            // 【第一层：最底层的背景图】
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 300, // 👈 顶部背景图高度（建议先设为300，900会填满整个屏幕）
              child: Image.asset(
                'images/1.png',
                fit: BoxFit.cover, // 宽度100%撑满
              ),
            ),

            // 【第二层：悬浮在背景图之上的所有内容】
            // 💡 核心改动 2：将 Column 换成 ListView，这样内容多了可以上下滚动，且自带安全区域
            SafeArea(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  // 💡 核心改动 3：顶部加一个透明间距，让按钮刚好落在背景图下方（或者留在图上）

                  // 下方其它组件
                  _buildNetworkImage(),
                  _sectionTitle('头像'),
                  const SizedBox(height: 100),

                  // 1. 基础按钮（悬浮在背景图上方）
                  ElevatedButton(
                    onPressed: () {
                      debugPrint('基础按钮被点击了');
                    },
                    child: const Text('基础按钮'),
                  ),
                  const SizedBox(height: 20),

                  const CircleAvatar(
                    radius: 80, // 👈 头像半径（总直径就是 80 像素）
                    backgroundImage: AssetImage('images/logo.png'), // 本地图片路径
                  ),

                  // 4. 禁用状态
                  const ElevatedButton(onPressed: null, child: Text('禁用状态')),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 标题小组件
Widget _sectionTitle(String title) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8.0),
    child: Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    ),
  );
}

// 加载网络图片
Widget _buildNetworkImage() {
  return Image.asset(
    'images/logo.png', // 测试图源
    height: 40,
    width: 40,
  );
}
