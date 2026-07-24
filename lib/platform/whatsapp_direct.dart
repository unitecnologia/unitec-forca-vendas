import 'dart:io';

import 'package:flutter/services.dart';

/// Envio direto de PDF ao chat do WhatsApp (Android).
///
/// Usa Intent ACTION_SEND com package WhatsApp + extra `jid`.
/// Em iOS / falha → o caller deve cair no Share sheet.
class WhatsAppDirect {
  static const _channel = MethodChannel('com.unitec.forca_vendas/whatsapp');

  static bool get isAndroid => Platform.isAndroid;

  static Future<bool> isAvailable() async {
    if (!isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('isAvailable');
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  /// Abre o chat do número (cria a conversa se ainda não existir).
  static Future<bool> openChat({
    required String phoneE164,
    String text = '',
  }) async {
    if (!isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('openChat', {
        'phone': phoneE164,
        'text': text,
      });
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  /// Envia o PDF direto ao WhatsApp, preferindo o chat do [phoneE164].
  static Future<bool> sharePdf({
    required String phoneE164,
    required String filePath,
    String text = '',
  }) async {
    if (!isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('sharePdf', {
        'phone': phoneE164,
        'path': filePath,
        'text': text,
      });
      return ok == true;
    } catch (_) {
      return false;
    }
  }
}
