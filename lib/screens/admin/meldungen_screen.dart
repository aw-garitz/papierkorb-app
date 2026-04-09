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
      final liste = await _service.meldungen();
      if (mounted) {
        setState(() {
          _meldungen = liste;
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
    } catch (e) {
      if (mounted) {
        setState(() => _erledigt.remove(id));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Fehler: $e')));
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

  @override
  Widget build(BuildContext context) {
    final datumFormat = DateFormat('dd.MM.yyyy, HH:mm', 'de_DE');

    if (_laedt) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_fehler != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text("Fehler beim Laden: $_fehler"),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _laden,
                child: const Text("Erneut versuchen"),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Offene Meldungen")),
      body: RefreshIndicator(
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
                  final strasse =
                      m['strasse'] as String? ?? 'Unbekannte Straße';
                  final bemerkung = m['bemerkung'] as String?;
                  final fotoUrl = m['foto_url'] as String?;
                  final wirdErledigt = _erledigt.contains(id);

                  Color farbe = status == 'defekt'
                      ? Colors.orange
                      : (status == 'entfernt' ? Colors.red : Colors.blue);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: farbe.withOpacity(0.4),
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          leading: Icon(Icons.warning, color: farbe),
                          title: Text('Papierkorb #$nummer'),
                          subtitle: Text(strasse),
                        ),
                        if (bemerkung != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Text(
                              bemerkung,
                              style: const TextStyle(
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        if (fotoUrl != null && fotoUrl.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: fotoUrl,
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton(
                                onPressed: () => _oeffneDetail(m),
                                child: const Text("DETAILS / KARTE"),
                              ),
                              ElevatedButton(
                                onPressed: wirdErledigt
                                    ? null
                                    : () => _erledigen(m),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                ),
                                child: Text(
                                  wirdErledigt ? "Lädt..." : "ERLEDIGT",
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
