import 'package:absensi/nextpage.dart';
import 'package:absensi/splashscreen.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'homepage.dart';
import 'absensipage.dart';
import 'profilpage.dart';
import 'loginpage.dart';
import 'camera.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inisialisasi locale untuk tanggal Indonesia
  await initializeDateFormatting('id_ID', null);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Absensi Pegawai Furgetech',

      // HALAMAN PERTAMA
      initialRoute: '/splashscreen',

      routes: {
        '/splashscreen': (context) => const SplashScreen(),
        '/login': (context) => const LoginPage(),
        '/home': (context) => const HomePage(),
        '/absensi': (context) => const AbsensiPage(),
        '/next-page': (context) => const NextPage(),
        '/profil': (context) => const PegawaiPage(),
        '/camera': (context) => CameraPage(),

        
      },
    );
  }
}
