import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'pdv_alert_dialog.dart';

/// Coordenadas obtidas do GPS do aparelho.
class GpsPosicao {
  const GpsPosicao(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

/// GPS obrigatório na finalização de pedido / visita.
///
/// Retorna a posição ou `null` se o vendedor não puder fornecer
/// (serviço off, permissão negada ou falha na leitura).
class GpsObrigatorio {
  GpsObrigatorio._();

  /// Coordenada de fallback só em debug no emulador (sem satélite).
  static const _emuFallback = GpsPosicao(-23.5505, -46.6333);

  static LocationSettings _settings({
    required Duration timeLimit,
    LocationAccuracy accuracy = LocationAccuracy.high,
    bool forceLocationManager = false,
  }) {
    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: 0,
        forceLocationManager: forceLocationManager,
        timeLimit: timeLimit,
      );
    }
    return LocationSettings(
      accuracy: accuracy,
      timeLimit: timeLimit,
    );
  }

  static Future<bool> _ehEmuladorAndroid() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return !info.isPhysicalDevice;
    } catch (_) {
      return false;
    }
  }

  static Future<Position?> _tentarAtual({
    required LocationAccuracy accuracy,
    required bool forceLocationManager,
    required Duration timeLimit,
  }) async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: _settings(
          accuracy: accuracy,
          forceLocationManager: forceLocationManager,
          timeLimit: timeLimit,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Tenta posição atual; em aparelho real faz retries. Emulador (debug) não espera minutos.
  static Future<Position?> _lerPosicao({required bool emulador}) async {
    if (emulador) {
      // Uma tentativa curta; se falhar, o caller usa fallback de debug.
      return _tentarAtual(
        accuracy: LocationAccuracy.low,
        forceLocationManager: true,
        timeLimit: const Duration(seconds: 4),
      );
    }

    // Aparelho real: fused → LocationManager → última conhecida.
    var pos = await _tentarAtual(
      accuracy: LocationAccuracy.medium,
      forceLocationManager: false,
      timeLimit: const Duration(seconds: 12),
    );
    if (pos != null) return pos;

    pos = await _tentarAtual(
      accuracy: LocationAccuracy.high,
      forceLocationManager: true,
      timeLimit: const Duration(seconds: 12),
    );
    if (pos != null) return pos;

    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }

  /// Exige localização ativa + permissão + posição.
  /// [finalidade] entra na mensagem (ex.: "finalizar o pedido").
  static Future<GpsPosicao?> obter(
    BuildContext context, {
    required String finalidade,
  }) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (!context.mounted) return null;
      final abrir = await PdvAlertDialog.showSimNao(
        context,
        titulo: 'LOCALIZAÇÃO DESLIGADA',
        detalhe:
            'Ative a localização do aparelho para $finalidade.',
        hint: 'Sem GPS não é possível registrar a visita no cliente.',
        confirmLabel: 'ABRIR CONFIGURAÇÕES',
        cancelLabel: 'CANCELAR',
      );
      if (abrir) {
        await Geolocator.openLocationSettings();
      }
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      if (!context.mounted) return null;
      await PdvAlertDialog.showOk(
        context,
        titulo: 'PERMISSÃO NECESSÁRIA',
        detalhe:
            'Permita o acesso à localização para $finalidade.',
      );
      return null;
    }

    if (permission == LocationPermission.deniedForever) {
      if (!context.mounted) return null;
      final abrir = await PdvAlertDialog.showSimNao(
        context,
        titulo: 'PERMISSÃO BLOQUEADA',
        detalhe:
            'A localização está bloqueada para o app. Libere nas configurações para $finalidade.',
        confirmLabel: 'ABRIR CONFIGURAÇÕES',
        cancelLabel: 'CANCELAR',
      );
      if (abrir) {
        await Geolocator.openAppSettings();
      }
      return null;
    }

    final emulador = kDebugMode && await _ehEmuladorAndroid();
    final pos = await _lerPosicao(emulador: emulador);
    if (pos != null) {
      return GpsPosicao(pos.latitude, pos.longitude);
    }

    // Emulador sem fix de GPS: em debug permite testar o fluxo de gravação.
    if (emulador) {
      return _emuFallback;
    }

    if (!context.mounted) return null;
    await PdvAlertDialog.showOk(
      context,
      titulo: 'GPS INDISPONÍVEL',
      detalhe:
          'Não foi possível obter a localização. Verifique se a localização está ligada e tente novamente para $finalidade.',
    );
    return null;
  }

  /// Coleta silenciosa: só retorna lat/lng se já estiver liberado.
  /// Usado em orçamento (GPS opcional).
  static Future<(double?, double?)> coletarOpcional() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return (null, null);
      }
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        return (null, null);
      }
      final emulador = kDebugMode && await _ehEmuladorAndroid();
      final pos = await _lerPosicao(emulador: emulador);
      if (pos != null) {
        return (pos.latitude, pos.longitude);
      }
      if (emulador) {
        return (_emuFallback.latitude, _emuFallback.longitude);
      }
      return (null, null);
    } catch (_) {
      return (null, null);
    }
  }
}
