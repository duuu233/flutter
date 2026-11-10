// restore-builtin 新增选填 scene（2026-11-10，同小程序）：原入参与返回不变，scene 有值才带、原样传；
// 一键清空、我的相册全删传 DELETE_ALL_PHOTOS，删除设备不传。
import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/network/iot/iot_api.dart';

void main() {
  test('restore-builtin body：scene 选填', () {
    expect(IotApi.restoreSceneDeleteAllPhotos, 'DELETE_ALL_PHOTOS');
    expect(
      IotApi.restoreBuiltinBody('d0:cf:13:f0:2f:f8', renderMode: 'fpga16'),
      {'deviceNo': 'D0CF13F02FF8', 'renderMode': 'fpga16'},
      reason: '不给 scene：body 与原来一致（删除设备）',
    );
    expect(
      IotApi.restoreBuiltinBody(
        'D0CF13F02FF8',
        renderMode: 'fpga16',
        scene: IotApi.restoreSceneDeleteAllPhotos,
      ),
      {'deviceNo': 'D0CF13F02FF8', 'renderMode': 'fpga16', 'scene': 'DELETE_ALL_PHOTOS'},
    );
    expect(IotApi.restoreBuiltinBody('D0CF13F02FF8'), {'deviceNo': 'D0CF13F02FF8'}, reason: '空 renderMode / scene 都不带');
  });
}
