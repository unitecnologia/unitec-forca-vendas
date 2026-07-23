import 'package:flutter/material.dart';

import 'brand.dart';
import 'phone_formatter.dart';
import 'uppercase_input.dart';

enum PedidoEnvioCanal { whatsapp, email }

class PedidoEnvioResult {
  const PedidoEnvioResult({
    required this.canal,
    required this.whatsapp,
    required this.email,
    required this.mensagem,
  });

  final PedidoEnvioCanal canal;
  final String whatsapp;
  final String email;
  final String mensagem;
}

/// Modal pós-salvar: envia PDF por WhatsApp e/ou e-mail (mesmo fluxo do ERP).
Future<PedidoEnvioResult?> showPedidoEnvioDialog(
  BuildContext context, {
  required String tipoLabel,
  required String clienteNome,
  required String whatsappInicial,
  required String emailInicial,
  required String mensagemInicial,
}) {
  return showDialog<PedidoEnvioResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _PedidoEnvioDialog(
      tipoLabel: tipoLabel,
      clienteNome: clienteNome,
      whatsappInicial: whatsappInicial,
      emailInicial: emailInicial,
      mensagemInicial: mensagemInicial,
    ),
  );
}

class _PedidoEnvioDialog extends StatefulWidget {
  const _PedidoEnvioDialog({
    required this.tipoLabel,
    required this.clienteNome,
    required this.whatsappInicial,
    required this.emailInicial,
    required this.mensagemInicial,
  });

  final String tipoLabel;
  final String clienteNome;
  final String whatsappInicial;
  final String emailInicial;
  final String mensagemInicial;

  @override
  State<_PedidoEnvioDialog> createState() => _PedidoEnvioDialogState();
}

class _PedidoEnvioDialogState extends State<_PedidoEnvioDialog> {
  late final TextEditingController _whats;
  late final TextEditingController _email;
  late final TextEditingController _msg;

  @override
  void initState() {
    super.initState();
    _whats = TextEditingController(text: BrPhoneInputFormatter.format(widget.whatsappInicial));
    _email = TextEditingController(text: widget.emailInicial);
    _msg = TextEditingController(text: widget.mensagemInicial);
  }

  @override
  void dispose() {
    _whats.dispose();
    _email.dispose();
    _msg.dispose();
    super.dispose();
  }

  void _enviar(PedidoEnvioCanal canal) {
    final whats = _whats.text.trim();
    final email = _email.text.trim();
    final msg = _msg.text.trim();

    if (canal == PedidoEnvioCanal.whatsapp) {
      if (!BrPhoneInputFormatter.isValid(whats)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe um WhatsApp válido, ex.: (47)99644-9859')),
        );
        return;
      }
    } else {
      if (email.isEmpty || !email.contains('@')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe um e-mail válido.')),
        );
        return;
      }
    }

    if (msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe a mensagem.')),
      );
      return;
    }

    Navigator.of(context).pop(PedidoEnvioResult(
      canal: canal,
      whatsapp: whats,
      email: email,
      mensagem: msg,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      title: Row(
        children: [
          Expanded(
            child: Text(
              'Enviar ${widget.tipoLabel}?',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Brand.textPrimary),
            ),
          ),
          IconButton(
            tooltip: 'Não enviar',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 20),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.clienteNome,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
            ),
            const SizedBox(height: 4),
            const Text(
              'Deseja enviar o PDF ao cliente? Você pode alterar o número ou o e-mail.',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B), height: 1.35),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _whats,
              keyboardType: TextInputType.phone,
              inputFormatters: const [BrPhoneInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'WhatsApp',
                hintText: '(47)99644-9859',
                prefixIcon: Icon(Icons.chat_outlined, color: Brand.green),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'E-mail',
                hintText: 'cliente@email.com',
                prefixIcon: Icon(Icons.email_outlined, color: Brand.blue),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _msg,
              maxLines: 2,
              maxLength: 500,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: withUpperCase(),
              decoration: const InputDecoration(
                labelText: 'Mensagem',
                isDense: true,
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Na próxima tela, escolha WhatsApp ou e-mail para enviar o PDF.',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _enviar(PedidoEnvioCanal.email),
                    icon: const Icon(Icons.email_outlined, size: 18),
                    label: const Text('E-mail'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Brand.green),
                    onPressed: () => _enviar(PedidoEnvioCanal.whatsapp),
                    icon: const Icon(Icons.chat, size: 18),
                    label: const Text('WhatsApp'),
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Não enviar'),
            ),
          ],
        ),
      ),
      actions: const [],
    );
  }
}
