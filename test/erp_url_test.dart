import 'package:flutter_test/flutter_test.dart';
import 'package:unitec_forca_vendas/config/erp_url.dart';

void main() {
  group('ErpUrl.normalize', () {
    test('túnel unierp.uk sem porta', () {
      expect(
        ErpUrl.normalize('https://alencardeoliveira.unierp.uk'),
        'https://alencardeoliveira.unierp.uk',
      );
      expect(
        ErpUrl.normalize('alencardeoliveira.unierp.uk'),
        'https://alencardeoliveira.unierp.uk',
      );
    });

    test('remove :8765 / :8000 de unierp.uk', () {
      expect(
        ErpUrl.normalize('https://alencardeoliveira.unierp.uk:8765'),
        'https://alencardeoliveira.unierp.uk',
      );
      expect(
        ErpUrl.normalize('alencardeoliveira.unierp.uk:8765'),
        'https://alencardeoliveira.unierp.uk',
      );
      expect(
        ErpUrl.normalize('https://loja.unierp.uk:8000'),
        'https://loja.unierp.uk',
      );
    });

    test('IP local ganha :8765', () {
      expect(ErpUrl.normalize('192.168.0.53'), 'http://192.168.0.53:8765');
      expect(
        ErpUrl.normalize('http://192.168.0.53:8765'),
        'http://192.168.0.53:8765',
      );
    });
  });
}
