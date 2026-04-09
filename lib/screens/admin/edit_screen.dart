import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/papierkorb.dart';
import '../../services/papierkorb_service.dart';

class EditScreen extends StatefulWidget {
  final Papierkorb papierkorb;

  const EditScreen({super.key, required this.papierkorb});

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  final _service = PapierkorbService();
  final _mapController = MapController();

  int? _strassenId;
  String? _bauartId;
  final _hausnummerCtrl = TextEditingController();
  final _beschreibungCtrl = TextEditingController();
  String _status = 'aktiv';

  Uint8List? _neuesFotoBytes;
  late double _lat;
  late double _lng;

  List<Map<String, dynamic>> _allStrassen = [];
  List<Map<String, dynamic>> _strassenListe = [];
  final _strassenSuchCtrl = TextEditingController();
  List<Map<String, dynamic>> _bauarten = [];

  bool _laedtStrassen = true;
  bool _laedtBauarten = true;
  bool _speichert = false;

  @override
  void initState() {
    super.initState();
    final pk = widget.papierkorb;
    _strassenId = pk.strassenId;
    _bauartId = pk.bauartId;
    _hausnummerCtrl.text = pk.hausnummer ?? '';
    _beschreibungCtrl.text = pk.beschreibung ?? '';
    _status = pk.status;
    _lat = pk.lat;
    _lng = pk.lng;
    _strassenSuchCtrl.addListener(_strassenFiltern);
    _ladeDaten();
  }

  Future<void> _ladeDaten() async {
    try {
      final res = await Future.wait([_service.strassen(), _service.bauarten()]);
      setState(() {
        _allStrassen = res[0] as List<Map<String, dynamic>>;
        _strassenListe = _allStrassen;
        _bauarten = res[1] as List<Map<String, dynamic>>;
        _laedtStrassen = false;
        _laedtBauarten = false;
      });
    } catch (e) {
      debugPrint("Fehler Stammdaten: $e");
    }
  }

  void _strassenFiltern() {
    final suche = _strassenSuchCtrl.text.toLowerCase();
    setState(() {
      _strassenListe = suche.isEmpty
          ? _allStrassen
          : _allStrassen
              .where((s) => (s['name'] as String).toLowerCase().contains(suche))
              .toList();
    });
  }

  Future<void> _fotoWaehlen() async {
    final picker = ImagePicker();
    final bild =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (bild == null) return;
    final bytes = await bild.readAsBytes();
    setState(() => _neuesFotoBytes = bytes);
  }

  Future<void> _speichern() async {
    if (_strassenId == null) return;
    setState(() => _speichert = true);
    try {
      await _service.aktualisieren(
        id: widget.papierkorb.id,
        strassenId: _strassenId!,
        hausnummer: _hausnummerCtrl.text.trim(),
        beschreibung: _beschreibungCtrl.text.trim(),
        bauartId: _bauartId,
        lat: _lat,
        lng: _lng,
        status: _status,
        neuesFotoBytes: _neuesFotoBytes,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _speichert = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
            'Papierkorb #${widget.papierkorb.nummer} - Stammdaten bearbeiten'),
        actions: [
          FilledButton.icon(
            onPressed: _speichert ? null : _speichern,
            icon: const Icon(Icons.save),
            label: Text(_speichert ? 'Speichert...' : 'Speichern'),
          ),
          const SizedBox(width: 20),
        ],
      ),
      body: (_laedtStrassen || _laedtBauarten)
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                // Linke Seite: Formular
                SizedBox(
                  width: 450,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fotoBereich(),
                        const SizedBox(height: 24),
                        _formularFelder(),
                      ],
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                // Rechte Seite: Karte (nimmt den Rest des Platzes ein)
                Expanded(
                  child: Stack(
                    children: [
                      _karte(),
                      _kartenInfo(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _fotoBereich() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Foto", style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        InkWell(
          onTap: _fotoWaehlen,
          child: Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: _neuesFotoBytes != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(_neuesFotoBytes!, fit: BoxFit.cover))
                : (widget.papierkorb.fotoUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                            imageUrl: widget.papierkorb.fotoUrl!,
                            fit: BoxFit.cover))
                    : const Center(
                        child: Icon(Icons.add_a_photo,
                            size: 40, color: Colors.grey))),
          ),
        ),
      ],
    );
  }

  Widget _formularFelder() {
    return Column(
      children: [
        _strassenSucheBox(),
        const SizedBox(height: 16),
        TextField(
            controller: _hausnummerCtrl,
            decoration: const InputDecoration(
                labelText: 'Hausnummer', border: OutlineInputBorder())),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _bauartId,
          decoration: const InputDecoration(
              labelText: 'Bauart', border: OutlineInputBorder()),
          items: _bauarten
              .map((b) => DropdownMenuItem(
                  value: b['id'].toString(), child: Text(b['beschreibung'])))
              .toList(),
          onChanged: (v) => setState(() => _bauartId = v),
        ),
        const SizedBox(height: 16),
        TextField(
            controller: _beschreibungCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'Beschreibung / Notiz',
                border: OutlineInputBorder())),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _status,
          decoration: const InputDecoration(
              labelText: 'Verwaltungs-Status', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'aktiv', child: Text('Aktiv (In Betrieb)')),
            DropdownMenuItem(
                value: 'defekt', child: Text('Defekt (Reparatur nötig)')),
            DropdownMenuItem(
                value: 'archiviert', child: Text('Archiviert (Abgebaut)')),
          ],
          onChanged: (v) => setState(() => _status = v!),
        ),
      ],
    );
  }

  Widget _strassenSucheBox() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          TextField(
            controller: _strassenSuchCtrl,
            decoration: const InputDecoration(
                hintText: 'Straße suchen...',
                prefixIcon: Icon(Icons.search),
                isDense: true),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 150,
            child: ListView.builder(
              itemCount: _strassenListe.length,
              itemBuilder: (context, i) {
                final s = _strassenListe[i];
                final sel = s['id'] == _strassenId;
                return ListTile(
                  title: Text(s['name'],
                      style: TextStyle(
                          fontWeight:
                              sel ? FontWeight.bold : FontWeight.normal)),
                  selected: sel,
                  onTap: () => setState(() => _strassenId = s['id']),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _karte() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: LatLng(_lat, _lng),
        initialZoom: 18,
        onTap: (tapPos, point) => setState(() {
          _lat = point.latitude;
          _lng = point.longitude;
        }),
      ),
      children: [
        TileLayer(
            urlTemplate:
                'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'),
        Opacity(
          opacity: 0.7,
          child: TileLayer(
              urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/light_only_labels/{z}/{x}/{y}{r}.png'),
        ),
        MarkerLayer(markers: [
          Marker(
              point: LatLng(_lat, _lng),
              width: 50,
              height: 50,
              child:
                  const Icon(Icons.location_on, color: Colors.red, size: 50)),
        ]),
      ],
    );
  }

  Widget _kartenInfo() {
    return Positioned(
      top: 10,
      right: 10,
      child: Container(
        padding: const EdgeInsets.all(8),
        color: Colors.black87,
        child: Text("${_lat.toStringAsFixed(6)}, ${_lng.toStringAsFixed(6)}",
            style: const TextStyle(color: Colors.white, fontSize: 12)),
      ),
    );
  }
}
