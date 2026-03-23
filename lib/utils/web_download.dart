// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

void downloadDatei(Uint8List bytes, String dateiname) {
  final blob = html.Blob(
    [bytes],
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  );
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', dateiname)
    ..click();
  html.Url.revokeObjectUrl(url);
}