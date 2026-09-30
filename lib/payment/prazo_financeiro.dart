/// Espelho de [PdvFinalizarPagamentosHelper] do ERP (prazo financeiro da forma).
///
/// Critério e geração de dias devem permanecer idênticos ao ERP para o app
/// e o Monitor não divergirem no carnê/boleto.
library;

/// Prazo financeiro válido.
///
/// Com [modoPrazo] explícito:
/// - `financeiro` → max>=1 e intervalo>0 (inclui 1×30 intencional)
/// - `tabela` → nunca usa max/intervalo para auto-prazo
///
/// Sem modo (app antigo / sync antigo): mantém a heurística histórica
/// excluindo o default de instalação (1 × 30).
bool isPrazoFinanceiroValido(
  int maxParcelas,
  int intervaloParcelas, [
  String? modoPrazo,
]) {
  final modo = (modoPrazo ?? '').trim().toLowerCase();

  if (modo == 'tabela') return false;

  if (modo == 'financeiro') {
    return maxParcelas >= 1 && intervaloParcelas > 0;
  }

  // Legado sem modo_prazo (compatibilidade com app/ERP antigos).
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

/// Lê max/intervalo/modo de um row de `formas_pagamento` (SQLite ou sync).
(int max, int intervalo, String? modo) lerParcelasForma(Map<String, dynamic>? forma) {
  if (forma == null) return (0, 0, null);
  final max = _asInt(forma['max_parcelas']) ?? 0;
  final intervalo = _asInt(forma['intervalo_parcelas']) ?? 0;
  final modoRaw = forma['modo_prazo']?.toString().trim();
  final modo = (modoRaw == null || modoRaw.isEmpty) ? null : modoRaw.toLowerCase();
  return (max, intervalo, modo);
}

/// Dias do prazo financeiro da forma, ou null se inválido/modo tabela/default.
List<int>? diasPrazoFinanceiroDaForma(Map<String, dynamic>? forma) {
  final (max, intervalo, modo) = lerParcelasForma(forma);
  if (!isPrazoFinanceiroValido(max, intervalo, modo)) return null;
  return diasDePrazoFinanceiro(max, intervalo);
}

/// Dropdown de tabela só quando a forma está em modo tabela e o cliente
/// não tem tabela de prazo fixa.
bool podeEscolherTabelaPrazo({
  String? modoPrazo,
  required bool clienteTemTabelaFixa,
}) {
  if (clienteTemTabelaFixa) return false;
  return (modoPrazo ?? '').trim().toLowerCase() == 'tabela';
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}
