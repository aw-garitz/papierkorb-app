import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:ui' as ui;
import '../../main.dart';

class QrGeneratorScreen extends StatefulWidget {
  const QrGeneratorScreen({super.key});

  @override
  State<QrGeneratorScreen> createState() => _QrGeneratorScreenState();
}

class _QrGeneratorScreenState extends State<QrGeneratorScreen> {
  int _letzteNummer = 0;
  int _anzahl = 15;
  bool _laedt = true;
  bool _generiert = false;
  final _nachdruckCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _ladeLetzteNummer();
  }

  @override
  void dispose() {
    _nachdruckCtrl.dispose();
    super.dispose();
  }

  Future<void> _ladeLetzteNummer() async {
    try {
      final response = await supabase
          .schema('waste')
          .from('qr_generator')
          .select('letzte_nummer')
          .eq('id', 1)
          .single();
      setState(() {
        _letzteNummer = response['letzte_nummer'] as int;
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

  String _formatNummer(int n) => 'pk_${n.toString().padLeft(4, '0')}';

  Future<Uint8List> _qrBytes(String data) async {
    final painter = QrPainter(
      data: data,
      version: QrVersions.auto,
      gapless: true,
      color: const ui.Color(0xFF000000),
      emptyColor: const ui.Color(0xFFFFFFFF),
    );
    final imgData = await painter.toImageData(300);
    return imgData!.buffer.asUint8List();
  }

  Future<pw.Document> _bauePdf(List<int> nummern) async {
    // Alle QR-Codes generieren — explizit <String, dynamic>
    final List<Map<String, dynamic>> codes = await Future.wait(
      nummern.map((n) async {
        final label = _formatNummer(n);
        final bytes = await _qrBytes(label);
        return <String, dynamic>{'label': label, 'bytes': bytes};
      }),
    );

    final pdf = pw.Document();

    const spalten = 3;
    const zeilenProSeite = 5;
    const perSeite = spalten * zeilenProSeite; // 15

    for (int seiteStart = 0; seiteStart < codes.length; seiteStart += perSeite) {
      final List<Map<String, dynamic>> seitenCodes =
          codes.skip(seiteStart).take(perSeite).toList();

      // Auf 15 auffüllen mit leeren Zellen
      while (seitenCodes.length < perSeite) {
        seitenCodes.add(<String, dynamic>{'label': '', 'bytes': null});
      }

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(15 * PdfPageFormat.mm),
          build: (ctx) {
            final zeilenWidgets = <pw.Widget>[];

            for (int z = 0; z < zeilenProSeite; z++) {
              final spaltenWidgets = <pw.Widget>[];

              for (int s = 0; s < spalten; s++) {
                final idx = z * spalten + s;
                final code = seitenCodes[idx];
                final hatInhalt = code['bytes'] != null;

                spaltenWidgets.add(
                  pw.Expanded(
                    child: pw.Container(
                      margin: const pw.EdgeInsets.all(3),
                      decoration: hatInhalt
                          ? pw.BoxDecoration(
                              border: pw.Border.all(
                                color: PdfColors.grey400,
                                width: 0.5,
                              ),
                              borderRadius: const pw.BorderRadius.all(
                                  pw.Radius.circular(3)),
                            )
                          : null,
                      child: hatInhalt
                          ? pw.Column(
                              mainAxisAlignment: pw.MainAxisAlignment.center,
                              crossAxisAlignment: pw.CrossAxisAlignment.center,
                              children: [
                                pw.Image(
                                  pw.MemoryImage(
                                      code['bytes'] as Uint8List),
                                  width: 90,
                                  height: 90,
                                ),
                                pw.SizedBox(height: 4),
                                pw.Text(
                                  code['label'] as String,
                                  style: pw.TextStyle(
                                    fontSize: 11,
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                  textAlign: pw.TextAlign.center,
                                ),
                              ],
                            )
                          : pw.SizedBox(),
                    ),
                  ),
                );
              }

              zeilenWidgets.add(
                pw.Expanded(
                  child: pw.Row(children: spaltenWidgets),
                ),
              );
            }

            return pw.Column(children: zeilenWidgets);
          },
        ),
      );
    }

    return pdf;
  }

  Future<void> _generierePdf() async {
    setState(() => _generiert = true);

    final vonNummer = _letzteNummer + 1;
    final bisNummer = _letzteNummer + _anzahl;
    final nummern = List.generate(_anzahl, (i) => vonNummer + i);

    try {
      final pdf = await _bauePdf(nummern);

      await supabase
          .schema('waste')
          .from('qr_generator')
          .update({
            'letzte_nummer': bisNummer,
            'geaendert_am': DateTime.now().toIso8601String(),
          })
          .eq('id', 1);

      setState(() {
        _letzteNummer = bisNummer;
        _generiert = false;
      });

      await Printing.layoutPdf(
        onLayout: (_) async => pdf.save(),
        name: 'qr_${_formatNummer(vonNummer)}_${_formatNummer(bisNummer)}.pdf',
      );
    } catch (e) {
      setState(() => _generiert = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }

  Future<void> _nachdruckEinzel() async {
    final eingabe = _nachdruckCtrl.text.trim();
    final nummer = int.tryParse(eingabe);
    if (nummer == null || nummer < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte gültige Nummer eingeben')),
      );
      return;
    }

    setState(() => _generiert = true);

    try {
      final pdf = await _bauePdf([nummer]);
      setState(() => _generiert = false);

      await Printing.layoutPdf(
        onLayout: (_) async => pdf.save(),
        name: 'qr_nachdruck_${_formatNummer(nummer)}.pdf',
      );
    } catch (e) {
      setState(() => _generiert = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vonNummer = _letzteNummer + 1;
    final bisNummer = _letzteNummer + _anzahl;

    return _laedt
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // Status
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.blue.shade700, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _letzteNummer == 0
                              ? 'Noch keine QR-Codes generiert'
                              : 'Zuletzt gedruckt bis: ${_formatNummer(_letzteNummer)}',
                          style: TextStyle(color: Colors.blue.shade800),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                Text('Neuer Druck',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),

                Text('Anzahl neue QR-Codes: $_anzahl',
                    style: const TextStyle(fontSize: 15)),
                Slider(
                  value: _anzahl.toDouble(),
                  min: 15,
                  max: 150,
                  divisions: 9,
                  label: '$_anzahl',
                  onChanged: (v) => setState(() => _anzahl = v.round()),
                ),
                Text(
                  '${(_anzahl / 15).ceil()} ${(_anzahl / 15).ceil() == 1 ? 'Seite' : 'Seiten'} (15 pro Seite, 3×5)',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600),
                ),

                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.print, color: Colors.green.shade700),
                      const SizedBox(width: 12),
                      Text(
                        '${_formatNummer(vonNummer)}  →  ${_formatNummer(bisNummer)}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade800,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _generiert ? null : _generierePdf,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _generiert
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.print),
                    label: Text(
                      _generiert
                          ? 'Wird generiert...'
                          : 'PDF generieren & drucken',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),

                const SizedBox(height: 40),
                const Divider(),
                const SizedBox(height: 24),

                Text('Nachdruck (Ersatz)',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'QR-Code verblasst oder beschädigt? Nummer eingeben:',
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _nachdruckCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Nummer (z.B. 42)',
                          prefixText: 'pk_',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          prefixStyle: TextStyle(
                              color: Colors.grey.shade700,
                              fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _generiert ? null : _nachdruckEinzel,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Drucken'),
                    ),
                  ],
                ),
              ],
            ),
          );
  }
}