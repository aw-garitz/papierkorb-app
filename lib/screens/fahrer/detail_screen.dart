import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
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
  bool _laedt = true;
  bool _speichert = false;
  bool _erfolgreich = false;

  @override
  void initState() {
    super.initState();
    _ladeLeerungen();
  }

  Future<void> _ladeLeerungen() async {
    try {
      final leerungen = await _service.leerungenFuer(widget.papierkorb.id);
      setState(() {
        _leerungen = leerungen;
        _laedt = false;
      });
    } catch (_) {
      setState(() => _laedt = false);
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
      appBar: AppBar(title: Text(pk.qrCode)),
      body: _erfolgreich
          ? _erfolgsAnzeige()
          : kIsWeb
              ? _webLayout(pk)
              : _mobilLayout(pk),
    );
  }

  // ----------------------------------------------------------
  // WEB: zweispaltig — links Text, rechts Foto
  // ----------------------------------------------------------
  Widget _webLayout(Papierkorb pk) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Linke Spalte: alle Textinfos
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(right: 32),
              child: _infoBereich(pk),
            ),
          ),

          // Rechte Spalte: Foto
          Expanded(
            flex: 2,
            child: _fotoWidget(pk, maxHoehe: 320),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // MOBIL: einspaltig — Foto oben, Text darunter
  // ----------------------------------------------------------
  Widget _mobilLayout(Papierkorb pk) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Foto — quadratischer Container, Foto mit contain darin
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
  // FOTO WIDGET
  // Quadratischer Container — Foto mit BoxFit.contain darin
  // Hoch- und Querformat werden vollständig angezeigt
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
        // Quadrat: Seite = verfügbare Breite, begrenzt durch maxHoehe
        final seite = maxHoehe != null
            ? constraints.maxWidth.clamp(0.0, maxHoehe)
            : constraints.maxWidth;

        return Container(
          width: seite,
          height: seite,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,  // Letterbox-Hintergrund
            borderRadius: BorderRadius.circular(12),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: pk.fotoUrl!,
              fit: BoxFit.contain,   // Foto vollständig sichtbar
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
  // INFO BEREICH (geteilt zwischen Web und Mobil)
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
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: pk.status == 'aktiv'
                      ? Colors.green.shade200
                      : Colors.red.shade200,
                ),
              ),
              child: Text(
                pk.status,
                style: TextStyle(
                  fontSize: 12,
                  color: pk.status == 'aktiv'
                      ? Colors.green.shade700
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
                  Text(
                    pk.adresse,
                    style:
                        Theme.of(context).textTheme.titleMedium,
                  ),
                  if (pk.stadtteil != null)
                    Text(
                      pk.stadtteil!,
                      style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13),
                    ),
                ],
              ),
            ),
          ],
        ),

        // Koordinaten nur im Admin-Modus
        if (widget.readonly) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              '${pk.lat.toStringAsFixed(6)}, '
              '${pk.lng.toStringAsFixed(6)}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade400,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],

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

        if (_laedt)
          const Center(child: CircularProgressIndicator())
        else if (_leerungen.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Noch keine Leerung erfasst',
              style: TextStyle(color: Colors.grey.shade500),
            ),
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
                          borderRadius:
                              BorderRadius.circular(4),
                        ),
                        child: Text(
                          '2×',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange.shade800,
                          ),
                        ),
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

        // Geleert-Button nur im Fahrer-Modus
        if (!widget.readonly) ...[
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed:
                  _speichert ? null : _leerungBestaetigen,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _speichert
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.delete_outline, size: 24),
              label: Text(
                _speichert ? 'Wird gespeichert...' : 'Geleert ✓',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
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