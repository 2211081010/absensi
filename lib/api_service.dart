import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = "http://10.0.2.2:8000/api"; // Ganti sesuai alamat API kamu

  // Login
  static Future<Map<String, dynamic>> login(String username, String password) async {
    final url = Uri.parse('$baseUrl/login');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Login gagal');
    }
  }

  // Contoh ambil list akun
  static Future<List<dynamic>> getAccounts(String token) async {
    final url = Uri.parse('$baseUrl/accounts'); // Sesuaikan route di Laravel
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['data'];
    } else {
      throw Exception('Gagal mengambil data akun');
    }
  }

  // Tambah akun
  static Future<void> addAccount(String token, Map<String, dynamic> userData) async {
    final url = Uri.parse('$baseUrl/accounts');
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(userData),
    );

    if (response.statusCode != 200) {
      throw Exception('Gagal menambah akun');
    }
  }

  // Reset password
  static Future<void> resetPassword(String token, int userId) async {
    final url = Uri.parse('$baseUrl/accounts/reset-password/$userId');
    final response = await http.put(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Gagal reset password');
    }
  }
}