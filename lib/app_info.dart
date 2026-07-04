/// Informações de versão do aplicativo (ponto único de controle).
///
/// Mantenha em sincronia com a linha `version:` do pubspec.yaml.
/// `kAppVersion` é exibida nas telas e enviada ao ERP (registro/login)
/// para facilitar o controle de qual build está em cada aparelho.
const String kAppName = 'Unitec Força de Vendas';
const String kAppVersion = '1.3.7';
const int kAppBuild = 14;

/// Texto pronto para exibição (ex.: "v1.1.0 (2)").
const String kAppVersionLabel = 'v$kAppVersion ($kAppBuild)';
