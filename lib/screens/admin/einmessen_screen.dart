import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/papierkorb_service.dart';

class EinmessenScreen extends StatefulWidget {
  const EinmessenScreen({super.key});

  @override
  State<EinmessenScreen> createState() => _EinmessenScreenState();
}

class _EinmessenScreenState extends State<EinmessenScreen> {
  final _service = PapierkorbService();
  final _formKey = GlobalKey<FormState>();

  String? _qrCode;
  int? _nummer;
  int? _strassenId;
  String? _bauartId;
  final _hausnummerCtrl = TextEditingController();
  final _beschreibungCtrl = TextEditingController();
  double? _lat;
  double? _lng;

  File? _foto;
  Uint8List? _fotoBytes;

  bool _laedt = false;
  bool _laedtStrassen = true;
  bool _laedtBauarten = true;
  bool _scanlaeuft = false;
  bool _gpsLaedt = false;

  List<Map<String, dynamic>> _allStrassen = [];
  List<Map<String, dynamic>> _strassenListe = [];
  final _strassenSuchCtrl = TextEditingController();

  List<Map<String, dynamic>> _bauarten = [];

  @override
  void initState() {
    super.initState();
    _ladeStrassen();
    _ladeBauarten();
    _strassenSuchCtrl.addListener(_strassenFiltern);
  }

  @override
  void dispose() {
    _hausnummerCtrl.dispose();
    _beschreibungCtrl.dispose();
    _strassenSuchCtrl.dispose();
    super.dispose();
  }

  Future<void> _ladeStrassen() async {
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

  Future<void> _ladeBauarten() async {
    try {
      final liste = await _service.bauarten();
      setState(() {
        _bauarten = liste;
        _laedtBauarten = false;
      });
    } catch (_) {
      setState(() => _laedtBauarten = false);
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

  Future<void> _qrScannen() async {
    setState(() => _scanlaeuft = true);
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _QrScannerDialog()),
    );
    setState(() => _scanlaeuft = false);
    if (result == null) return;

    final regex = RegExp(r'^pk_(\d{4})$');
    final match = regex.firstMatch(result);
    if (match == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ungültiger QR-Code: $result'),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    final vorhanden = await _service.perQrCode(result);
    if (!mounted) return;
    if (vorhanden != null) {
      final weiter = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('$result bereits erfasst'),
          content: const Text(
              'Möchtest du den bestehenden Eintrag bearbeiten?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Bearbeiten'),
            ),
          ],
        ),
      );
      if (weiter == true && mounted) {
        Navigator.pushNamed(context, '/edit', arguments: vorhanden);
      }
      return;
    }

    setState(() {
      _qrCode = result;
      _nummer = int.parse(match.group(1)!);
    });
  }

  Future<Position?> _holeGps() async {
    try {
      final berechtigung = await Geolocator.checkPermission();
      if (berechtigung == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _fotoAufnehmen() async {
    if (_qrCode == null) return;
    final picker = ImagePicker();
    final bild = await picker.pickImage(
      source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
      imageQuality: 90,
    );
    if (bild == null) return;
    final bytes = await bild.readAsBytes();

    Position? position;
    if (!kIsWeb) {
      setState(() => _gpsLaedt = true);
      position = await _holeGps();
      setState(() => _gpsLaedt = false);
    }

    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Foto aufgenommen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle,
                color: Colors.green.shade600, size: 56),
            const SizedBox(height: 16),
            if (position != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_on,
                      size: 16, color: Colors.green.shade600),
                  const SizedBox(width: 4),
                  Text('GPS erfasst',
                      style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w500)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${position.latitude.toStringAsFixed(5)}, '
                '${position.longitude.toStringAsFixed(5)}',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontFamily: 'monospace'),
                textAlign: TextAlign.center,
              ),
            ] else if (!kIsWeb) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_off,
                      size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 4),
                  Text('GPS nicht verfügbar',
                      style:
                          TextStyle(color: Colors.orange.shade700)),
                ],
              ),
            ] else
              Text('Datei ausgewählt',
                  style: TextStyle(color: Colors.green.shade700)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context, false),
            icon: const Icon(Icons.refresh),
            label: const Text('Nochmal'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.check),
            label: const Text('Passt ✓'),
            style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade700),
          ),
        ],
      ),
    );

    if (ok != true) {
      setState(() {
        _foto = null;
        _fotoBytes = null;
        _lat = null;
        _lng = null;
      });
      return;
    }

    setState(() {
      _fotoBytes = bytes;
      _foto = kIsWeb ? null : File(bild.path);
      if (position != null) {
        _lat = position.latitude;
        _lng = position.longitude;
      }
    });
  }

  void _zuruecksetzen() {
    _hausnummerCtrl.clear();
    _beschreibungCtrl.clear();
    _strassenSuchCtrl.clear();
    setState(() {
      _qrCode = null;
      _nummer = null;
      _foto = null;
      _fotoBytes = null;
      _lat = null;
      _lng = null;
      _strassenId = null;
      _bauartId = null;
      _laedt = false;
      _strassenListe = _allStrassen;
    });
  }

  Future<void> _speichern() async {
    if (_qrCode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Bitte zuerst den QR-Code scannen'),
            backgroundColor: Colors.orange),
      );
      return;
    }
    if (_strassenId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Bitte eine Straße auswählen'),
            backgroundColor: Colors.orange),
      );
      return;
    }
    if (_fotoBytes == null && _foto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Bitte zuerst ein Foto aufnehmen'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _laedt = true);

    try {
      await _service.anlegen(
        qrCode:       _qrCode!,
        nummer:       _nummer!,
        strassenId:   _strassenId!,
        hausnummer:   _hausnummerCtrl.text.trim().isEmpty
                          ? null : _hausnummerCtrl.text.trim(),
        beschreibung: _beschreibungCtrl.text.trim().isEmpty
                          ? null : _beschreibungCtrl.text.trim(),
        bauartId:     _bauartId,
        lat:          _lat ?? 0.0,
        lng:          _lng ?? 0.0,
        foto:         _foto,
        fotoBytes:    _fotoBytes,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$_qrCode gespeichert ✓'),
          backgroundColor: Colors.green.shade700,
        ),
      );
      _zuruecksetzen();
    } catch (e) {
      setState(() => _laedt = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Fehler: $e'),
            backgroundColor: Colors.red.shade700),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Papierkorb einmessen')),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // SCHRITT 1: QR-Code (nur mobil)
                  if (!kIsWeb) ...[
                    _schrittHeader('1', 'QR-Code scannen', _qrCode != null),
                    const SizedBox(height: 12),
                    if (_qrCode == null)
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: _scanlaeuft ? null : _qrScannen,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: Colors.green.shade400, width: 2),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: _scanlaeuft
                              ? const SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.qr_code_scanner),
                          label: const Text('QR-Code scannen',
                              style: TextStyle(fontSize: 16)),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: Colors.green.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle,
                                color: Colors.green.shade700, size: 24),
                            const SizedBox(width: 12),
                            Text(
                              _qrCode!,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade800,
                                fontFamily: 'monospace',
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () => setState(() {
                                _qrCode = null;
                                _nummer = null;
                                _foto = null;
                                _fotoBytes = null;
                                _lat = null;
                                _lng = null;
                              }),
                              child: const Text('Ändern'),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 24),
                  ],

                  // SCHRITT 2: Straße
                  _schrittHeader(kIsWeb ? '1' : '2',
                      'Straße auswählen', _strassenId != null),
                  const SizedBox(height: 12),
                  if (_laedtStrassen)
                    const LinearProgressIndicator()
                  else
                    _strassenAuswahl(),

                  const SizedBox(height: 24),

                  // SCHRITT 3: Details
                  _schrittHeader(kIsWeb ? '2' : '3',
                      'Details (optional)', false),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _hausnummerCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Hausnummer',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.home_outlined),
                    ),
                    keyboardType: TextInputType.streetAddress,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _beschreibungCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Beschreibung',
                      hintText: 'z.B. neben Bushaltestelle',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.notes),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),

                  // Bauart
                  _laedtBauarten
                      ? const LinearProgressIndicator()
                      : DropdownButtonFormField<String>(
                          value: _bauartId,
                          decoration: const InputDecoration(
                            labelText: 'Bauart (optional)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.delete_outline),
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('— keine Angabe —'),
                            ),
                            ..._bauarten.map((b) =>
                                DropdownMenuItem<String>(
                                  value: b['id'] as String,
                                  child: Text(b['beschreibung'] as String),
                                )),
                          ],
                          onChanged: (v) =>
                              setState(() => _bauartId = v),
                        ),

                  const SizedBox(height: 24),

                  // SCHRITT 4: Foto
                  _schrittHeader(
                      kIsWeb ? '3' : '4',
                      kIsWeb ? 'Foto auswählen' : 'Foto aufnehmen',
                      _fotoBytes != null || _foto != null),
                  const SizedBox(height: 12),

                  GestureDetector(
                    onTap: (kIsWeb || _qrCode != null)
                        ? _fotoAufnehmen
                        : null,
                    child: Container(
                      height: 180,
                      decoration: BoxDecoration(
                        color: (!kIsWeb && _qrCode == null)
                            ? Colors.grey.shade200
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: _fotoBytes != null
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius:
                                      BorderRadius.circular(12),
                                  child: Image.memory(_fotoBytes!,
                                      fit: BoxFit.cover),
                                ),
                                if (_lat != null)
                                  Positioned(
                                    bottom: 8, left: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${_lat!.toStringAsFixed(5)}, '
                                        '${_lng!.toStringAsFixed(5)}',
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11),
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  top: 8, right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius:
                                          BorderRadius.circular(6),
                                    ),
                                    child: Icon(
                                      kIsWeb
                                          ? Icons.upload_file
                                          : Icons.refresh,
                                      color: Colors.white, size: 18),
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
                                  size: 40,
                                  color: (!kIsWeb && _qrCode == null)
                                      ? Colors.grey.shade300
                                      : Colors.grey.shade400,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  (!kIsWeb && _qrCode == null)
                                      ? 'Zuerst QR-Code scannen'
                                      : kIsWeb
                                          ? 'Datei auswählen'
                                          : 'Foto aufnehmen',
                                  style: TextStyle(
                                    color: (!kIsWeb && _qrCode == null)
                                        ? Colors.grey.shade400
                                        : Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: _laedt ? null : _speichern,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: _laedt
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.save),
                      label: Text(
                        _laedt
                            ? 'Wird gespeichert...'
                            : 'Papierkorb speichern',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          if (_gpsLaedt)
            Container(
              color: Colors.black45,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      const Text('GPS wird ermittelt...'),
                      const SizedBox(height: 4),
                      Text('Max. 10 Sekunden',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _schrittHeader(String nr, String titel, bool erledigt) {
    return Row(
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: erledigt
                ? Colors.green.shade600
                : Colors.grey.shade300,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: erledigt
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : Text(nr,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Colors.grey.shade700)),
          ),
        ),
        const SizedBox(width: 10),
        Text(titel,
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600)),
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
          if (_strassenId != null)
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
                      _allStrassen.firstWhere(
                          (s) => s['id'] == _strassenId)['name']
                          as String,
                      style: TextStyle(
                          color: Colors.green.shade800,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _strassenId = null),
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
            height: 200,
            child: _strassenListe.isEmpty
                ? Center(
                    child: Text('Keine Treffer',
                        style: TextStyle(
                            color: Colors.grey.shade500)))
                : ListView.builder(
                    itemCount: _strassenListe.length,
                    itemBuilder: (_, i) {
                      final s = _strassenListe[i];
                      final istAusgewaehlt = s['id'] == _strassenId;
                      return ListTile(
                        dense: true,
                        selected: istAusgewaehlt,
                        selectedTileColor: Colors.green.shade50,
                        title: Text(s['name'] as String),
                        subtitle: s['stadtteil'] != null
                            ? Text(s['stadtteil'] as String,
                                style: const TextStyle(fontSize: 11))
                            : null,
                        trailing: istAusgewaehlt
                            ? Icon(Icons.check,
                                color: Colors.green.shade600,
                                size: 18)
                            : null,
                        onTap: () => setState(
                            () => _strassenId = s['id'] as int),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------
// QR-Scanner Dialog
// ----------------------------------------------------------
class _QrScannerDialog extends StatefulWidget {
  const _QrScannerDialog();

  @override
  State<_QrScannerDialog> createState() => _QrScannerDialogState();
}

class _QrScannerDialogState extends State<_QrScannerDialog> {
  final _controller = MobileScannerController();
  bool _gescannt = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('QR-Code scannen'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flashlight_on),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) async {
              if (_gescannt) return;
              final code = capture.barcodes.firstOrNull?.rawValue;
              if (code == null) return;
              _gescannt = true;
              await _controller.stop();
              if (!mounted) return;
              Navigator.pop(context, code);
            },
          ),
          Center(
            child: Container(
              width: 250, height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            bottom: 48, left: 0, right: 0,
            child: Text(
              'QR-Code-Aufkleber scannen',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}