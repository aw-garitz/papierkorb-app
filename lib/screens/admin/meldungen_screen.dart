import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../services/papierkorb_service.dart';

class MeldungenScreen extends StatefulWidget {
  const MeldungenScreen({super.key});

  @override
  State<MeldungenScreen> createState() => _MeldungenScreenState();
}

class _MeldungenScreenState extends State<MeldungenScreen> {
  final _service = PapierkorbService();
  List<Map<String, dynamic>> _meldungen = [];
  bool _laedt = true;
  final Set<String> _erledigt = {}; // IDs die gerade erledigt werden

  @override
  void initState() {
    super.initState();
    _laden();
  }

  Future<void> _laden() async {
    setState(() => _laedt = true);
    try {
      final liste = await _service.meldungen();
      setState(() {
        _meldungen = liste;
        _laedt = false;
      });
    } catch (e) {
      setState(() => _laedt = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }

  Future<void> _erledigen(Map<String, dynamic> meldung) async {
    final id = meldung['id'] as String;
    final typ = meldung['typ'] as String;
    final papierkorbId = meldung['papierkorb_id'] as String;
    final qrCode = meldung['qr_code'] as String;

    // Bestätigung
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Meldung erledigen?'),
        content: Text(
          '$qrCode wird auf "aktiv" gesetzt\n'
          'und aus der Meldungsliste entfernt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.check),
            label: const Text('Erledigt'),
            style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade700),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _erledigt.add(id));

    try {
      await _service.meldungErledigen(
        typ:          typ,
        id:           id,
        papierkorbId: papierkorbId,
      );
      await _laden();
    } catch (e) {
      setState(() => _erledigt.remove(id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fehler: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  void _oeffneDetail(Map<String, dynamic> meldung) {
    final qrCode = meldung['qr_code'] as String;
    _service.perQrCode(qrCode).then((pk) {
      if (!mounted || pk == null) return;
      Navigator.pushNamed(
        context,
        '/fahrer/detail',
        arguments: {'papierkorb': pk, 'readonly': false},
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final datumFormat = DateFormat('dd.MM.yyyy', 'de_DE');

    return _laedt
        ? const Center(child: CircularProgressIndicator())
        : _meldungen.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 64, color: Colors.green.shade300),
                    const SizedBox(height: 16),
                    Text(
                      'Keine Meldungen',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Alle Papierkörbe sind in Ordnung',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _laden,
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _meldungen.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final m = _meldungen[i];
                    final id = m['id'] as String;
                    final typ = m['typ'] as String;
                    final status = m['status'] as String;
                    final qrCode = m['qr_code'] as String;
                    final strasse = m['strasse'] as String? ?? '';
                    final hausnummer = m['hausnummer'] as String?;
                    final bemerkung = m['bemerkung'] as String?;
                    final fotoUrl = m['foto_url'] as String?;
                    final datum = DateTime.parse(m['datum'] as String);
                    final wirdErledigt = _erledigt.contains(id);

                    // Farbe + Icon + Label
                    Color farbe;
                    IconData icon;
                    String label;

                    if (status == 'defekt') {
                      farbe = Colors.orange;
                      icon = Icons.build_circle_outlined;
                      label = 'Defekt';
                    } else if (status == 'entfernt') {
                      farbe = Colors.red;
                      icon = Icons.remove_circle_outlined;
                      label = 'Entfernt';
                    } else if (fotoUrl != null && bemerkung != null) {
                      farbe = Colors.blue;
                      icon = Icons.report_outlined;
                      label = 'Bemerkung + Foto';
                    } else if (fotoUrl != null) {
                      farbe = Colors.purple;
                      icon = Icons.photo_camera_outlined;
                      label = 'Foto';
                    } else {
                      farbe = Colors.teal;
                      icon = Icons.comment_outlined;
                      label = 'Bemerkung';
                    }

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                            color: farbe.withValues(alpha: 0.4),
                            width: 1.5),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [

                                // Icon
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: farbe.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(icon,
                                      color: farbe, size: 22),
                                ),

                                const SizedBox(width: 12),

                                // Inhalt
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            qrCode,
                                            style: TextStyle(
                                              fontWeight:
                                                  FontWeight.bold,
                                              fontFamily: 'monospace',
                                              color: farbe,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets
                                                .symmetric(
                                                horizontal: 8,
                                                vertical: 2),
                                            decoration: BoxDecoration(
                                              color: farbe.withValues(
                                                  alpha: 0.1),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                      12),
                                            ),
                                            child: Text(
                                              label,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: farbe,
                                                fontWeight:
                                                    FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        [strasse, hausnummer]
                                            .where((s) =>
                                                s != null &&
                                                s.isNotEmpty)
                                            .join(' '),
                                        style: TextStyle(
                                            color:
                                                Colors.grey.shade600,
                                            fontSize: 13),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        datumFormat.format(
                                            datum.toLocal()),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade400,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            // Bemerkung
                            if (bemerkung != null) ...[
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius:
                                      BorderRadius.circular(6),
                                  border: Border.all(
                                      color: Colors.grey.shade200),
                                ),
                                child: Text(
                                  '"$bemerkung"',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            ],

                            // Foto
                            if (fotoUrl != null) ...[
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: fotoUrl,
                                  height: 120,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ],

                            const SizedBox(height: 12),

                            // Aktionen
                            Row(
                              children: [
                                // Detail öffnen
                                OutlinedButton.icon(
                                  onPressed: () => _oeffneDetail(m),
                                  icon: const Icon(Icons.open_in_new,
                                      size: 16),
                                  label: const Text('Details'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8),
                                  ),
                                ),
                                const Spacer(),
                                // Erledigt
                                FilledButton.icon(
                                  onPressed: wirdErledigt
                                      ? null
                                      : () => _erledigen(m),
                                  icon: wirdErledigt
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2),
                                        )
                                      : const Icon(Icons.check,
                                          size: 16),
                                  label: Text(wirdErledigt
                                      ? 'Wird erledigt...'
                                      : 'Erledigt'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor:
                                        Colors.green.shade700,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8),
                                  ),
                                ),
                              ],
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