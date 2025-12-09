import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class EditProfilPage extends StatefulWidget {
  final Map<String, dynamic> data;

  const EditProfilPage({super.key, required this.data});

  @override
  State<EditProfilPage> createState() => _EditProfilPageState();
}

class _EditProfilPageState extends State<EditProfilPage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController namaC;
  late TextEditingController contactC;
  late TextEditingController alamatC;

  final TextEditingController oldPasswordC = TextEditingController();
  final TextEditingController newPasswordC = TextEditingController();
  final TextEditingController confirmPasswordC = TextEditingController();

  File? fotoFile;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    namaC = TextEditingController(text: widget.data['nama']);
    contactC = TextEditingController(text: widget.data['contact']);
    alamatC = TextEditingController(text: widget.data['alamat']);
  }

  Future<void> pilihFoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => fotoFile = File(picked.path));
    }
  }

  // 🔹 Update profil & password
  Future<void> updateProfil() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => loading = true);
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString('token');

    var uri = Uri.parse("http://192.168.1.12:8000/api/pegawai/update");

    var request = http.MultipartRequest("POST", uri);
    request.headers['Authorization'] = "Bearer $token";
    request.fields['nama'] = namaC.text;
    request.fields['contact'] = contactC.text;
    request.fields['alamat'] = alamatC.text;

    if (oldPasswordC.text.isNotEmpty && newPasswordC.text.isNotEmpty) {
      request.fields['old_password'] = oldPasswordC.text;
      request.fields['password'] = newPasswordC.text;
      request.fields['password_confirmation'] = confirmPasswordC.text;
    }

    var response = await request.send();
    var respStr = await response.stream.bytesToString();
    var data = jsonDecode(respStr);

    setState(() => loading = false);

    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profil berhasil diperbarui!")),
      );

      // Jika foto diubah, upload foto secara terpisah
      if (fotoFile != null) await updateFoto(token!);

      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data['message'] ?? "Gagal update")),
      );
    }
  }

  // 🔹 Update foto pegawai
  Future<void> updateFoto(String token) async {
    if (fotoFile == null) return;

    var uri = Uri.parse("http://192.168.1.12:8000/api/pegawai/update-foto");
    var request = http.MultipartRequest("POST", uri);
    request.headers['Authorization'] = "Bearer $token";
    request.files.add(await http.MultipartFile.fromPath('foto', fotoFile!.path));

    var response = await request.send();
    var respStr = await response.stream.bytesToString();
    var data = jsonDecode(respStr);

    if (response.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Foto profil berhasil diperbarui")),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data['message'] ?? "Gagal upload foto")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Profil"),
        backgroundColor: Colors.blue,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // FOTO
                    Center(
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 60,
                            backgroundImage: fotoFile != null
                                ? FileImage(fotoFile!)
                                : NetworkImage(
                                    widget.data['foto_url'] ??
                                        "http://192.168.1.12:8000/storage/foto_pegawai/default_user.jpg",
                                  ) as ImageProvider,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: InkWell(
                              onTap: pilihFoto,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(
                                    color: Colors.blue, shape: BoxShape.circle),
                                child: const Icon(Icons.edit, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // NAMA
                    TextFormField(
                      controller: namaC,
                      decoration: const InputDecoration(
                        labelText: "Nama",
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v!.isEmpty ? "Nama wajib diisi" : null,
                    ),

                    const SizedBox(height: 15),

                    // CONTACT
                    TextFormField(
                      controller: contactC,
                      decoration: const InputDecoration(
                        labelText: "Contact",
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v!.isEmpty ? "Contact wajib diisi" : null,
                    ),

                    const SizedBox(height: 15),

                    // ALAMAT
                    TextFormField(
                      controller: alamatC,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: "Alamat",
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v!.isEmpty ? "Alamat wajib diisi" : null,
                    ),

                    const SizedBox(height: 20),
                    const Text(
                      "Ganti Password (Opsional)",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),

                    // PASSWORD LAMA
                    TextFormField(
                      controller: oldPasswordC,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: "Password Lama",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 15),

                    // PASSWORD BARU
                    TextFormField(
                      controller: newPasswordC,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: "Password Baru",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 15),

                    // KONFIRMASI PASSWORD
                    TextFormField(
                      controller: confirmPasswordC,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: "Konfirmasi Password Baru",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 25),

                    // BUTTON SAVE
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: updateProfil,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          "SIMPAN PERUBAHAN",
                          style: TextStyle(fontSize: 17),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
