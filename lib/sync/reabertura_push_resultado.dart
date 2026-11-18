/// Decisões puras do resultado do push na reabertura (testável sem SQLite/HTTP).
class ReaberturaPushDecisao {
  const ReaberturaPushDecisao({
    required this.statusLocal,
    required this.liberarLockLocal,
    required this.contarEnviado,
    required this.contarErro,
    this.erro,
  });

  final String statusLocal;
  final bool liberarLockLocal;
  final bool contarEnviado;
  final bool contarErro;
  final String? erro;
}

/// Define o que fazer com a outbox após o ACK do ERP.
ReaberturaPushDecisao decidirReaberturaPush({
  required String status,
  required bool duplicado,
  required bool reaberturaLocal,
  String? situacao,
  String? erroServidor,
}) {
  if (duplicado && reaberturaLocal) {
    return const ReaberturaPushDecisao(
      statusLocal: 'pendente',
      liberarLockLocal: false,
      contarEnviado: false,
      contarErro: true,
      erro: 'Reabertura não aplicada no ERP. Verifique o parâmetro Permitir Reabrir Pedido.',
    );
  }

  if (status == 'importado' || duplicado) {
    final local = (situacao ?? '') == 'financeiro' ? 'financeiro' : 'enviado';
    return ReaberturaPushDecisao(
      statusLocal: local,
      // Só libera após update real (importado sem duplicado). ACK idempotente não mexe no lock.
      liberarLockLocal: status == 'importado' && ! duplicado,
      contarEnviado: true,
      contarErro: false,
    );
  }

  if (status == 'erro') {
    return ReaberturaPushDecisao(
      statusLocal: reaberturaLocal ? 'pendente' : 'erro',
      liberarLockLocal: false,
      contarEnviado: false,
      contarErro: true,
      erro: erroServidor,
    );
  }

  return ReaberturaPushDecisao(
    statusLocal: reaberturaLocal ? 'pendente' : 'erro',
    liberarLockLocal: false,
    contarEnviado: false,
    contarErro: true,
    erro: erroServidor ?? 'Resposta de sync inesperada.',
  );
}
