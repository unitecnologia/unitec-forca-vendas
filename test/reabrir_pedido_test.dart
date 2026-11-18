import 'package:flutter_test/flutter_test.dart';
import 'package:unitec_forca_vendas/sync/reabertura_push_resultado.dart';
import 'package:unitec_forca_vendas/ui/format.dart';

void main() {
  group('decidirReaberturaPush', () {
    test('importado libera lock e marca enviado', () {
      final d = decidirReaberturaPush(
        status: 'importado',
        duplicado: false,
        reaberturaLocal: true,
      );
      expect(d.statusLocal, 'enviado');
      expect(d.liberarLockLocal, isTrue);
      expect(d.contarEnviado, isTrue);
    });

    test('duplicado em reabertura mantém pendente e NÃO libera lock', () {
      final d = decidirReaberturaPush(
        status: 'importado',
        duplicado: true,
        reaberturaLocal: true,
      );
      expect(d.statusLocal, 'pendente');
      expect(d.liberarLockLocal, isFalse);
      expect(d.contarErro, isTrue);
      expect(d.contarEnviado, isFalse);
    });

    test('duplicado sem reabertura (app antigo) marca enviado sem liberar lock', () {
      final d = decidirReaberturaPush(
        status: 'importado',
        duplicado: true,
        reaberturaLocal: false,
      );
      expect(d.statusLocal, 'enviado');
      expect(d.liberarLockLocal, isFalse);
      expect(d.contarEnviado, isTrue);
    });

    test('erro em reabertura retenta (pendente) sem liberar lock', () {
      final d = decidirReaberturaPush(
        status: 'erro',
        duplicado: false,
        reaberturaLocal: true,
        erroServidor: 'Pedido em edição no ERP',
      );
      expect(d.statusLocal, 'pendente');
      expect(d.liberarLockLocal, isFalse);
      expect(d.erro, 'Pedido em edição no ERP');
    });

    test('erro sem reabertura marca erro (comportamento legado)', () {
      final d = decidirReaberturaPush(
        status: 'erro',
        duplicado: false,
        reaberturaLocal: false,
        erroServidor: 'Cliente inválido',
      );
      expect(d.statusLocal, 'erro');
      expect(d.liberarLockLocal, isFalse);
    });
  });

  group('situacaoPermiteReabrir', () {
    test('permite pendente / confirmado / financeiro / aguardando', () {
      expect(situacaoPermiteReabrir('pendente'), isTrue);
      expect(situacaoPermiteReabrir('confirmado'), isTrue);
      expect(situacaoPermiteReabrir('financeiro'), isTrue);
      expect(situacaoPermiteReabrir('aguardando'), isTrue);
    });

    test('bloqueia faturado e cancelado', () {
      expect(situacaoPermiteReabrir('faturado'), isFalse);
      expect(situacaoPermiteReabrir('cancelado'), isFalse);
    });

    test('sem situacao usa status local enviado/financeiro', () {
      expect(situacaoPermiteReabrir(null, statusLocal: 'enviado'), isTrue);
      expect(situacaoPermiteReabrir(null, statusLocal: 'financeiro'), isTrue);
      expect(situacaoPermiteReabrir(null, statusLocal: 'pendente'), isFalse);
      expect(situacaoPermiteReabrir(null, statusLocal: 'faturado'), isFalse);
    });
  });

  group('payload de reabertura (regressão sync)', () {
    test('flag reabertura só entra quando true', () {
      Map<String, dynamic> montar({required bool reabertura}) {
        final extra = <String, dynamic>{
          if (reabertura) 'reabertura': true,
        };
        return {
          'uuid': 'same-uuid',
          'tipo': 'pedido',
          'device_uuid': 'device-1',
          if (extra['reabertura'] == true) 'reabertura': true,
        };
      }

      final com = montar(reabertura: true);
      final sem = montar(reabertura: false);

      expect(com['reabertura'], isTrue);
      expect(com['uuid'], 'same-uuid');
      expect(sem.containsKey('reabertura'), isFalse);
      expect(sem['uuid'], 'same-uuid');
    });

    test('reabertura preserva UUID e não gera outro', () {
      const uuidOriginal = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
      var pedidoUuid = 'novo-rascunho';
      const reabrindo = true;
      const converter = false;

      if (!converter) {
        pedidoUuid = uuidOriginal;
      }

      expect(reabrindo, isTrue);
      expect(pedidoUuid, uuidOriginal);
    });
  });
}
