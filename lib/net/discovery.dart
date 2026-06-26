import 'dart:async';
import 'dart:io';

import '../api/api_client.dart';

/// Descoberta do servidor do ERP na rede local (LAN).
///
/// Varre as sub-redes privadas do aparelho batendo em `/ping` na porta padrão.
/// Retorna a primeira base URL que responder como servidor do ERP, ou null.
class ServerDiscovery {
  static const int defaultPort = 8765;

  /// Portas testadas na varredura: 8765 (instalação/produção) e 8000 (dev).
  static const List<int> defaultPorts = [8765, 8000];

  static Future<String?> find({
    List<int> ports = defaultPorts,
    void Function(int done, int total)? onProgress,
  }) async {
    final prefixes = await _localPrefixes();
    if (prefixes.isEmpty) return null;

    for (final prefix in prefixes) {
      for (final port in ports) {
        final found = await _scanSubnet(prefix, port, onProgress);
        if (found != null) return found;
      }
    }
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
    } catch (_) {}
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
    int port,
    void Function(int done, int total)? onProgress,
  ) async {
    const total = 254;
    const batchSize = 32;
    var done = 0;

    for (var start = 1; start <= total; start += batchSize) {
      final end = (start + batchSize - 1).clamp(1, total);
      final futures = <Future<String?>>[];

      for (var host = start; host <= end; host++) {
        final base = 'http://$prefix.$host:$port';
        futures.add(ApiClient.pingBase(base, timeout: const Duration(milliseconds: 700))
            .then((ok) => ok ? base : null));
      }

      final results = await Future.wait(futures);
      done += futures.length;
      onProgress?.call(done, total);

      for (final r in results) {
        if (r != null) return r;
      }
    }
    return null;
  }
}
