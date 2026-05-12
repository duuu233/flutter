import 'package:flutter/material.dart';

import '../../../shared/shared.dart';
import '../../../state.dart';

class DemoPage extends StatefulWidget {
  const DemoPage({super.key, required this.state});

  final PhotoFrameState state;

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final Set<String> _selectedIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final state = widget.state;

    return MaterialApp(
      title: '这个顶部导航栏的文字',
      home: Scaffold(
        // appBar: AppBar(title: const Text('111')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 1. 最基础的用法
              ElevatedButton(
                onPressed: () {
                  debugPrint('基础按钮被点击了');
                },
                child: const Text('基础按钮'),
              ),
              const SizedBox(height: 20),
              // 2. 带图标的按钮 (使用 .icon 构造函数)
              ElevatedButton.icon(
                onPressed: () => debugPrint('发送按钮被点击'),
                icon: const Icon(Icons.send),
                label: const Text('发送消息'),
              ),
              const SizedBox(height: 20),
              // 3. 自定义样式的按钮
              ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange, // 背景颜色
                  foregroundColor: Colors.white, // 文字和图标颜色
                  elevation: 5, // 阴影深度
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 15,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30), // 圆角
                  ),
                ),
                child: const Text('圆角橙色按钮'),
              ),
              const SizedBox(height: 20),
              // 4. 禁用状态 (onPressed 为 null 时自动进入禁用状态)
              const ElevatedButton(onPressed: null, child: Text('禁用状态')),
              // 3. Card 与 Text 示例
              const Card(
                child: ListTile(
                  leading: Icon(Icons.info),
                  title: Text(
                    '这是一个卡片标题',
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 24,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  subtitle: Text('这里是副标题描述内容'),
                ),
              ),
              _sectionTitle('1. 网络图片'),
              _buildNetworkImage(),

              // 示例：显示一段带样式的文字和一个图标
              Column(
                children: [
                  Text(
                    '你好 Flutter',
                    style: TextStyle(
                      fontSize: 24,
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Icon(Icons.star, color: Colors.amber, size: 50),
                ],
              ),
              // 示例：一个带圆角和阴影的卡片布局
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
                ),
                child: Row(
                  children: [
                    Icon(Icons.account_circle),
                    SizedBox(width: 10), // 占位间距
                    Expanded(
                      child: Text('用户姓名', style: TextStyle(fontSize: 18)),
                    ),
                    Icon(Icons.arrow_forward_ios),
                  ],
                ),
              ),
              Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      labelText: '请输入密码',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true, // 隐藏输入内容
                  ),
                  ElevatedButton(
                    onPressed: () => print('点击了登录'),
                    child: Text('登录'),
                  ),
                ],
              ),
            ],
          ),
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
  return Image.network(
    'https://picsum.photos', // 测试图源
    height: 150,
    fit: BoxFit.cover, // 告诉图片如何适应容器：充满并裁剪
  );
}
