import 'package:flutter_test/flutter_test.dart';

import 'package:BoltStar/src/network/api_rows.dart';

void main() {
  test('extracts records from the BoltFox pageData field', () {
    final rows = extractApiRows({
      'pageData': [
        {
          'userProductId': 63,
          'productName': 'EF6-589',
          'deviceId': 'E9:48:C2:1E:D4:28',
        },
        {
          'userProductId': 68,
          'productName': 'EF6-370',
          'deviceId': 'E4:48:C2:1E:D4:28',
        },
      ],
      'pageIndex': 1,
      'recordCount': 2,
      'pageCount': 1,
    });

    expect(rows, hasLength(2));
    expect(rows.first['userProductId'], 63);
    expect(rows.last['productName'], 'EF6-370');
  });

  test('continues to support direct and legacy list payloads', () {
    expect(
      extractApiRows([
        {'id': 1},
      ]),
      hasLength(1),
    );
    expect(
      extractApiRows({
        'list': [
          {'id': 2},
        ],
      }),
      hasLength(1),
    );
  });
}
