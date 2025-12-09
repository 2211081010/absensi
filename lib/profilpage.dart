import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'loginpage.dart';
import 'editprofilpage.dart';

class PegawaiPage extends StatefulWidget {
  const PegawaiPage({super.key});

  @override
  State<PegawaiPage> createState() => _PegawaiPageState();
}

class _PegawaiPageState extends State<PegawaiPage> {
  Map<String, dynamic>? pegawai;
  bool loading = true;
  String? errorMessage;

  int _selectedIndex = 2;

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);

    switch (index) {
      case 0:
        Navigator.pushNamed(context, '/home');
        break;
      case 1:
        Navigator.pushNamed(context, '/lokasi');
        break;
      case 2:
        break;
    }
  }

  Future<void> getPegawai() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');

      if (token == null) {
        setState(() {
          loading = false;
          errorMessage = 'Token tidak ditemukan. Silakan login kembali.';
        });
        return;
      }

      final response = await http.get(
        Uri.parse("http://192.168.1.12:8000/api/pegawai/by-user"),
        headers: {
          "Accept": "application/json",
          "Authorization": "Bearer $token",
        },
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        setState(() {
          pegawai = data['data'];
          loading = false;
        });
      } else {
        setState(() {
          loading = false;
          errorMessage = data['message'] ?? 'Terjadi kesalahan';
        });
      }
    } catch (e) {
      setState(() {
        loading = false;
        errorMessage = 'Terjadi kesalahan koneksi: $e';
      });
    }
  }

  Future<void> logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  @override
  void initState() {
    super.initState();
    getPegawai();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(
                  child: Text(
                    errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                )
              : Stack(
                  children: [
                    Container(
                      height: 250,
                      decoration: const BoxDecoration(
                        image: DecorationImage(
                          image: AssetImage('lib/assets/backround2.png'),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    SingleChildScrollView(
                      child: Column(
                        children: [
                          const SizedBox(height: 160),

                          // FOTO PROFIL
                          Center(
                            child: Container(
                              width: 140,
                              height: 140,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 4),
                                image: DecorationImage(
                                  image: NetworkImage(
                                    pegawai!['foto'] != null && pegawai!['foto'] != ''
                                        ? 'http://192.168.1.12:8000/storage/${pegawai!['foto']}'
                                        : 'http://192.168.1.12:8000/storage/default_user.jpg',
                                  ),
                                  fit: BoxFit.cover,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  )
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // NAMA
                          Text(
                            pegawai!['nama'] ?? '-',
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),

                          const SizedBox(height: 6),

                          // NIP
                          Text(
                            "NIP: ${pegawai!['nip'] ?? '-'}",
                            style: const TextStyle(
                              fontSize: 17,
                              color: Colors.black54,
                            ),
                          ),

                          const SizedBox(height: 20),

                          // CARD DETAIL
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Card(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              elevation: 6,
                              child: Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.phone, color: Colors.blue),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            pegawai!['contact'] ?? "-",
                                            style: const TextStyle(fontSize: 16),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 15),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Icon(Icons.location_on, color: Colors.blue),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            pegawai!['alamat'] ?? "-",
                                            style: const TextStyle(fontSize: 16),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 30),

                          // TOMBOL SEJAJAR (EDIT KIRI, LOGOUT KANAN)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              children: [
                                // EDIT PROFIL
                                Expanded(
                                  child: SizedBox(
                                    height: 50,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(30),
                                        ),
                                      ),
                                      onPressed: () async {
                                        await Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => EditProfilPage(data: pegawai!),
                                          ),
                                        );
                                        getPegawai(); // refresh setelah edit
                                      },
                                      child: const Text(
                                        "EDIT PROFIL",
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 15),
                                // LOGOUT
                                Expanded(
                                  child: SizedBox(
                                    height: 50,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(30),
                                        ),
                                      ),
                                      onPressed: logout,
                                      child: const Text(
                                        "LOGOUT",
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ],
                ),

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: const Color(0xff0078C8),
        unselectedItemColor: Colors.grey,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home, size: 30), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.location_on, size: 30), label: 'Lokasi'),
          BottomNavigationBarItem(icon: Icon(Icons.person, size: 30), label: 'Profil'),
        ],
      ),
    );
  }
}
