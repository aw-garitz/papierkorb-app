import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/papierkorb.dart';
import '../../models/leerung.dart';
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
  String _status = 'ok';

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

  // Leerungshistorie
  List<Leerung> _leerungen = [];
  bool _laedtLeerungen = true;

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
    _ladeLeerungen();
  }

  @override
  void dispose() {
    _hausnummerCtrl.dispose();
    _beschreibungCtrl.dispose();
    _strassenSuchCtrl.dispose();
    super.dispose();
  }

  Future<void> _ladeDaten() async {
    try {
      final res = await Future.wait([_service.strassen(), _service.bauarten()]);
      setState(() {
        _allStrassen = res[0];
        _strassenListe = _allStrassen;
        _bauarten = res[1];
        _laedtStrassen = false;
        _laedtBauarten = false;
      });
    } catch (e) {
      debugPrint('Fehler Stammdaten: $e');
    }
  }

  Future<void> _ladeLeerungen() async {
    try {
      final liste =
          await _service.leerungenFuer(widget.papierkorb.id, limit: 30);
      setState(() {
        _leerungen = liste;
        _laedtLeerungen = false;
      });
    } catch (_) {
      setState(() => _laedtLeerungen = false);
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
        final bytes = result.files.first.bytes;
        if (bytes != null) setState(() => _neuesFotoBytes = bytes);
      }
    } catch (e) {
      debugPrint('Fehler Bildauswahl: $e');
    }
  }

  Future<void> _speichern() async {
    if (_strassenId == null) return;
    setState(() => _speichert = true);
    try {
      await _service.aktualisieren(
        id: widget.papierkorb.id,
        strassenId: _strassenId!,
        hausnummer: _hausnummerCtrl.text.trim().isEmpty
            ? null
            : _hausnummerCtrl.text.trim(),
        beschreibung: _beschreibungCtrl.text.trim().isEmpty
            ? null
            : _beschreibungCtrl.text.trim(),
        bauartId: _bauartId,
        lat: _lat,
        lng: _lng,
        status: _status,
        neuesFotoBytes: _neuesFotoBytes,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _speichert = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Fehler: $e')));
    }
  }

  String _formatDatum(DateTime datum) {
    return '${datum.day.toString().padLeft(2, '0')}.'
        '${datum.month.toString().padLeft(2, '0')}.'
        '${datum.year}';
  }

  String _getBauartName() {
    if (_bauartId == null || _bauarten.isEmpty) return 'Nicht zugewiesen';
    final bauart = _bauarten.firstWhere(
      (b) => b['id'].toString() == _bauartId,
      orElse: () => {'beschreibung': 'Unbekannte Bauart'},
    );
    return bauart['beschreibung'] as String? ?? 'Unbekannte Bauart';
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 1200;

    return Scaffold(
      appBar: AppBar(
        title: Text(
            'Papierkorb #${widget.papierkorb.nummer} – Stammdaten bearbeiten'),
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

  // ----------------------------------------------------------
  // DESKTOP LAYOUT
  // ----------------------------------------------------------
  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // LINKS: Formular
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

        // RECHTS: Karte + Foto + Info + Historie
        Expanded(
          child: Column(
            children: [
              // OBEN: Karte + Foto
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    // Karte
                    Expanded(
                      flex: 3,
                      child: Container(
                        margin: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(color: Colors.black12, blurRadius: 4)
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _karte(),
                        ),
                      ),
                    ),
                    // Foto
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                      child: SizedBox(
                        width: 220,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Foto',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Expanded(
                              child: Stack(
                                children: [
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
                                        : widget.papierkorb.fotoUrl != null
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
                                                    color: Colors.grey)),
                                  ),
                                  Positioned.fill(
                                    child: GestureDetector(
                                      onTap: () {
                                        if (_neuesFotoBytes != null)
                                          _showPhotoDialog(
                                              _neuesFotoBytes!, 'Neues Foto');
                                        else if (widget.papierkorb.fotoUrl !=
                                            null)
                                          _showPhotoDialog(
                                              null, widget.papierkorb.fotoUrl!);
                                      },
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 8,
                                    right: 8,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _fotoButton(
                                            color: Colors.blue,
                                            icon: Icons.folder_open,
                                            tooltip: 'Bild auswählen',
                                            onPressed: _fotoWaehlen),
                                        if (_neuesFotoBytes != null) ...[
                                          const SizedBox(width: 4),
                                          _fotoButton(
                                              color: Colors.orange,
                                              icon: Icons.refresh,
                                              tooltip: 'Zurück zum Original',
                                              onPressed: () => setState(() =>
                                                  _neuesFotoBytes = null)),
                                        ],
                                      ],
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

              // UNTEN: Info + Historie
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Zusatzinfos
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Zusatzinformationen',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                            fontWeight: FontWeight.bold)),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: Column(
                                      children: [
                                        _infoZeile('Koordinaten',
                                            '${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}'),
                                        _infoZeile(
                                            'Status', _status.toUpperCase()),
                                        _infoZeile('Bauart', _getBauartName()),
                                        _infoZeile(
                                            'Straße',
                                            widget.papierkorb.strassenName ??
                                                '—'),
                                        _infoZeile(
                                            'Erstellt',
                                            _formatDatum(
                                                widget.papierkorb.erstelltAm)),
                                        if (widget.papierkorb.letzteLeerung !=
                                            null)
                                          _infoZeile(
                                              'Letzte Leerung',
                                              _formatDatum(widget
                                                  .papierkorb.letzteLeerung!)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Historie
                      Expanded(
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Leerungshistorie',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                            fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: _laedtLeerungen
                                      ? const Center(
                                          child: CircularProgressIndicator())
                                      : _leerungen.isEmpty
                                          ? Text('Noch keine Leerungen erfasst',
                                              style: TextStyle(
                                                  color: Colors.grey.shade500,
                                                  fontStyle: FontStyle.italic))
                                          : ListView.separated(
                                              itemCount: _leerungen.length,
                                              separatorBuilder: (_, __) =>
                                                  const Divider(height: 8),
                                              itemBuilder: (_, i) =>
                                                  _leerungZeile(_leerungen[i]),
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

  // ----------------------------------------------------------
  // MOBIL LAYOUT
  // ----------------------------------------------------------
  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          _buildFormular(),
          const SizedBox(height: 16),
          Container(
            height: 300,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 4)
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _karte(),
            ),
          ),
          const SizedBox(height: 16),
          _buildActions(),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Info',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        _infoZeile('Status', _status),
                        _infoZeile('Bauart', _getBauartName()),
                        _infoZeile('Erstellt',
                            _formatDatum(widget.papierkorb.erstelltAm)),
                        if (widget.papierkorb.letzteLeerung != null)
                          _infoZeile('Letzte Leerung',
                              _formatDatum(widget.papierkorb.letzteLeerung!)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Leerungshistorie',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        _laedtLeerungen
                            ? const Center(child: CircularProgressIndicator())
                            : _leerungen.isEmpty
                                ? Text('Keine Leerungen',
                                    style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 12))
                                : Column(
                                    children: _leerungen
                                        .take(5)
                                        .map(_leerungZeile)
                                        .toList()),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // LEERUNGS-ZEILE
  // ----------------------------------------------------------
  Widget _leerungZeile(Leerung l) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.delete_outline,
            size: 16,
            color: l.twice ? Colors.orange : Colors.green.shade600,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _formatDatum(l.geleertAm.toLocal()),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    if (l.twice) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('2×',
                            style: TextStyle(
                                fontSize: 10, color: Colors.orange.shade800)),
                      ),
                    ],
                    if (l.befuellung != null) ...[
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Text(
                          l.befuellung!,
                          style: TextStyle(
                              fontSize: 11, color: Colors.blue.shade700),
                        ),
                      ),
                    ],
                  ],
                ),
                if (l.bemerkung != null)
                  Text(
                    l.bemerkung!,
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // HILFS-WIDGETS
  // ----------------------------------------------------------
  Widget _buildHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Papierkorb #${widget.papierkorb.nummer}',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              '${widget.papierkorb.strassenName ?? "Unbekannte Straße"} '
              '${widget.papierkorb.hausnummer ?? ""}',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Colors.grey[600]),
            ),
            if (widget.papierkorb.beschreibung != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  widget.papierkorb.beschreibung!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[500], fontStyle: FontStyle.italic),
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
            Text('Stammdaten',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _strassenSucheBox(),
            const SizedBox(height: 16),
            TextField(
              controller: _hausnummerCtrl,
              decoration: const InputDecoration(
                  labelText: 'Hausnummer', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _bauartId,
              decoration: const InputDecoration(
                  labelText: 'Bauart', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(
                    value: null, child: Text('— keine Angabe —')),
                ..._bauarten.map((b) => DropdownMenuItem(
                    value: b['id'].toString(),
                    child: Text(b['beschreibung'] as String))),
              ],
              onChanged: (v) => setState(() => _bauartId = v),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _beschreibungCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Beschreibung / Notiz',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _status,
              decoration: const InputDecoration(
                  labelText: 'Status', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'ok', child: Text('OK')),
                DropdownMenuItem(value: 'defekt', child: Text('Defekt')),
                DropdownMenuItem(value: 'schmutzig', child: Text('Schmutzig')),
              ],
              onChanged: (v) => setState(() => _status = v!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    return SizedBox(
      width: double.infinity,
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
            padding: const EdgeInsets.symmetric(vertical: 16)),
      ),
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
            decoration: InputDecoration(
              hintText: 'Straße suchen...',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: _strassenSuchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _strassenSuchCtrl.clear();
                        _strassenFiltern();
                      },
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 150,
            child: ListView.builder(
              itemCount: _strassenListe.length,
              itemBuilder: (_, i) {
                final s = _strassenListe[i];
                final sel = s['id'] == _strassenId;
                return ListTile(
                  dense: true,
                  title: Text(s['name'] as String,
                      style: TextStyle(
                          fontWeight:
                              sel ? FontWeight.bold : FontWeight.normal)),
                  selected: sel,
                  selectedTileColor: Colors.green.shade50,
                  trailing: sel
                      ? Icon(Icons.check,
                          color: Colors.green.shade600, size: 18)
                      : null,
                  onTap: () => setState(() => _strassenId = s['id'] as int),
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
        onTap: (_, punkt) => setState(() {
          _lat = punkt.latitude;
          _lng = punkt.longitude;
        }),
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
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'de.stadt.papierkorb_app',
          ),
        ),
        MarkerLayer(markers: [
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
                    color: Colors.black54, blurRadius: 6, offset: Offset(2, 2))
              ],
            ),
          ),
        ]),
      ],
    );
  }

  // ----------------------------------------------------------
  // FOTO-DIALOG FÜR GROẞANZEIGT
  // ----------------------------------------------------------
  void _showPhotoDialog(Uint8List? bytes, String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          height: MediaQuery.of(context).size.height * 0.9,
          child: Stack(
            children: [
              // Schließen-Button
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withOpacity(0.5),
                  ),
                ),
              ),
              // Foto in voller Größe mit Web-kompatiblem Zoom
              Center(
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 4.0,
                  boundaryMargin: const EdgeInsets.all(20),
                  child: bytes != null
                      ? Image.memory(bytes, fit: BoxFit.contain)
                      : CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.contain,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fotoButton({
    required Color color,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 16, color: Colors.white),
        tooltip: tooltip,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        padding: const EdgeInsets.all(8),
      ),
    );
  }

  Widget _infoZeile(String label, String wert) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text('$label:',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Text(wert, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
