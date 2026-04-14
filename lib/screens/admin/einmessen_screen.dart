import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/papierkorb_service.dart';

class EinmessenScreen extends StatefulWidget {
  const EinmessenScreen({super.key});

  @override
  State<EinmessenScreen> createState() => _EinmessenScreenState();
}

class _EinmessenScreenState extends State<EinmessenScreen> {
  final _service = PapierkorbService();
  final _formKey = GlobalKey<FormState>();

  int? _nummer;
  int? _strassenId;
  String? _bauartId;
  final _hausnummerCtrl = TextEditingController();
  final _beschreibungCtrl = TextEditingController();
  double? _lat;
  double? _lng;

  File? _foto;
  Uint8List? _fotoBytes;

  bool _laedt = false;
  bool _laedtStrassen = true;
  bool _laedtBauarten = true;
  bool _gpsLaedt = false;

  List<Map<String, dynamic>> _allStrassen = [];
  List<Map<String, dynamic>> _strassenListe = [];
  final _strassenSuchCtrl = TextEditingController();

  List<Map<String, dynamic>> _bauarten = [];

  @override
  void initState() {
    super.initState();
    _ladeStrassen();
    _ladeBauarten();
    _strassenSuchCtrl.addListener(_strassenFiltern);
    _generiereNummer();
  }

  @override
  void dispose() {
    _hausnummerCtrl.dispose();
    _beschreibungCtrl.dispose();
    _strassenSuchCtrl.dispose();
    super.dispose();
  }

  Future<void> _ladeStrassen() async {
    try {
      final liste = await _service.strassen();
      // Sortieren nach Straßennamen A-Z
      liste
          .sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));
      setState(() {
        _allStrassen = liste;
        _strassenListe = liste;
        _laedtStrassen = false;
      });
    } catch (_) {
      setState(() => _laedtStrassen = false);
    }
  }

  Future<void> _ladeBauarten() async {
    try {
      final liste = await _service.bauarten();
      setState(() {
        _bauarten = liste;
        _laedtBauarten = false;
      });
    } catch (_) {
      setState(() => _laedtBauarten = false);
    }
  }

  void _strassenFiltern() {
    final suche = _strassenSuchCtrl.text.toLowerCase();
    setState(() {
      if (suche.isEmpty) {
        _strassenListe = _allStrassen;
      } else {
        _strassenListe = _allStrassen
            .where((s) => (s['name'] as String).toLowerCase().contains(suche))
            .toList();
        // Gefilterte Liste auch sortieren A-Z
        _strassenListe.sort(
            (a, b) => (a['name'] as String).compareTo(b['name'] as String));
      }
    });
  }

  Future<void> _generiereNummer() async {
    try {
      final papierkoerbe = await _service.alleAktiven();
      final maxNummer = papierkoerbe.isEmpty
          ? 0
          : papierkoerbe.map((pk) => pk.nummer).reduce((a, b) => a > b ? a : b);

      setState(() {
        _nummer = maxNummer + 1;
      });
    } catch (e) {
      setState(() {
        _nummer = 1;
      });
    }
  }

  Future<void> _fotoAufnehmen() async {
    final picker = ImagePicker();
    final bild = await picker.pickImage(
      source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
      imageQuality: 55,
    );
    if (bild != null) {
      final bytes = await bild.readAsBytes();
      setState(() {
        _fotoBytes = bytes;
        _foto = kIsWeb ? null : File(bild.path);
      });
    }
  }

  void _formularLeeren() {
    _formKey.currentState?.reset();
    _hausnummerCtrl.clear();
    _beschreibungCtrl.clear();
    _strassenSuchCtrl.clear();
    setState(() {
      _foto = null;
      _fotoBytes = null;
      _lat = null;
      _lng = null;
      _strassenId = null;
      _bauartId = null;
    });
    _generiereNummer();
  }

  Future<bool> _standortErmitteln() async {
    setState(() => _gpsLaedt = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 8),
      );

      setState(() {
        _lat = position.latitude;
        _lng = position.longitude;
      });
      return true;
    } catch (e) {
      return false;
    } finally {
      setState(() => _gpsLaedt = false);
    }
  }

  Future<void> _speichern() async {
    if (_nummer == null || _strassenId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Nummer und Straße prüfen!')),
      );
      return;
    }

    // --- HIER IST DIE GEÄNDERTE LOGIK ---
    if (!kIsWeb) {
      // NUR AUF MOBILE: GPS zwingend abfragen
      bool gpsErfolgreich = await _standortErmitteln();

      if (!gpsErfolgreich) {
        if (!mounted) return;
        bool trotzdem = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Kein GPS'),
                content: const Text(
                    'Trotzdem speichern und später im Büro verorten?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Abbrechen')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Speichern')),
                ],
              ),
            ) ??
            false;

        if (!trotzdem) return;
        _lat ??= 50.2007;
        _lng ??= 10.0760;
      }
    } else {
      // WEB: GPS wird ignoriert, wir setzen direkt Standardwerte
      _lat ??= 50.2007;
      _lng ??= 10.0760;
    }
    // --- ENDE DER ÄNDERUNG ---

    setState(() => _laedt = true);

    try {
      await _service.anlegen(
        nummer: _nummer!,
        strassenId: _strassenId!,
        hausnummer: _hausnummerCtrl.text.trim(),
        beschreibung: _beschreibungCtrl.text.trim(),
        bauartId: _bauartId,
        lat: _lat!,
        lng: _lng!,
        foto: _foto,
        fotoBytes: _fotoBytes,
      );

      _formularLeeren();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Gespeichert!'), backgroundColor: Colors.green));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fehler: $e')));
    } finally {
      setState(() => _laedt = false);
    }
    // Nach dem Speichern:
    Navigator.pop(
        context, true); // Das 'true' signalisiert: "Es wurde etwas hinzugefügt"
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Papierkorb einmessen')),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _schrittHeader('1', 'Nächste Nummer', _nummer != null),
                  const SizedBox(height: 12),
                  _buildNummerAnzeige(),
                  const SizedBox(height: 24),
                  _schrittHeader('2', 'Straße auswählen', _strassenId != null),
                  const SizedBox(height: 12),
                  if (_laedtStrassen)
                    const LinearProgressIndicator()
                  else
                    _strassenAuswahl(),
                  const SizedBox(height: 24),
                  _schrittHeader('3', 'Details & Bauart', false),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _hausnummerCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Hausnummer', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _beschreibungCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Beschreibung',
                        hintText: 'z.B. Neben dem roten Haus',
                        border: OutlineInputBorder()),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  _laedtBauarten
                      ? const LinearProgressIndicator()
                      : DropdownButtonFormField<String>(
                          value: _bauartId,
                          decoration: const InputDecoration(
                              labelText: 'Bauart',
                              border: OutlineInputBorder()),
                          items: _bauarten
                              .map((b) => DropdownMenuItem<String>(
                                    value: b['id'].toString(),
                                    child: Text(b['beschreibung']),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _bauartId = v),
                        ),
                  const SizedBox(height: 24),
                  _schrittHeader('4', 'Foto', _fotoBytes != null),
                  const SizedBox(height: 12),
                  _buildFotoBereich(),
                  const SizedBox(height: 32),
                  _buildSpeichernButton(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
          if (_gpsLaedt) _buildGpsOverlay(),
        ],
      ),
    );
  }

  Widget _buildNummerAnzeige() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade300),
      ),
      child: Row(
        children: [
          Text(
            _nummer != null
                ? 'pk_${_nummer.toString().padLeft(4, '0')}'
                : 'Lädt...',
            style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.green.shade800),
          ),
          const Spacer(),
          const Icon(Icons.auto_awesome, color: Colors.green),
        ],
      ),
    );
  }

  Widget _strassenAuswahl() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
            color: _strassenId != null ? Colors.green : Colors.grey.shade400,
            width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: _strassenSuchCtrl,
              decoration: const InputDecoration(
                hintText: 'Straße suchen...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          // Anzeige der aktuell gewählten Straße als "Feedback-Header"
          if (_strassenId != null)
            Container(
              width: double.infinity,
              color: Colors.green.shade100,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Text(
                "Ausgewählt: ${_allStrassen.firstWhere((s) => s['id'] == _strassenId)['name']}",
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Colors.green),
              ),
            ),
          SizedBox(
            height: 180,
            child: ListView.builder(
              itemCount: _strassenListe.length,
              itemBuilder: (_, i) {
                final s = _strassenListe[i];
                final istSelektiert = _strassenId == s['id'];
                return ListTile(
                  tileColor: istSelektiert ? Colors.green.shade50 : null,
                  title: Text(s['name'],
                      style: TextStyle(
                          fontWeight: istSelektiert
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: istSelektiert ? Colors.green.shade900 : null)),
                  subtitle: Text(s['stadtteil'] ?? ''),
                  trailing: istSelektiert
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : null,
                  onTap: () {
                    setState(() {
                      _strassenId = s['id'];
                    });
                    // Verstecke Tastatur nach Auswahl
                    FocusScope.of(context).unfocus();
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFotoBereich() {
    return GestureDetector(
      onTap: _fotoAufnehmen,
      child: Container(
        height: 150,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: _fotoBytes != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(_fotoBytes!, fit: BoxFit.cover))
            : const Center(
                child: Icon(Icons.camera_alt, size: 40, color: Colors.grey)),
      ),
    );
  }

  Widget _buildSpeichernButton() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton.icon(
        onPressed: _laedt ? null : _speichern,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green.shade700,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: _laedt
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.save),
        label: const Text('PAPIERKORB SPEICHERN',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildGpsOverlay() {
    return Container(
      color: Colors.black54,
      child: const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('GPS wird ermittelt...'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _schrittHeader(String nr, String titel, bool erledigt) {
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: erledigt ? Colors.green : Colors.grey.shade400,
          child: Text(nr,
              style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
        const SizedBox(width: 10),
        Text(titel,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
