import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Thay 2 hằng số này bằng giá trị từ tài khoản Cloudinary của nhóm.
/// Cloud name: Dashboard → Cloud name
/// Upload preset: Settings → Upload → Upload presets (Signing mode: Unsigned)
const _cloudName = 'h4woanl7';
const _uploadPreset = 'splitpay_qr';

/// Upload [imageFile] lên Cloudinary (unsigned).
/// Trả về URL public của ảnh, hoặc throw Exception nếu thất bại.
Future<String> uploadToCloudinary(File imageFile) async {
  final uri = Uri.parse(
    'https://api.cloudinary.com/v1_1/$_cloudName/image/upload',
  );

  final request = http.MultipartRequest('POST', uri)
    ..fields['upload_preset'] = _uploadPreset
    ..files.add(await http.MultipartFile.fromPath('file', imageFile.path));

  final response = await request.send();

  if (response.statusCode != 200) {
    throw Exception('Upload thất bại: HTTP ${response.statusCode}');
  }

  final body = await response.stream.bytesToString();
  final json = jsonDecode(body) as Map<String, dynamic>;
  return json['secure_url'] as String;
}
