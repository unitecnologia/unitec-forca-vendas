import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pricing/product_preco.dart';
import 'brand.dart';
import 'format.dart';

/// Seleção obrigatória de Tab. Preço (Varejo / Atacado / Especial habilitados).
Future<TabPrecoOpcao?> showTabPrecoSheet(
  BuildContext context, {
  required String produtoNome,
  required List<TabPrecoOpcao> opcoes,
  int? preferidoPriceTableId,
}) {
  if (opcoes.isEmpty) return Future.value(null);

  var selected = 0;
  if (preferidoPriceTableId != null) {
    final idx = opcoes.indexWhere((o) => o.priceTableId == preferidoPriceTableId);
    if (idx >= 0) selected = idx;
  }

  return showModalBottomSheet<TabPrecoOpcao>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _TabPrecoSheet(
      produtoNome: produtoNome,
      opcoes: opcoes,
      selectedIndex: selected,
    ),
  );
}

class _TabPrecoSheet extends StatefulWidget {
  const _TabPrecoSheet({
    required this.produtoNome,
    required this.opcoes,
    required this.selectedIndex,
  });

  final String produtoNome;
  final List<TabPrecoOpcao> opcoes;
  final int selectedIndex;

  @override
  State<_TabPrecoSheet> createState() => _TabPrecoSheetState();
}

class _TabPrecoSheetState extends State<_TabPrecoSheet> {
  late int _index;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _index = widget.selectedIndex.clamp(0, widget.opcoes.length - 1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _confirmar() {
    Navigator.pop(context, widget.opcoes[_index]);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() => _index = (_index + 1).clamp(0, widget.opcoes.length - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() => _index = (_index - 1).clamp(0, widget.opcoes.length - 1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _confirmar();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Tabela de Preço',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16 + Brand.textBump01cm,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                Text(
                  widget.produtoNome,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Escolha a tabela para este produto (obrigatório).',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 12),
                ...List.generate(widget.opcoes.length, (i) {
                  final op = widget.opcoes[i];
                  final on = i == _index;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: on ? Brand.blue.withValues(alpha: 0.10) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() => _index = i),
                        onDoubleTap: () {
                          setState(() => _index = i);
                          _confirmar();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: on ? Brand.blue : const Color(0xFFE2E8F0),
                              width: on ? 1.6 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                alignment: Alignment.center,
                                child: Text(
                                  op.codigo,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: on ? Brand.blue : const Color(0xFF334155),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  op.descricao,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: on ? Brand.blue : const Color(0xFF1E293B),
                                  ),
                                ),
                              ),
                              Text(
                                brMoney(op.preco),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: on ? Brand.blue : const Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 4),
                FilledButton(
                  onPressed: _confirmar,
                  style: FilledButton.styleFrom(
                    backgroundColor: Brand.blue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Confirmar', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
