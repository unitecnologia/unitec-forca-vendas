import 'package:flutter_test/flutter_test.dart';
import 'package:unitec_forca_vendas/update/app_updater.dart';

Map<String, dynamic> _release({
  String tag = 'v1.4.29',
  String body = '- Versão: 1.4.29 (versionCode 81)',
  bool comSha = true,
}) {
  final apk = 'unitec-forca-vendas-${tag.substring(1)}.apk';
  return {
    'tag_name': tag,
    'draft': false,
    'prerelease': false,
    'body': body,
    'assets': [
      {'name': apk, 'size': 1000, 'browser_download_url': 'https://x/$apk'},
      if (comSha) {'name': '$apk.sha256', 'size': 90, 'browser_download_url': 'https://x/$apk.sha256'},
    ],
  };
}

void main() {
  test('lê versão, versionCode e assets da Release', () {
    final r = AppUpdater.parseRelease(_release())!;
    expect(r.versionName, '1.4.29');
    expect(r.versionCode, 81);
    expect(r.apkName, 'unitec-forca-vendas-1.4.29.apk');
    expect(r.sha256Url, 'https://x/unitec-forca-vendas-1.4.29.apk.sha256');
  });

  test('Release sem .sha256 não é oferecida', () {
    expect(AppUpdater.parseRelease(_release(comSha: false)), isNull);
  });

  test('versionCode manda na comparação', () {
    final r = AppUpdater.parseRelease(_release())!;
    expect(AppUpdater.ehMaisNova(r, build: 80, versao: '1.4.28'), isTrue);
    expect(AppUpdater.ehMaisNova(r, build: 81, versao: '1.4.28'), isFalse);
    expect(AppUpdater.ehMaisNova(r, build: 90, versao: '1.5.0'), isFalse);
  });

  test('sem versionCode compara o nome da versão', () {
    final r = AppUpdater.parseRelease(_release(tag: 'v1.4.17', body: 'build antigo'))!;
    expect(r.versionCode, isNull);
    expect(AppUpdater.ehMaisNova(r, build: 80, versao: '1.4.28'), isFalse);
    expect(AppUpdater.compararVersao('1.4.30', '1.4.28'), greaterThan(0));
    expect(AppUpdater.compararVersao('1.10.0', '1.9.9'), greaterThan(0));
  });
}
