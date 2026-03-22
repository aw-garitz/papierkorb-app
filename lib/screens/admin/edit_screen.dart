import 'dart:io';
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

  File? _neuesFoto;
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
    _ladeStrassen();
    _ladeBauarten();
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
      _strassenListe = suche.isEmpty
          ? _allStrassen
          : _allStrassen
              .where((s) =>
                  (s['name'] as String).toLowerCase().contains(suche))
              .toList();
    });
  }

  Future<void> _fotoErsetzen() async {
    final picker = ImagePicker();
    final bild = await picker.pickImage(
      source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
      imageQuality: 90,
    );
    if (bild == null) return;
    final bytes = await bild.readAsBytes();
    setState(() {
      _neuesFotoBytes = bytes;
      _neuesFoto = kIsWeb ? null : File(bild.path);
    });
  }

  Future<void> _speichern() async {
    if (_strassenId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Bitte eine Straße auswählen'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _speichert = true);

    try {
      final aktualisiert = await _service.aktualisieren(
        id:             widget.papierkorb.id,
        qrCode:         widget.papierkorb.qrCode,
        strassenId:     _strassenId!,
        hausnummer:     _hausnummerCtrl.text.trim().isEmpty
                            ? null : _hausnummerCtrl.text.trim(),
        beschreibung:   _beschreibungCtrl.text.trim().isEmpty
                            ? null : _beschreibungCtrl.text.trim(),
        bauartId:       _bauartId,
        lat:            _lat,
        lng:            _lng,
        status:         _status,
        neuesFoto:      _neuesFoto,
        neuesFotoBytes: _neuesFotoBytes,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Gespeichert ✓'),
            backgroundColor: Colors.green),
      );
      Navigator.pop(context, aktualisiert);
    } catch (e) {
      setState(() => _speichert = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Fehler: $e'),
            backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.papierkorb.qrCode} bearbeiten'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen',
                style: TextStyle(color: Colors.red)),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _speichert ? null : _speichern,
            style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade700),
            icon: _speichert
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.save, size: 18),
            label: Text(_speichert ? 'Speichert...' : 'Speichern'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: (_laedtStrassen || _laedtBauarten)
          ? const Center(child: CircularProgressIndicator())
          : kIsWeb
              ? _webLayout()
              : _mobilLayout(),
    );
  }

  Widget _webLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 420,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: _formular(),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Stack(
            children: [
              _karte(),
              Positioned(
                top: 12, left: 0, right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Auf Karte tippen um Marker zu verschieben',
                      style: TextStyle(
                          color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 12, left: 0, right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_lat.toStringAsFixed(6)}, ${_lng.toStringAsFixed(6)}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _mobilLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _formular(),
          const SizedBox(height: 24),
          Text('Position',
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Container(
            height: 300,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  _karte(),
                  Positioned(
                    top: 8, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Text('Tippen zum Verschieben',
                            style: TextStyle(
                                color: Colors.white, fontSize: 12)),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8, left: 0, right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _speichert ? null : _speichern,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: _speichert
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(
                _speichert ? 'Wird gespeichert...' : 'Speichern',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),
          const SizedBox(height: 24),
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
        onTap: (_, punkt) {
          setState(() {
            _lat = punkt.latitude;
            _lng = punkt.longitude;
          });
        },
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
          userAgentPackageName: 'de.stadt.papierkorb_app',
        ),
        Opacity(
          opacity: 0.4,
          child: TileLayer(
            urlTemplate:
                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'de.stadt.papierkorb_app',
          ),
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: LatLng(_lat, _lng),
              width: 48,
              height: 48,
              child: const Icon(
                Icons.location_pin,
                color: Colors.orange,
                size: 48,
                shadows: [
                  Shadow(
                    color: Colors.black54,
                    blurRadius: 6,
                    offset: Offset(2, 2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _formular() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        _fotoBereich(),
        const SizedBox(height: 20),

        Text('Straße *',
            style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        _strassenAuswahl(),
        const SizedBox(height: 16),

        TextFormField(
          controller: _hausnummerCtrl,
          decoration: const InputDecoration(
            labelText: 'Hausnummer',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.home_outlined),
          ),
        ),
        const SizedBox(height: 16),

        TextFormField(
          controller: _beschreibungCtrl,
          decoration: const InputDecoration(
            labelText: 'Beschreibung',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.notes),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 16),

        // Bauart
        DropdownButtonFormField<String>(
          value: _bauartId,
          decoration: const InputDecoration(
            labelText: 'Bauart (optional)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.delete_outline),
          ),
          items: [
            const DropdownMenuItem(
              value: null,
              child: Text('— keine Angabe —'),
            ),
            ..._bauarten.map((b) => DropdownMenuItem<String>(
                  value: b['id'] as String,
                  child: Text(b['beschreibung'] as String),
                )),
          ],
          onChanged: (v) => setState(() => _bauartId = v),
        ),
        const SizedBox(height: 16),

        DropdownButtonFormField<String>(
          initialValue: _status,
          decoration: const InputDecoration(
            labelText: 'Status',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.info_outline),
          ),
          items: const [
            DropdownMenuItem(value: 'aktiv', child: Text('Aktiv')),
            DropdownMenuItem(value: 'defekt', child: Text('Defekt')),
            DropdownMenuItem(
                value: 'entfernt', child: Text('Entfernt')),
          ],
          onChanged: (v) => setState(() => _status = v!),
        ),
      ],
    );
  }

  Widget _fotoBereich() {
    Widget vorschau;

    if (_neuesFotoBytes != null) {
      vorschau = Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(_neuesFotoBytes!, fit: BoxFit.cover),
          ),
          Positioned(
            top: 8, right: 8,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.refresh,
                  color: Colors.white, size: 18),
            ),
          ),
        ],
      );
    } else if (widget.papierkorb.fotoUrl != null) {
      vorschau = Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: widget.papierkorb.fotoUrl!,
              fit: BoxFit.cover,
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(kIsWeb ? Icons.upload_file : Icons.camera_alt,
                      color: Colors.white, size: 28),
                  const SizedBox(height: 4),
                  Text(
                    kIsWeb ? 'Datei auswählen' : 'Foto ersetzen',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      );
    } else {
      vorschau = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(kIsWeb ? Icons.upload_file : Icons.camera_alt,
              size: 32, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text(kIsWeb ? 'Datei auswählen' : 'Foto aufnehmen',
              style: TextStyle(color: Colors.grey.shade500)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Foto',
            style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _fotoErsetzen,
          child: Container(
            height: 160,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: vorschau,
          ),
        ),
      ],
    );
  }

  Widget _strassenAuswahl() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: _strassenSuchCtrl,
              decoration: InputDecoration(
                hintText: 'Straße suchen...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _strassenSuchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _strassenSuchCtrl.clear();
                          _strassenFiltern();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                isDense: true,
              ),
            ),
          ),
          if (_strassenId != null && _allStrassen.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle,
                      color: Colors.green.shade600, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _allStrassen.firstWhere(
                          (s) => s['id'] == _strassenId,
                          orElse: () => {'name': ''})['name']
                          as String,
                      style: TextStyle(
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _strassenId = null),
                    style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(40, 24)),
                    child: const Text('Ändern',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          SizedBox(
            height: 180,
            child: _strassenListe.isEmpty
                ? Center(
                    child: Text('Keine Treffer',
                        style: TextStyle(
                            color: Colors.grey.shade500)))
                : ListView.builder(
                    itemCount: _strassenListe.length,
                    itemBuilder: (_, i) {
                      final s = _strassenListe[i];
                      final istAusgewaehlt = s['id'] == _strassenId;
                      return ListTile(
                        dense: true,
                        selected: istAusgewaehlt,
                        selectedTileColor: Colors.green.shade50,
                        title: Text(s['name'] as String),
                        subtitle: s['stadtteil'] != null
                            ? Text(s['stadtteil'] as String,
                                style:
                                    const TextStyle(fontSize: 11))
                            : null,
                        trailing: istAusgewaehlt
                            ? Icon(Icons.check,
                                color: Colors.green.shade600,
                                size: 18)
                            : null,
                        onTap: () => setState(
                            () => _strassenId = s['id'] as int),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}