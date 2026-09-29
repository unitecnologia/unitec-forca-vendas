/// Espelho de [PdvFinalizarPagamentosHelper] do ERP (prazo financeiro da forma).
///
/// Critério e geração de dias devem permanecer idênticos ao ERP para o app
/// e o Monitor não divergirem no carnê/boleto.
library;

/// Prazo financeiro válido: max >= 1 e intervalo > 0, excluindo o default
/// de instalação/formulário (1 × 30).
bool isPrazoFinanceiroValido(int maxParcelas, int intervaloParcelas) {
  if (maxParcelas < 1 || intervaloParcelas <= 0) return false;
  if (maxParcelas == 1 && intervaloParcelas == 30) return false;
  return true;
}

/// Dias absolutos: 1..max → intervalo * i  (ex.: 1×7 → [7]; 3×30 → [30,60,90]).
List<int> diasDePrazoFinanceiro(int maxParcelas, int intervaloParcelas) {
  final max = maxParcelas < 1 ? 1 : maxParcelas;
  final intervalo = intervaloParcelas < 0 ? 0 : intervaloParcelas;
  return [for (var i = 1; i <= max; i++) intervalo * i];
}

/// Lê max/intervalo de um row de `formas_pagamento` (SQLite ou sync).
(int max, int intervalo) lerParcelasForma(Map<String, dynamic>? forma) {
  if (forma == null) return (0, 0);
  final max = _asInt(forma['max_parcelas']) ?? 0;
  final intervalo = _asInt(forma['intervalo_parcelas']) ?? 0;
  return (max, intervalo);
}

/// Dias do prazo financeiro da forma, ou null se inválido/default.
List<int>? diasPrazoFinanceiroDaForma(Map<String, dynamic>? forma) {
  final (max, intervalo) = lerParcelasForma(forma);
  if (!isPrazoFinanceiroValido(max, intervalo)) return null;
  return diasDePrazoFinanceiro(max, intervalo);
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}
