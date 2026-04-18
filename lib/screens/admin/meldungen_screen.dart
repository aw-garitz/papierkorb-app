import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../services/papierkorb_service.dart';

class MeldungenScreen extends StatefulWidget {
  final VoidCallback? onMeldungErledigt;
  const MeldungenScreen({super.key, this.onMeldungErledigt});

  @override
  State<MeldungenScreen> createState() => _MeldungenScreenState();
}

class _MeldungenScreenState extends State<MeldungenScreen> {
  final _service = PapierkorbService();
  List<Map<String, dynamic>> _offene = [];
  List<Map<String, dynamic>> _historie = [];
  bool _laedt = true;
  String? _fehler;

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    if (!mounted) return;
    setState(() {
      _laedt = true;
      _fehler = null;
    });
    try {
      final alle = await _service.meldungen();
      if (mounted) {
        final alleMeldungen = alle.where((m) {
          final hatBemerkung = m['bemerkung'] != null && m['bemerkung'].toString().trim().isNotEmpty;
          final hatFoto = m['foto_url'] != null && m['foto_url'].toString().trim().isNotEmpty;
          return hatBemerkung || hatFoto;
        }).toList();

        // Sortierung: Neueste Meldungen zuerst
        alleMeldungen.sort((a, b) {
          final dateA = DateTime.tryParse(a['geleert_am']?.toString() ?? '') ?? DateTime(0);
          final dateB = DateTime.tryParse(b['geleert_am']?.toString() ?? '') ?? DateTime(0);
          return dateB.compareTo(dateA);
        });

        setState(() {
          _offene = alleMeldungen.where((m) => m['meldung_erledigt'] == false).toList();
          _historie = alleMeldungen.where((m) => m['meldung_erledigt'] == true).toList();
          _laedt = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _laedt = false;
          _fehler = e.toString();
        });
      }
    }
  }

  void _oeffneMeldungDetail(Map<String, dynamic> meldung) {
    Navigator.pushNamed(context, '/admin/meldung-detail', arguments: meldung).then((value) {
      if (value == true) {
        _laden();
        widget.onMeldungErledigt?.call();
      }
    });
  }

  void _oeffneDetail(Map<String, dynamic> meldung) async {
    final id = meldung['papierkorb_id'];
    final pk = await _service.perId(id);
    if (!mounted || pk == null) return;

    Navigator.pushNamed(context, '/admin/edit', arguments: pk).then((value) {
      if (value == true) _laden();
    });
  }

  // Hilfsmethode für das Vollbild-Overlay
  void _zeigeVollbild(String url) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
      body: Center(child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain)),
    )));
  }

  @override
  Widget build(BuildContext context) {
    if (_laedt) return const Center(child: CircularProgressIndicator());

    if (_fehler != null) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 16),
          Text("Fehler beim Laden: $_fehler"),
          ElevatedButton(onPressed: _laden, child: const Text("Erneut versuchen")),
        ]),
      );
    }

    return RefreshIndicator(
      onRefresh: _laden,
      child: (_offene.isEmpty && _historie.isEmpty)
          ? const Center(child: Text("Keine Meldungen vorhanden."))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (_offene.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                    child: Text("Offene Meldungen", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange)),
                  ),
                  ..._offene.map((m) => _buildMeldungCard(m, istHistorie: false)),
                ],
                if (_historie.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 24.0, bottom: 8.0, left: 4.0),
                    child: Text("Historie Meldungen", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                  ),
                  ..._historie.map((m) => _buildMeldungCard(m, istHistorie: true)),
                ],
              ],
            ),
    );
  }

  Widget _buildMeldungCard(Map<String, dynamic> m, {required bool istHistorie}) {
    final status = m['status'] as String;
    final nummer = m['nummer']?.toString() ?? '???';
    final strasse = m['strasse'] as String? ?? 'Unbekannte Straße';
    final bemerkung = m['bemerkung'] as String?;
    final meldungBemerkung = m['meldung_bemerkung'] as String?;
    final fotoUrl = m['foto_url'] as String?;
    final datumRaw = m['geleert_am']?.toString();
    final datum = datumRaw != null ? DateFormat('dd.MM. HH:mm').format(DateTime.parse(datumRaw).toLocal()) : '';

    Color farbe = istHistorie ? Colors.grey : (status == 'defekt' ? Colors.orange : (status == 'entfernt' ? Colors.red : Colors.blue));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: istHistorie ? 1 : 2,
      color: istHistorie ? Colors.grey.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Linker Bereich: Avatar und Texte
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    backgroundColor: farbe.withOpacity(0.15),
                    child: Text(nummer, style: TextStyle(color: farbe.withOpacity(0.9), fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(strasse, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(width: 8),
                            Text(datum, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                          ],
                        ),
                        if (bemerkung != null && bemerkung.isNotEmpty)
                          Padding(padding: const EdgeInsets.only(top: 4), child: Text(bemerkung, style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontStyle: FontStyle.italic))),
                        if (istHistorie && meldungBemerkung != null && meldungBemerkung.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline, size: 14, color: Colors.green),
                                const SizedBox(width: 4),
                                Expanded(child: Text(meldungBemerkung, style: const TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.w500))),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Mittlerer Bereich: Buttons
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!istHistorie) ...[
                  IconButton(onPressed: () => _oeffneDetail(m), icon: const Icon(Icons.edit_note), tooltip: 'Stammdaten editieren'),
                  IconButton(onPressed: () => _oeffneMeldungDetail(m), icon: const Icon(Icons.check_circle_outline, color: Colors.green), tooltip: 'Meldung bearbeiten & abschließen'),
                ],
                if (istHistorie) const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Icon(Icons.check_circle, color: Colors.green, size: 20)),
              ],
            ),
            // Rechter Bereich: Foto (falls vorhanden)
            if (fotoUrl != null && fotoUrl.isNotEmpty)
              GestureDetector(
                onTap: () => _zeigeVollbild(fotoUrl),
                child: Container(
                  margin: const EdgeInsets.only(left: 12),
                  width: 60,
                  height: 60,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(imageUrl: fotoUrl, fit: BoxFit.cover, color: istHistorie ? Colors.white.withOpacity(0.7) : null, colorBlendMode: istHistorie ? BlendMode.dstATop : null),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}