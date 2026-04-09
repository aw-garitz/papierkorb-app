import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:file_picker/file_picker.dart';
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
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final bytes = await file.bytes;
        setState(() => _neuesFotoBytes = bytes);
      }
    } catch (e) {
      debugPrint("Fehler beim Bildauswahl: $e");
    }
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
    final isDesktop = MediaQuery.of(context).size.width > 1200;

    return Scaffold(
      appBar: AppBar(
        title: Text(
            'Papierkorb #${widget.papierkorb.nummer} - Stammdaten bearbeiten'),
        actions: [
          FilledButton.icon(
            onPressed: _speichert ? null : _speichern,
            icon: _speichert
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save),
            label: Text(_speichert ? 'Speichert...' : 'Speichern'),
          ),
          const SizedBox(width: 20),
        ],
      ),
      body: (_laedtStrassen || _laedtBauarten)
          ? const Center(child: CircularProgressIndicator())
          : isDesktop
              ? _buildDesktopLayout()
              : _buildMobileLayout(),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Linke Seite: Formular mit fester Breite
        SizedBox(
          width: 500,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 24),
                _buildFormular(),
                const SizedBox(height: 24),
                _buildActions(),
                const SizedBox(height: 16),
                // Abbrechen-Button unten links
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Abbrechen'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        // Rechte Seite: Karte + Foto + Zusatzinfos
        Expanded(
          child: Column(
            children: [
              // Oben: Karte + Foto nebeneinander (kleiner)
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    // Karte (verkleinert)
                    Expanded(
                      flex: 3,
                      child: Container(
                        margin: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(color: Colors.black12, blurRadius: 4),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _karte(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Foto rechts neben Karte
                    SizedBox(
                      width: 250,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Foto",
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 250),
                            child: AspectRatio(
                              aspectRatio: 3 / 4, // Hochformat
                              child: Stack(
                                children: [
                                  // Aktuelles Bild
                                  Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: Colors.grey.shade300),
                                    ),
                                    child: _neuesFotoBytes != null
                                        ? ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            child: Image.memory(
                                                _neuesFotoBytes!,
                                                fit: BoxFit.cover))
                                        : (widget.papierkorb.fotoUrl != null
                                            ? ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                child: CachedNetworkImage(
                                                    imageUrl: widget
                                                        .papierkorb.fotoUrl!,
                                                    fit: BoxFit.cover))
                                            : const Center(
                                                child: Icon(Icons.add_a_photo,
                                                    size: 40,
                                                    color: Colors.grey))),
                                  ),
                                  // Bearbeitungs-Buttons
                                  Positioned(
                                    bottom: 8,
                                    right: 8,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // Neues Foto
                                        Container(
                                          decoration: BoxDecoration(
                                            color: Colors.blue.withOpacity(0.9),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: IconButton(
                                            onPressed: _fotoWaehlen,
                                            icon: const Icon(Icons.folder_open,
                                                size: 16, color: Colors.white),
                                            tooltip:
                                                'Bild aus Ordner auswählen',
                                            constraints: const BoxConstraints(
                                                minWidth: 36, minHeight: 36),
                                            padding: const EdgeInsets.all(8),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        // Foto zurücksetzen (wenn neues ausgewählt)
                                        if (_neuesFotoBytes != null)
                                          Container(
                                            decoration: BoxDecoration(
                                              color: Colors.orange
                                                  .withOpacity(0.9),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: IconButton(
                                              onPressed: () {
                                                setState(() {
                                                  _neuesFotoBytes = null;
                                                });
                                              },
                                              icon: const Icon(Icons.refresh,
                                                  size: 16,
                                                  color: Colors.white),
                                              tooltip: 'Zurück zum Original',
                                              constraints: const BoxConstraints(
                                                  minWidth: 36, minHeight: 36),
                                              padding: const EdgeInsets.all(8),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Unten: Zusatzinfos + Historie (sofort sichtbar)
              Expanded(
                flex: 1,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Zusatzinfos
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Zusatzinformationen',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                  const SizedBox(height: 12),
                                  _buildInfoItem('Koordinaten',
                                      '${widget.papierkorb.lat}, ${widget.papierkorb.lng}'),
                                  _buildInfoItem(
                                      'Status', _status.toUpperCase()),
                                  _buildInfoItem('Bauart', _getBauartName()),
                                  _buildInfoItem('Straße',
                                      '${widget.papierkorb.strassenName ?? "-"} (ID: ${widget.papierkorb.strassenId ?? "-"})'),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Erstellt: ${_formatDatum(widget.papierkorb.erstelltAm)}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Historie
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Historie',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Historie wird implementiert...',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                fontStyle: FontStyle.italic,
                                              ),
                                        ),
                                        const SizedBox(height: 16),
                                        // Beispiel für zukünftige Historie-Einträge
                                        _buildHistorieEintrag(
                                          datum: DateTime.now().subtract(
                                              const Duration(days: 1)),
                                          typ: 'Leerung',
                                          bemerkung: 'Reguläre Leerung',
                                        ),
                                        _buildHistorieEintrag(
                                          datum: DateTime.now().subtract(
                                              const Duration(days: 7)),
                                          typ: 'Statusänderung',
                                          bemerkung:
                                              'Status auf "defekt" geändert',
                                        ),
                                        _buildHistorieEintrag(
                                          datum: DateTime.now().subtract(
                                              const Duration(days: 14)),
                                          typ: 'Leerung',
                                          bemerkung: 'Reguläre Leerung',
                                        ),
                                        _buildHistorieEintrag(
                                          datum: DateTime.now().subtract(
                                              const Duration(days: 30)),
                                          typ: 'Wartung',
                                          bemerkung: 'Reparatur durchgeführt',
                                        ),
                                        _buildHistorieEintrag(
                                          datum: DateTime.now().subtract(
                                              const Duration(days: 60)),
                                          typ: 'Leerung',
                                          bemerkung: 'Reguläre Leerung',
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          _buildFormular(),
          const SizedBox(height: 24),
          Container(
            height: 300,
            margin: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _karte(),
            ),
          ),
          _buildInfoPanel(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Papierkorb #${widget.papierkorb.nummer}',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.papierkorb.strassenName ?? "Unbekannte Straße"} ${widget.papierkorb.hausnummer ?? ""}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            if (widget.papierkorb.beschreibung != null &&
                widget.papierkorb.beschreibung!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  widget.papierkorb.beschreibung!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[500],
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormular() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Stammdaten',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            _formularFelder(),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _speichert ? null : _speichern,
            icon: _speichert
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save),
            label: Text(_speichert ? 'Speichert...' : 'Speichern'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(width: 12),
      ],
    );
  }

  Widget _buildInfoPanel() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Zusatzinformationen',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              _buildInfoItem('Koordinaten',
                  '${widget.papierkorb.lat}, ${widget.papierkorb.lng}'),
              _buildInfoItem('Status', _status.toUpperCase()),
              _buildInfoItem('Bauart', _getBauartName()),
              _buildInfoItem('Straße',
                  '${widget.papierkorb.strassenName ?? "-"} (ID: ${widget.papierkorb.strassenId ?? "-"})'),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                'Letzte Änderung',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Erstellt am: ${_formatDatum(widget.papierkorb.erstelltAm)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (widget.papierkorb.letzteLeerung != null)
                Text(
                  'Letzte Leerung: ${_formatDatum(widget.papierkorb.letzteLeerung!)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                'Historie',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Historie-Funktion wird implementiert...',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  String _getBauartName() {
    if (_bauartId == null || _bauarten.isEmpty) {
      return 'Nicht zugewiesen';
    }

    final bauart = _bauarten.firstWhere(
      (b) => b['id'].toString() == _bauartId,
      orElse: () => {'beschreibung': 'Unbekannte Bauart'},
    );

    return bauart['beschreibung'] as String? ?? 'Unbekannte Bauart';
  }

  Widget _buildHistorieEintrag({
    required DateTime datum,
    required String typ,
    required String bemerkung,
  }) {
    Color typColor;
    IconData typIcon;

    switch (typ.toLowerCase()) {
      case 'leerung':
        typColor = Colors.green;
        typIcon = Icons.delete_outline;
        break;
      case 'statusänderung':
        typColor = Colors.orange;
        typIcon = Icons.edit_note;
        break;
      case 'wartung':
        typColor = Colors.blue;
        typIcon = Icons.build;
        break;
      default:
        typColor = Colors.grey;
        typIcon = Icons.info_outline;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: typColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(typIcon, size: 16, color: typColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      typ,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: typColor,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _formatDatum(datum),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                            fontSize: 11,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  bemerkung,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDatum(DateTime datum) {
    return '${datum.day.toString().padLeft(2, '0')}.${datum.month.toString().padLeft(2, '0')}.${datum.year} ${datum.hour.toString().padLeft(2, '0')}:${datum.minute.toString().padLeft(2, '0')}';
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
            DropdownMenuItem(value: 'ok', child: Text('OK (In Betrieb)')),
            DropdownMenuItem(
                value: 'defekt', child: Text('Defekt (Reparatur nötig)')),
            DropdownMenuItem(
                value: 'schmutzig', child: Text('Schmutzig (Reinigung nötig)')),
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
}
