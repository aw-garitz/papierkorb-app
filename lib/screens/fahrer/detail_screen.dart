import 'dart:io';
import 'dart:typed_data';
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
  List<Leerung> _leerungen = [];
  bool _laedtLeerungen = true;
  bool _speichert = false;
  bool _erfolgreich = false;
  late Papierkorb _papierkorb;

  // Cache-Buster für Foto nach Edit
  String? _fotoUrlMitTimestamp;

  @override
  void initState() {
    super.initState();
    _papierkorb = widget.papierkorb;
    _ladeLeerungen();
  }

  Future<void> _ladeLeerungen() async {
    try {
      final leerungen = await _service.leerungenFuer(_papierkorb.id);
      setState(() {
        _leerungen = leerungen;
        _laedtLeerungen = false;
      });
    } catch (_) {
      setState(() => _laedtLeerungen = false);
    }
  }

  Future<void> _oeffneEdit() async {
    final aktualisiert = await Navigator.pushNamed(
      context,
      '/edit',
      arguments: _papierkorb,
    );
    if (aktualisiert is Papierkorb) {
      setState(() {
        _papierkorb = aktualisiert;
        // Cache-Buster damit Browser das neue Foto lädt
        if (aktualisiert.fotoUrl != null) {
          _fotoUrlMitTimestamp =
              '${aktualisiert.fotoUrl!}?t=${DateTime.now().millisecondsSinceEpoch}';
        }
      });
    }
  }

  Future<void> _zeigeLeerungsDialog() async {
    final bemerkungCtrl = TextEditingController();
    File? foto;
    Uint8List? fotoBytes;
    String status = _papierkorb.status;
    bool dialogSpeichert = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Leerung — ${_papierkorb.qrCode}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // Foto aufnehmen
                GestureDetector(
                  onTap: () async {
                    final picker = ImagePicker();
                    final bild = await picker.pickImage(
                      source: kIsWeb
                          ? ImageSource.gallery
                          : ImageSource.camera,
                      imageQuality: 90,
                    );
                    if (bild != null) {
                      final bytes = await bild.readAsBytes();
                      setDialogState(() {
                        fotoBytes = bytes;
                        foto = kIsWeb ? null : File(bild.path);
                      });
                    }
                  },
                  child: Container(
                    height: 140,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: fotoBytes != null
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(fotoBytes!,
                                    fit: BoxFit.cover),
                              ),
                              Positioned(
                                top: 6, right: 6,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius:
                                        BorderRadius.circular(4),
                                  ),
                                  child: Icon(
                                    kIsWeb
                                        ? Icons.upload_file
                                        : Icons.refresh,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                kIsWeb
                                    ? Icons.upload_file
                                    : Icons.camera_alt,
                                size: 32,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                kIsWeb
                                    ? 'Datei auswählen (optional)'
                                    : 'Foto aufnehmen (optional)',
                                style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 13),
                              ),
                            ],
                          ),
                  ),
                ),

                const SizedBox(height: 16),

                // Bemerkung
                TextField(
                  controller: bemerkungCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Bemerkung (optional)...',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),

                const SizedBox(height: 16),

                // Status
                Text('Status',
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _statusChip('aktiv', 'Aktiv', Colors.green,
                        status,
                        (v) => setDialogState(() => status = v)),
                    const SizedBox(width: 8),
                    _statusChip('defekt', 'Defekt', Colors.orange,
                        status,
                        (v) => setDialogState(() => status = v)),
                    const SizedBox(width: 8),
                    _statusChip('entfernt', 'Entfernt', Colors.red,
                        status,
                        (v) => setDialogState(() => status = v)),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  dialogSpeichert ? null : () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            FilledButton.icon(
              onPressed: dialogSpeichert
                  ? null
                  : () async {
                      setDialogState(() => dialogSpeichert = true);
                      try {
                        await _service.leerungBestaetigen(
                          papierkorbId: _papierkorb.id,
                          papierkorbQrCode: _papierkorb.qrCode,
                          bemerkung: bemerkungCtrl.text.trim().isEmpty
                              ? null
                              : bemerkungCtrl.text.trim(),
                          foto:       foto,
                          fotoBytes:  fotoBytes,
                          neuerStatus:
                              status != _papierkorb.status
                                  ? status
                                  : null,
                        );
                        if (!ctx.mounted) return;
                        Navigator.pop(ctx);
                        setState(() => _erfolgreich = true);
                        await Future.delayed(
                            const Duration(seconds: 2));
                        if (mounted) Navigator.pop(context);
                      } catch (e) {
                        setDialogState(
                            () => dialogSpeichert = false);
                        if (!ctx.mounted) return;
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text('Fehler: $e'),
                            backgroundColor: Colors.red.shade700,
                          ),
                        );
                      }
                    },
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700),
              icon: dialogSpeichert
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
              label: Text(
                  dialogSpeichert ? 'Speichert...' : 'Geleert ✓'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String wert, String label, MaterialColor farbe,
      String aktuellerWert, Function(String) onTap) {
    final ausgewaehlt = wert == aktuellerWert;
    return GestureDetector(
      onTap: () => onTap(wert),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: ausgewaehlt
              ? farbe.shade100
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: ausgewaehlt
                ? farbe.shade400
                : Colors.grey.shade300,
            width: ausgewaehlt ? 2 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: ausgewaehlt
                ? farbe.shade800
                : Colors.grey.shade600,
            fontWeight: ausgewaehlt
                ? FontWeight.bold
                : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_papierkorb.qrCode),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'Bearbeiten',
            onPressed: _oeffneEdit,
          ),
        ],
      ),
      body: _erfolgreich
          ? _erfolgsAnzeige()
          : kIsWeb
              ? _webLayout()
              : _mobilLayout(),
    );
  }

  Widget _webLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(right: 32),
              child: _infoBereich(),
            ),
          ),
          Expanded(
            flex: 2,
            child: _fotoWidget(maxHoehe: 320),
          ),
        ],
      ),
    );
  }

  Widget _mobilLayout() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: _fotoWidget(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: _infoBereich(),
          ),
        ],
      ),
    );
  }

  Widget _fotoWidget({double? maxHoehe}) {
    // URL mit Cache-Buster falls nach Edit aktualisiert
    final fotoUrl = _fotoUrlMitTimestamp ?? _papierkorb.fotoUrl;

    if (fotoUrl == null) {
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
              imageUrl: fotoUrl,
              // Cache-Key erzwingen wenn Timestamp gesetzt
              cacheKey: _fotoUrlMitTimestamp != null
                  ? 'foto_${_papierkorb.qrCode}_${DateTime.now().millisecondsSinceEpoch}'
                  : _papierkorb.qrCode,
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

  Widget _infoBereich() {
    final datumFormat = DateFormat('dd.MM.yyyy', 'de_DE');
    final pk = _papierkorb;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        // QR-Code + Status
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
          Text('Noch keine Leerung erfasst',
              style: TextStyle(color: Colors.grey.shade500))
        else
          ..._leerungen.map((l) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: l.twice
                          ? Colors.orange
                          : Colors.green.shade600,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(datumFormat
                                  .format(l.geleertAm.toLocal())),
                              if (l.twice) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade100,
                                    borderRadius:
                                        BorderRadius.circular(4),
                                  ),
                                  child: Text('2×',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors
                                              .orange.shade800)),
                                ),
                              ],
                            ],
                          ),
                          if (l.bemerkung != null)
                            Padding(
                              padding:
                                  const EdgeInsets.only(top: 4),
                              child: Text(
                                l.bemerkung!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          if (l.fotoUrl != null)
                            Padding(
                              padding:
                                  const EdgeInsets.only(top: 6),
                              child: ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(6),
                                child: CachedNetworkImage(
                                  imageUrl: l.fotoUrl!,
                                  height: 80,
                                  width: 120,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),

        // Geleert-Button nur Fahrer (readonly=true)
        if (widget.readonly) ...[
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed:
                  _speichert ? null : _zeigeLeerungsDialog,
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
            _papierkorb.qrCode,
            style: TextStyle(
                color: Colors.grey.shade600,
                fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}