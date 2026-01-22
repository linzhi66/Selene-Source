import 'dart:io'
    show HttpOverrides, SecurityContext, X509Certificate, HttpClient;

// 全局禁用证书校验
class CustomizeHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;
    return client;
  }
}
