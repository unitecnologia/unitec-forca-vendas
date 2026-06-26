import 'dart:async';
import 'dart:io';

import '../api/api_client.dart';
import '../log/app_log.dart';

/// Descoberta do servidor do ERP na rede local (LAN).
///
/// Estratégia: para cada IP da sub-rede do aparelho, faz primeiro um teste
/// TCP leve (`Socket.connect` com timeout, fechando o socket na hora) e só
/// confirma via HTTP `/ping` nos endereços que tiverem a porta aberta.
/// Isso evita acumular conexões HTTP penduradas (causa de falsos "não achou").
class ServerDiscovery {
  static const int defaultPort = 8765;

  /// Portas testadas na varredura: 8765 (instalação/produção) e 8000 (dev).
  static const List<int> defaultPorts = [8765, 8000];

  /// Quantos IPs sondados em paralelo por lote (menor = menos congestão Wi-Fi).
  static const int batchSize = 16;

  static Future<String?> find({
    List<int> ports = defaultPorts,
    void Function(int done, int total)? onProgress,
  }) async {
    final prefixes = await _localPrefixes();
    if (prefixes.isEmpty) {
      AppLog.instance.warn('rede', 'Nenhuma sub-rede privada detectada no aparelho.');
      return null;
    }

    AppLog.instance.info('rede',
        'Varredura: sub-redes ${prefixes.map((p) => '$p.x').join(', ')} nas portas ${ports.join('/')}');

    for (final prefix in prefixes) {
      final found = await _scanSubnet(prefix, ports, onProgress);
      if (found != null) {
        AppLog.instance.ok('rede', 'Servidor encontrado: $found');
        return found;
      }
    }

    AppLog.instance.warn('rede', 'Varredura concluída: nenhum servidor respondeu.');
    return null;
  }

  /// Octetos iniciais (ex.: "192.168.0") das interfaces IPv4 privadas.
  static Future<List<String>> _localPrefixes() async {
    final prefixes = <String>{};
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (_isPrivateIpv4(ip)) {
            final parts = ip.split('.');
            if (parts.length == 4) {
              prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
            }
          }
        }
      }
    } catch (e) {
      AppLog.instance.error('rede', 'Falha ao listar interfaces: $e');
    }
    return prefixes.toList();
  }

  static bool _isPrivateIpv4(String ip) {
    if (ip.startsWith('192.168.')) return true;
    if (ip.startsWith('10.')) return true;
    final m = RegExp(r'^172\.(\d+)\.').firstMatch(ip);
    if (m != null) {
      final second = int.tryParse(m.group(1) ?? '') ?? 0;
      return second >= 16 && second <= 31;
    }
    return false;
  }

  static Future<String?> _scanSubnet(
    String prefix,
    List<int> ports,
    void Function(int done, int total)? onProgress,
  ) async {
    const total = 254;
    var done = 0;

    for (var start = 1; start <= total; start += batchSize) {
      final end = (start + batchSize - 1).clamp(1, total);
      final futures = <Future<String?>>[];

      for (var host = start; host <= end; host++) {
        futures.add(_probeHost('$prefix.$host', ports));
      }

      final results = await Future.wait(futures);
      done += (end - start + 1);
      onProgress?.call(done, total);

      for (final r in results) {
        if (r != null) return r;
      }
    }
    return null;
  }

  /// Testa as portas de um IP: TCP primeiro (rápido), HTTP só se a porta abrir.
  static Future<String?> _probeHost(String ip, List<int> ports) async {
    for (final port in ports) {
      final aberto = await _tcpOpen(ip, port, const Duration(milliseconds: 600));
      if (!aberto) continue;
      final base = 'http://$ip:$port';
      final ok = await ApiClient.pingBase(base, timeout: const Duration(seconds: 2));
      if (ok) return base;
    }
    return null;
  }

  /// Conecta via TCP e fecha imediatamente. Retorna true se a porta aceitou.
  static Future<bool> _tcpOpen(String ip, int port, Duration timeout) async {
    Socket? socket;
    try {
      socket = await Socket.connect(ip, port, timeout: timeout);
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }
}
