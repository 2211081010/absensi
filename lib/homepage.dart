import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String baseUrl = "http://10.28.223.39:8000/api";

  String? token;
  Map<String, dynamic>? pegawai;
  Map<String, dynamic>? statusAbsensi;

  String tanggal = "";
  String jam = "";

  bool loading = true;

  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    updateWaktu();
    Timer.periodic(const Duration(seconds: 1), (timer) => updateWaktu());
    loadData();
  }

  // Update jam dan tanggal realtime
  void updateWaktu() {
    final now = DateTime.now();
    tanggal = DateFormat("EEEE, dd MMMM yyyy", "id_ID").format(now);
    jam = DateFormat("HH:mm:ss").format(now);
    setState(() {});
  }

  // Bottom Navigation
  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;

    setState(() => _selectedIndex = index);

    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, '/home');
        break;
      case 1:
        Navigator.pushReplacementNamed(context, '/lokasi');
        break;
      case 2:
        Navigator.pushReplacementNamed(context, '/profil');
        break;
    }
  }

  // Load data awal
  Future<void> loadData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    token = prefs.getString('token');

    if (token == null) return;

    await fetchPegawai();
    await fetchTodayStatus();

    setState(() => loading = false);
  }

  // Get data pegawai
  Future<void> fetchPegawai() async {
    final response = await http.get(
      Uri.parse("$baseUrl/pegawai/me"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode == 200) {
      pegawai = jsonDecode(response.body)['data'];
    }
  }

  // Get status absensi hari ini
  Future<void> fetchTodayStatus() async {
    if (pegawai == null) return;

    final idPegawai = pegawai!['id'];

    final response = await http.get(
      Uri.parse("$baseUrl/absensi/today/$idPegawai"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode == 200) {
      statusAbsensi = jsonDecode(response.body);
    }
  }

  // POST absen masuk
  Future<void> absenMasuk() async {
    final response = await http.post(
      Uri.parse("$baseUrl/absensi/create"),
      headers: {"Authorization": "Bearer $token"},
      body: {"id_pegawai": pegawai!['id'].toString()},
    );

    if (response.statusCode == 200) {
      await fetchTodayStatus();
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Absen Masuk Berhasil")),
      );
    }
  }

  // POST absen pulang
  Future<void> absenPulang() async {
    final response = await http.post(
      Uri.parse("$baseUrl/absensi/pulang"),
      headers: {"Authorization": "Bearer $token"},
      body: {"id_pegawai": pegawai!['id'].toString()},
    );

    if (response.statusCode == 200) {
      await fetchTodayStatus();
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Absen Pulang Berhasil")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            header(),
            const SizedBox(height: 20),

            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    /// CARD ABSEN MASUK
                    buildAbsenCard(
                      title: "Absen Masuk",
                      img: "lib/assets/sebelum.png",
                      waktu: statusAbsensi?['jam_masuk'] ?? "-",
                      status: statusAbsensi?['status'] == "belum"
                          ? "Belum Absen"
                          : "Hadir",
                      onTap: () {
                        Navigator.pushNamed(context, '/absensi');
                      },
                    ),

                    const SizedBox(height: 20),

                    /// CARD ABSEN PULANG
                    buildAbsenCard(
                      title: "Absen Pulang",
                      img: "lib/assets/sebelum.png",
                      waktu: statusAbsensi?['jam_pulang'] ?? "-",
                      status: statusAbsensi?['status'] == "masuk"
                          ? "Belum Pulang"
                          : statusAbsensi?['status'] == "pulang"
                              ? "Hadir"
                              : "Belum Absen",
                      onTap: () {
                        Navigator.pushNamed(context, '/absensi');
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      // BOTTOM NAV BAR
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xff0078C8),
        unselectedItemColor: Colors.grey,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home, size: 30), label: "Home"),
          BottomNavigationBarItem(
              icon: Icon(Icons.location_on, size: 30), label: "Lokasi"),
          BottomNavigationBarItem(
              icon: Icon(Icons.person, size: 30), label: "Profil"),
        ],
      ),
    );
  }

  // HEADER
  Widget header() {
    return Container(
      height: 160,
      width: double.infinity,
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage("lib/assets/backround.jpg"),
          fit: BoxFit.cover,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            tanggal,
            style: const TextStyle(
              fontSize: 20,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            "$jam WIB",
            style: const TextStyle(
              fontSize: 26,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // CARD ABSEN
  Widget buildAbsenCard({
    required String title,
    required String img,
    required String waktu,
    required String status,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
          color: Colors.white,
        ),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                color: Color(0xff0078C8),
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(15),
                ),
              ),
              child: Text(
                title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(15),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      img,
                      width: 70,
                      height: 70,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 15),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Waktu",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(waktu == "-" ? "-" : "$waktu WIB"),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.assignment_turned_in, size: 18),
                          const SizedBox(width: 6),
                          Text(status),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
