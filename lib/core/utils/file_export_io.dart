import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<String> saveAndShareBytes({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) async {
  final dir = await getTemporaryDirectory();
  final filePath = p.join(dir.path, fileName);
  final file = File(filePath);
  await file.writeAsBytes(bytes, flush: true);
  try {
    await Share.shareXFiles([XFile(filePath, mimeType: mimeType)]);
  } catch (_) {}
  return filePath;
}
