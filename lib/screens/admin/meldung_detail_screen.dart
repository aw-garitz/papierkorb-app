import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/papierkorb_service.dart';

class MeldungDetailScreen extends StatefulWidget {
  final Map<String, dynamic> meldung;
  const MeldungDetailScreen({super.key, required this.meldung});

  @override
  State<MeldungDetailScreen> createState() => _MeldungDetailScreenState();
}

class _MeldungDetailScreenState extends State<MeldungDetailScreen> {
  final _service = PapierkorbService();
  final _bemerkungCtrl = TextEditingController();
  bool _speichert = false;

  @override
  void dispose() {
    _bemerkungCtrl.dispose();
    super.dispose();
  }

  Future<void> _erledigen() async {
    setState(() => _speichert = true);
    try {
      await _service.meldungErledigen(
        typ: widget.meldung['typ'] as String,
        id: widget.meldung['id'].toString(),
        papierkorbId: widget.meldung['papierkorb_id'].toString(),
        bemerkung: _bemerkungCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _speichert = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.meldung;
    final nummer = m['nummer']?.toString() ?? '???';
    final strasse = m['strasse'] as String? ?? 'Unbekannte Straße';
    final bemerkung = m['bemerkung'] as String?;
    final fotoUrl = m['foto_url'] as String?;

    return Scaffold(
      appBar: AppBar(title: Text('Meldung Papierkorb $nummer')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Linke Spalte: Informationen und Formular
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(strasse, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  if (bemerkung != null && bemerkung.isNotEmpty) ...[
                    const Text("Meldung vom Fahrer:", style: TextStyle(fontWeight: FontWeight.bold)),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                      child: Text(bemerkung, style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 16)),
                    ),
                  ],
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 24),
                  const Text("Meldung bearbeiten", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bemerkungCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Interne Bemerkung zur Erledigung',
                      hintText: 'Was wurde getan? (z.B. Gereinigt, repariert...)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 4,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _speichert ? null : _erledigen,
                      icon: _speichert 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle),
                      label: const Text("ALS ERLEDIGT MARKIEREN", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            // Rechte Spalte: Foto (falls vorhanden)
            if (fotoUrl != null && fotoUrl.isNotEmpty) ...[
              const SizedBox(width: 32),
              Expanded(
                flex: 2,
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 500),
                  alignment: Alignment.topCenter,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(imageUrl: fotoUrl, fit: BoxFit.contain, placeholder: (context, url) => const Center(child: CircularProgressIndicator())),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}