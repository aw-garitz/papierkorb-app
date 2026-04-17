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
  List<Map<String, dynamic>> _meldungen = [];
  bool _laedt = true;
  String? _fehler;
  final Set<String> _erledigt = {};

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
        final gefiltert = alle.where((m) {
          final hatBemerkung = m['bemerkung'] != null && m['bemerkung'].toString().trim().isNotEmpty;
          final hatFoto = m['foto_url'] != null && m['foto_url'].toString().trim().isNotEmpty;
          return hatBemerkung || hatFoto;
        }).toList();

        // Sortierung: Neueste Meldungen zuerst
        gefiltert.sort((a, b) {
          final dateA = DateTime.tryParse(a['geleert_am']?.toString() ?? '') ?? DateTime(0);
          final dateB = DateTime.tryParse(b['geleert_am']?.toString() ?? '') ?? DateTime(0);
          return dateB.compareTo(dateA);
        });

        setState(() {
          _meldungen = gefiltert;
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

  Future<void> _erledigen(Map<String, dynamic> meldung) async {
    final id = meldung['id'].toString();
    final typ = meldung['typ'] as String;
    final papierkorbId = meldung['papierkorb_id'].toString();

    setState(() => _erledigt.add(id));
    try {
      await _service.meldungErledigen(
        typ: typ,
        id: id,
        papierkorbId: papierkorbId,
      );
      _laden();
      widget.onMeldungErledigt?.call();
    } catch (e) {
      if (mounted) {
        setState(() => _erledigt.remove(id));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
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
      child: _meldungen.isEmpty
          ? const Center(child: Text("Keine Meldungen vorhanden."))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _meldungen.length,
              itemBuilder: (context, i) {
                final m = _meldungen[i];
                final id = m['id'].toString();
                final status = m['status'] as String;
                final nummer = m['nummer']?.toString() ?? '???';
                final strasse = m['strasse'] as String? ?? 'Unbekannte Straße';
                final bemerkung = m['bemerkung'] as String?;
                final fotoUrl = m['foto_url'] as String?;
                final datumRaw = m['geleert_am']?.toString();
                final datum = datumRaw != null 
                    ? DateFormat('dd.MM. HH:mm').format(DateTime.parse(datumRaw).toLocal())
                    : '';
                final wirdErledigt = _erledigt.contains(id);

                Color farbe = status == 'defekt' ? Colors.orange : (status == 'entfernt' ? Colors.red : Colors.blue);

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Row(
                                children: [
                                  CircleAvatar(backgroundColor: farbe.withOpacity(0.15), child: Text(nummer, style: TextStyle(color: farbe.withOpacity(0.9), fontWeight: FontWeight.bold))),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(strasse, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                            Text(datum, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                          ],
                                        ),
                                        if (bemerkung != null && bemerkung.isNotEmpty)
                                          Padding(padding: const EdgeInsets.only(top: 4), child: Text(bemerkung, style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontStyle: FontStyle.italic))),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(onPressed: () => _oeffneDetail(m), icon: const Icon(Icons.edit_note), tooltip: 'Details bearbeiten'),
                                  IconButton(onPressed: wirdErledigt ? null : () => _erledigen(m), icon: Icon(wirdErledigt ? Icons.hourglass_empty : Icons.check_circle_outline, color: Colors.green)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (fotoUrl != null && fotoUrl.isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: GestureDetector(
                                onTap: () => _zeigeVollbild(fotoUrl),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: CachedNetworkImage(
                                    imageUrl: fotoUrl,
                                    height: 120, // Kleine Höhe
                                    width: 90,   // Kleine Breite für Hochformat
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}