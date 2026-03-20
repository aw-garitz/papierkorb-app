import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../models/papierkorb.dart';
import '../../models/leerung.dart';
import '../../services/papierkorb_service.dart';

class DetailScreen extends StatefulWidget {
  final Papierkorb papierkorb;
  final bool readonly;

  const DetailScreen({
    super.key,
    required this.papierkorb,
    this.readonly = false,
  });

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final _service = PapierkorbService();

  // Leerungen
  List<Leerung> _leerungen = [];
  bool _laedtLeerungen = true;

  // Leerung bestätigen
  bool _speichert = false;
  bool _erfolgreich = false;

  // Edit-Modus
  bool _editModus = false;
  bool _speichertEdit = false;

  // Edit-Felder
  int? _editStrassenId;
  final _editHausnummerCtrl = TextEditingController();
  final _editBeschreibungCtrl = TextEditingController();
  final _editLatCtrl = TextEditingController();
  final _editLngCtrl = TextEditingController();
  String _editStatus = 'aktiv';
  File? _editNeuesFoto;

  // Straßenliste für Edit
  List<Map<String, dynamic>> _allStrassen = [];
  List<Map<String, dynamic>> _strassenListe = [];
  final _strassenSuchCtrl = TextEditingController();
  bool _laedtStrassen = false;

  @override
  void initState() {
    super.initState();
    _ladeLeerungen();
    _strassenSuchCtrl.addListener(_strassenFiltern);
  }

  @override
  void dispose() {
    _editHausnummerCtrl.dispose();
    _editBeschreibungCtrl.dispose();
    _editLatCtrl.dispose();
    _editLngCtrl.dispose();
    _strassenSuchCtrl.dispose();
    super.dispose();
  }

  Future<void> _ladeLeerungen() async {
    try {
      final leerungen = await _service.leerungenFuer(widget.papierkorb.id);
      setState(() {
        _leerungen = leerungen;
        _laedtLeerungen = false;
      });
    } catch (_) {
      setState(() => _laedtLeerungen = false);
    }
  }

  Future<void> _ladeStrassen() async {
    if (_allStrassen.isNotEmpty) return;
    setState(() => _laedtStrassen = true);
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

  void _startEdit() async {
    await _ladeStrassen();
    final pk = widget.papierkorb;
    setState(() {
      _editModus = true;
      _editStrassenId = pk.strassenId;
      _editHausnummerCtrl.text = pk.hausnummer ?? '';
      _editBeschreibungCtrl.text = pk.beschreibung ?? '';
      _editLatCtrl.text = pk.lat.toStringAsFixed(6);
      _editLngCtrl.text = pk.lng.toStringAsFixed(6);
      _editStatus = pk.status;
      _editNeuesFoto = null;
    });
  }

  void _abbrechenEdit() {
    setState(() {
      _editModus = false;
      _editNeuesFoto = null;
      _strassenSuchCtrl.clear();
    });
  }

  Future<void> _fotoErsetzen() async {
    final picker = ImagePicker();
    final bild = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (bild == null) return;
    setState(() => _editNeuesFoto = File(bild.path));
  }

  Future<void> _speichernEdit() async {
    if (_editStrassenId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte eine Straße auswählen'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final lat = double.tryParse(_editLatCtrl.text.replaceAll(',', '.'));
    final lng = double.tryParse(_editLngCtrl.text.replaceAll(',', '.'));

    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ungültige GPS-Koordinaten'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _speichertEdit = true);

    try {
      final aktualisiert = await _service.aktualisieren(
        id:          widget.papierkorb.id,
        qrCode:      widget.papierkorb.qrCode,
        strassenId:  _editStrassenId!,
        hausnummer:  _editHausnummerCtrl.text.trim().isEmpty
                         ? null : _editHausnummerCtrl.text.trim(),
        beschreibung: _editBeschreibungCtrl.text.trim().isEmpty
                         ? null : _editBeschreibungCtrl.text.trim(),
        lat:         lat,
        lng:         lng,
        status:      _editStatus,
        neuesFoto:   _editNeuesFoto,
      );

      setState(() {
        _speichertEdit = false;
        _editModus = false;
        _editNeuesFoto = null;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gespeichert ✓'),
          backgroundColor: Colors.green,
        ),
      );

      // Screen mit aktualisierten Daten neu laden
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DetailScreen(
            papierkorb: aktualisiert,
            readonly: widget.readonly,
          ),
        ),
      );

    } catch (e) {
      setState(() => _speichertEdit = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _leerungBestaetigen() async {
    setState(() => _speichert = true);
    try {
      await _service.leerungBestaetigen(
        papierkorbId: widget.papierkorb.id,
      );
      setState(() {
        _speichert = false;
        _erfolgreich = true;
      });
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _speichert = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pk = widget.papierkorb;

    return Scaffold(
      appBar: AppBar(
        title: Text(pk.qrCode),
        actions: [
          // Edit-Button nur für Erfasser + Admin (nicht readonly=Fahrer)
          if (!widget.readonly && !_editModus)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _startEdit,
            ),
          if (_editModus) ...[
            TextButton(
              onPressed: _abbrechenEdit,
              child: const Text('Abbrechen',
                  style: TextStyle(color: Colors.red)),
            ),
          ],
        ],
      ),
      body: _erfolgreich
          ? _erfolgsAnzeige()
          : _editModus
              ? _editLayout(pk)
              : kIsWeb
                  ? _webLayout(pk)
                  : _mobilLayout(pk),
    );
  }

  // ----------------------------------------------------------
  // EDIT LAYOUT
  // ----------------------------------------------------------
  Widget _editLayout(Papierkorb pk) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Foto
          _editFotoBereich(pk),
          const SizedBox(height: 24),

          // Straße
          Text('Straße *',
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          _laedtStrassen
              ? const LinearProgressIndicator()
              : _strassenAuswahl(),

          const SizedBox(height: 16),

          // Hausnummer
          TextFormField(
            controller: _editHausnummerCtrl,
            decoration: const InputDecoration(
              labelText: 'Hausnummer',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.home_outlined),
            ),
          ),

          const SizedBox(height: 16),

          // Beschreibung
          TextFormField(
            controller: _editBeschreibungCtrl,
            decoration: const InputDecoration(
              labelText: 'Beschreibung',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.notes),
            ),
            maxLines: 2,
          ),

          const SizedBox(height: 16),

          // GPS
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _editLatCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Breitengrad (lat)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _editLngCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Längengrad (lng)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true, signed: true),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Status
          DropdownButtonFormField<String>(
            value: _editStatus,
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
            onChanged: (v) => setState(() => _editStatus = v!),
          ),

          const SizedBox(height: 32),

          // Speichern
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _speichertEdit ? null : _speichernEdit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: _speichertEdit
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(
                _speichertEdit ? 'Wird gespeichert...' : 'Speichern',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _editFotoBereich(Papierkorb pk) {
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
            height: 180,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: _editNeuesFoto != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(_editNeuesFoto!,
                            fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
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
                  )
                : pk.fotoUrl != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: pk.fotoUrl!,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.black38,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.camera_alt,
                                      color: Colors.white, size: 32),
                                  SizedBox(height: 4),
                                  Text('Foto ersetzen',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 13)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_alt,
                              size: 36, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text('Foto aufnehmen',
                              style: TextStyle(
                                  color: Colors.grey.shade500)),
                        ],
                      ),
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
          if (_editStrassenId != null && _allStrassen.isNotEmpty)
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
                      _allStrassen.firstWhere((s) =>
                          s['id'] == _editStrassenId,
                          orElse: () => {'name': ''})['name'] as String,
                      style: TextStyle(
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _editStrassenId = null),
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
                        style:
                            TextStyle(color: Colors.grey.shade500)))
                : ListView.builder(
                    itemCount: _strassenListe.length,
                    itemBuilder: (_, i) {
                      final s = _strassenListe[i];
                      final istAusgewaehlt =
                          s['id'] == _editStrassenId;
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
                            () => _editStrassenId = s['id'] as int),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // WEB LAYOUT
  // ----------------------------------------------------------
  Widget _webLayout(Papierkorb pk) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(right: 32),
              child: _infoBereich(pk),
            ),
          ),
          Expanded(
            flex: 2,
            child: _fotoWidget(pk, maxHoehe: 320),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // MOBIL LAYOUT
  // ----------------------------------------------------------
  Widget _mobilLayout(Papierkorb pk) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: _fotoWidget(pk),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: _infoBereich(pk),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // FOTO WIDGET (readonly)
  // ----------------------------------------------------------
  Widget _fotoWidget(Papierkorb pk, {double? maxHoehe}) {
    if (pk.fotoUrl == null) {
      return Container(
        height: 160,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.no_photography,
                size: 36, color: Colors.grey.shade400),
            const SizedBox(height: 4),
            Text('Kein Foto vorhanden',
                style: TextStyle(
                    color: Colors.grey.shade400, fontSize: 12)),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final seite = maxHoehe != null
            ? constraints.maxWidth.clamp(0.0, maxHoehe)
            : constraints.maxWidth;
        return Container(
          width: seite,
          height: seite,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: pk.fotoUrl!,
              fit: BoxFit.contain,
              placeholder: (_, __) => const Center(
                  child: CircularProgressIndicator()),
              errorWidget: (_, __, ___) => Icon(
                  Icons.broken_image,
                  color: Colors.grey.shade400,
                  size: 40),
            ),
          ),
        );
      },
    );
  }

  // ----------------------------------------------------------
  // INFO BEREICH (readonly)
  // ----------------------------------------------------------
  Widget _infoBereich(Papierkorb pk) {
    final datumFormat = DateFormat('dd.MM.yyyy', 'de_DE');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // Nummer + Status
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                pk.qrCode,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade800,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: pk.status == 'aktiv'
                    ? Colors.green.shade50
                    : pk.status == 'defekt'
                        ? Colors.orange.shade50
                        : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: pk.status == 'aktiv'
                      ? Colors.green.shade200
                      : pk.status == 'defekt'
                          ? Colors.orange.shade200
                          : Colors.red.shade200,
                ),
              ),
              child: Text(
                pk.status,
                style: TextStyle(
                  fontSize: 12,
                  color: pk.status == 'aktiv'
                      ? Colors.green.shade700
                      : pk.status == 'defekt'
                          ? Colors.orange.shade700
                          : Colors.red.shade700,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // Adresse
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.location_on,
                color: Colors.grey.shade500, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(pk.adresse,
                      style:
                          Theme.of(context).textTheme.titleMedium),
                  if (pk.stadtteil != null)
                    Text(pk.stadtteil!,
                        style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13)),
                ],
              ),
            ),
          ],
        ),

        // Koordinaten
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(left: 28),
          child: Text(
            '${pk.lat.toStringAsFixed(6)}, ${pk.lng.toStringAsFixed(6)}',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade400,
              fontFamily: 'monospace',
            ),
          ),
        ),

        // Beschreibung
        if (pk.beschreibung != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.shade200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    color: Colors.amber, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(pk.beschreibung!)),
              ],
            ),
          ),
        ],

        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 16),

        // Leerungshistorie
        Text(
          'Leerungshistorie',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),

        if (_laedtLeerungen)
          const Center(child: CircularProgressIndicator())
        else if (_leerungen.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Noch keine Leerung erfasst',
                style: TextStyle(color: Colors.grey.shade500)),
          )
        else
          ..._leerungen.map((l) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: l.twice
                          ? Colors.orange
                          : Colors.green.shade600,
                    ),
                    const SizedBox(width: 8),
                    Text(datumFormat
                        .format(l.geleertAm.toLocal())),
                    if (l.twice) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('2×',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange.shade800)),
                      ),
                    ],
                    if (l.bemerkung != null) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l.bemerkung!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              )),

        // Geleert-Button nur Fahrer (readonly=false aber kein Edit-Modus)
        if (widget.readonly) ...[
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _speichert ? null : _leerungBestaetigen,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: _speichert
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline, size: 24),
              label: Text(
                _speichert ? 'Wird gespeichert...' : 'Geleert ✓',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],

        const SizedBox(height: 24),
      ],
    );
  }

  Widget _erfolgsAnzeige() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle,
              color: Colors.green.shade600, size: 80),
          const SizedBox(height: 16),
          Text(
            'Leerung gespeichert!',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: Colors.green.shade700),
          ),
          const SizedBox(height: 8),
          Text(
            widget.papierkorb.qrCode,
            style: TextStyle(
                color: Colors.grey.shade600,
                fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}