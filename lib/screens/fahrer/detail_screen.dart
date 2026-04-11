import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
import '../../models/papierkorb.dart';
import '../../models/leerung.dart';
import '../../services/papierkorb_service.dart';

class DetailScreen extends StatefulWidget {
  final Papierkorb papierkorb;

  const DetailScreen({super.key, required this.papierkorb});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final _service = PapierkorbService();
  final _bemerkungCtrl = TextEditingController();
  final _picker = ImagePicker();

  File? _foto;
  bool _speichert = false;
  String _ausgewaehlterStatus = 'ok';
  String _ausgewaehlteFuellung = 'voll';
  List<Leerung> _letzteLeerungen = [];

  @override
  void initState() {
    super.initState();
    // Status nur setzen, wenn es ein gültiger Status ist, sonst 'ok' behalten
    if (['ok', 'defekt', 'schmutzig'].contains(widget.papierkorb.status)) {
      _ausgewaehlterStatus = widget.papierkorb.status;
    }
    _ladeLetzteLeerungen();
  }

  Future<void> _fotoAufnehmen() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 50, // Komprimierung direkt beim Pick
      maxWidth: 1024,
    );
    if (image != null) {
      setState(() => _foto = File(image.path));
    }
  }

  Future<void> _ladeLetzteLeerungen() async {
    try {
      final leerungen =
          await _service.leerungenFuer(widget.papierkorb.id, limit: 3);
      if (mounted) {
        setState(() {
          _letzteLeerungen = leerungen;
        });
      }
    } catch (e) {
      debugPrint("Fehler beim Laden der Leerungen: $e");
    }
  }

  Future<void> _speichern() async {
    setState(() => _speichert = true);
    try {
      await _service.leerungBestaetigen(
        papierkorbId: widget.papierkorb.id,
        bemerkung: _bemerkungCtrl.text,
        foto: _foto,
        neuerStatus: _ausgewaehlterStatus,
        befuellung: _ausgewaehlteFuellung, // NEU: Füllstand übergeben
      );
      if (mounted) {
        setState(() => _speichert = false);
        _bemerkungCtrl.clear();
        setState(() => _foto = null);
        // Historie neu laden nach erfolgreicher Leerung
        _ladeLetzteLeerungen();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Leerung erfolgreich bestätigt!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _speichert = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fehler: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _speichert = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pk = widget.papierkorb;

    return Scaffold(
      appBar: AppBar(
        title: Text('Papierkorb ${pk.nummer}'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Info Card mit Straßennamen + Foto
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    // Straßennamen mit Hausnummer (75%)
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${pk.strassenName ?? 'Unbekannte Straße'} ${pk.hausnummer ?? ''}',
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(pk.stadtteil ?? 'Kein Stadtteil',
                              style: TextStyle(color: Colors.grey.shade600)),
                          if (pk.beschreibung != null) ...[
                            const SizedBox(height: 8),
                            Text(pk.beschreibung!,
                                style: const TextStyle(
                                    fontStyle: FontStyle.italic)),
                          ]
                        ],
                      ),
                    ),
                    // Foto (25%)
                    Expanded(
                      flex: 1,
                      child: Container(
                        height: 120, // Hochformat mit Verhältnis 0,75
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: pk.fotoUrl != null
                              ? GestureDetector(
                                  onTap: () => _showPhotoDialog(pk.fotoUrl!),
                                  child: Hero(
                                    tag: 'photo_${pk.id}',
                                    child: CachedNetworkImage(
                                      imageUrl: pk.fotoUrl!,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) =>
                                          const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                      errorWidget: (context, url, error) {
                                        return Container(
                                          color: Colors.grey.shade200,
                                          child: const Icon(Icons.photo,
                                              color: Colors.grey),
                                        );
                                      },
                                    ),
                                  ),
                                )
                              : Container(
                                  color: Colors.grey.shade200,
                                  child: const Icon(Icons.photo,
                                      color: Colors.grey),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Status Auswahl
            const Text("Zustand / Status:",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'ok', label: Text('OK'), icon: Icon(Icons.check)),
                ButtonSegment(
                    value: 'schmutzig',
                    label: Text('Schmutzig'),
                    icon: Icon(Icons.cleaning_services)),
                ButtonSegment(
                    value: 'defekt',
                    label: Text('Defekt'),
                    icon: Icon(Icons.build)),
              ],
              selected: {_ausgewaehlterStatus},
              onSelectionChanged: (newSelection) {
                setState(() => _ausgewaehlterStatus = newSelection.first);
              },
            ),

            const SizedBox(height: 24),

            // Füllung Auswahl
            const Text("Füllung:",
                style: TextStyle(
                    fontSize: 16, // Kleinere Schriftart
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              style: SegmentedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                selectedBackgroundColor: Colors.green.shade100,
                textStyle: const TextStyle(fontSize: 12),
              ),
              segments: const [
                ButtonSegment(
                  value: 'leer',
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_outlined, size: 14),
                      SizedBox(width: 2),
                      Flexible(
                          child: Text('Leer', style: TextStyle(fontSize: 12))),
                    ],
                  ),
                ),
                ButtonSegment(
                  value: 'halbvoll',
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox, size: 14),
                      SizedBox(width: 2),
                      Flexible(
                          child: Text('Halb', style: TextStyle(fontSize: 12))),
                    ],
                  ),
                ),
                ButtonSegment(
                  value: 'voll',
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.mark_email_unread, size: 14),
                      SizedBox(width: 2),
                      Flexible(
                          child: Text('Voll', style: TextStyle(fontSize: 12))),
                    ],
                  ),
                ),
                ButtonSegment(
                  value: 'überfüllt',
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning, size: 14),
                      SizedBox(width: 2),
                      Flexible(
                          child: Text('Über', style: TextStyle(fontSize: 12))),
                    ],
                  ),
                ),
              ],
              selected: {_ausgewaehlteFuellung},
              onSelectionChanged: (newSelection) {
                setState(() => _ausgewaehlteFuellung = newSelection.first);
              },
            ),

            const SizedBox(height: 24),

            // Bemerkungsfeld
            TextField(
              controller: _bemerkungCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: "Bemerkung (optional)",
                hintText: "Z.B. Graffitischäden oder stark verschmutzt...",
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.photo_camera),
                      onPressed: _fotoAufnehmen,
                      tooltip: 'Foto hinzufügen',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Absende Button - Prominent gestaltet
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: ElevatedButton.icon(
                onPressed: _speichert ? null : _speichern,
                icon: _speichert
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.white,
                        ))
                    : const Icon(Icons.save_alt, size: 28),
                label: Text(
                  "LEERUNG BESTÄTIGEN",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 20.0),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 8,
                ),
              ),
            ),

            // Leerungs-Historie
            if (_letzteLeerungen.isNotEmpty) ...[
              const SizedBox(height: 24),
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Letzte Leerungen',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ..._letzteLeerungen
                          .map((leerung) => Padding(
                                padding: const EdgeInsets.only(bottom: 8.0),
                                child: Row(
                                  children: [
                                    const Icon(Icons.history,
                                        size: 16, color: Colors.grey),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Leerung am: ${_formatDatum(leerung.geleertAm)}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ))
                          .toList(),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDatum(DateTime datum) {
    return '${datum.day.toString().padLeft(2, '0')}.${datum.month.toString().padLeft(2, '0')}.${datum.year}';
  }

  // ----------------------------------------------------------
  // FOTO-DIALOG FÜR GROẞANZEIGT
  // ----------------------------------------------------------
  void _showPhotoDialog(String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.95,
          height: MediaQuery.of(context).size.height * 0.95,
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
              // Foto in voller Größe
              Center(
                child: InteractiveViewer(
                  minScale: 1.0,
                  maxScale: 4.0,
                  child: Hero(
                    tag: 'photo_${widget.papierkorb.id}',
                    child: CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
