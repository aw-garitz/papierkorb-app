import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../models/papierkorb.dart';
import '../../services/papierkorb_service.dart';

class FahrerScreen extends StatefulWidget {
  const FahrerScreen({super.key});

  @override
  State<FahrerScreen> createState() => _FahrerScreenState();
}

class _FahrerScreenState extends State<FahrerScreen>
    with SingleTickerProviderStateMixin {
  final _service = PapierkorbService();
  final _suchCtrl = TextEditingController();
  late final TabController _tabController;

  final _scannerController = MobileScannerController();
  bool _verarbeitung = false;

  List<Papierkorb> _alle = [];
  List<Papierkorb> _gefiltert = [];
  bool _laedt = true;

  final _karteKey = GlobalKey<_KarteTabState>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _suchCtrl.addListener(_filtern);
    _laden();

    _tabController.addListener(() {
      if (_tabController.index == 0) {
        _scannerController.start();
      } else {
        _scannerController.stop();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _suchCtrl.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _laden() async {
    try {
      final liste = await _service.alleAktiven();
      setState(() {
        _alle = liste;
        _gefiltert = liste;
        _laedt = false;
      });
      _karteKey.currentState?.aktualisiereMarker(liste);
    } catch (e) {
      setState(() => _laedt = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }

  void _filtern() {
    final suche = _suchCtrl.text.toLowerCase();
    setState(() {
      _gefiltert = suche.isEmpty
          ? _alle
          : _alle.where((pk) {
              final strasse = (pk.strasseName ?? '').toLowerCase();
              final beschreibung = (pk.beschreibung ?? '').toLowerCase();
              return strasse.contains(suche) ||
                  beschreibung.contains(suche) ||
                  pk.qrCode.toLowerCase().contains(suche);
            }).toList();
    });
  }

  void _zoomAufMarker(Papierkorb pk) {
    _tabController.animateTo(2);
    Future.delayed(const Duration(milliseconds: 300), () {
      _karteKey.currentState?.zoomZu(pk);
    });
  }

  void _oeffneDetail(Papierkorb pk) {
    Navigator.pushNamed(
      context,
      '/fahrer/detail',
      arguments: {'papierkorb': pk, 'readonly': true},
    );
  }

  Future<void> _onQrGescannt(BarcodeCapture capture) async {
    if (_verarbeitung) return;
    final qrCode = capture.barcodes.firstOrNull?.rawValue;
    if (qrCode == null) return;

    if (!RegExp(r'^pk_\d{4}$').hasMatch(qrCode)) {
      _zeigeFehler('Ungültiger QR-Code: $qrCode');
      return;
    }

    setState(() => _verarbeitung = true);
    await _scannerController.stop();

    try {
      final papierkorb = await _service.perQrCode(qrCode);
      if (!mounted) return;

      if (papierkorb == null) {
        _zeigeFehler('$qrCode nicht gefunden');
        await _scannerController.start();
        setState(() => _verarbeitung = false);
        return;
      }

      await Navigator.pushNamed(
        context,
        '/fahrer/detail',
        arguments: {'papierkorb': papierkorb, 'readonly': true},
      );

      await _scannerController.start();
      setState(() => _verarbeitung = false);
    } catch (e) {
      if (!mounted) return;
      _zeigeFehler('Fehler: $e');
      await _scannerController.start();
      setState(() => _verarbeitung = false);
    }
  }

  void _zeigeFehler(String nachricht) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(nachricht),
          backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Papierkörbe'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _laedt = true);
              _laden();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'Scanner'),
            Tab(icon: Icon(Icons.list), text: 'Liste'),
            Tab(icon: Icon(Icons.map_outlined), text: 'Karte'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildScanner(),
          _buildListe(),
          _KarteTab(
            key: _karteKey,
            papierkorbListe: _alle,
            onDetail: _oeffneDetail,
          ),
        ],
      ),
    );
  }

  Widget _buildScanner() {
    return Stack(
      children: [
        MobileScanner(
          controller: _scannerController,
          onDetect: _onQrGescannt,
        ),
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        Positioned(
          bottom: 48, left: 0, right: 0,
          child: Text(
            'QR-Code in den Rahmen halten',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 16),
          ),
        ),
        Positioned(
          top: 16, right: 16,
          child: IconButton(
            icon: const Icon(Icons.flashlight_on, color: Colors.white),
            onPressed: () => _scannerController.toggleTorch(),
          ),
        ),
        if (_verarbeitung)
          Container(
            color: Colors.black54,
            child: const Center(
                child: CircularProgressIndicator(color: Colors.white)),
          ),
      ],
    );
  }

  Widget _buildListe() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _suchCtrl,
            decoration: InputDecoration(
              hintText:
                  'Nach Straße, Beschreibung oder QR-Code suchen...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _suchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _suchCtrl.clear();
                        _filtern();
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
            ),
          ),
        ),
        if (_suchCtrl.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${_gefiltert.length} Treffer',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600)),
            ),
          ),
        Expanded(
          child: _laedt
              ? const Center(child: CircularProgressIndicator())
              : _gefiltert.isEmpty
                  ? Center(
                      child: Text('Keine Papierkörbe gefunden',
                          style: TextStyle(
                              color: Colors.grey.shade500)))
                  : ListView.separated(
                      itemCount: _gefiltert.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final pk = _gefiltert[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green.shade100,
                            child: Text(
                              '${pk.nummer}',
                              style: TextStyle(
                                color: Colors.green.shade800,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          title: Text(pk.adresse),
                          subtitle: pk.beschreibung != null
                              ? Text(pk.beschreibung!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12))
                              : null,
                          trailing: const Icon(Icons.my_location,
                              color: Colors.grey, size: 18),
                          onTap: () => _zoomAufMarker(pk),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------
// Karten-Tab mit AutomaticKeepAliveClientMixin
// ----------------------------------------------------------
class _KarteTab extends StatefulWidget {
  final List<Papierkorb> papierkorbListe;
  final void Function(Papierkorb) onDetail;

  const _KarteTab({
    super.key,
    required this.papierkorbListe,
    required this.onDetail,
  });

  @override
  State<_KarteTab> createState() => _KarteTabState();
}

class _KarteTabState extends State<_KarteTab>
    with AutomaticKeepAliveClientMixin {
  final _mapController = MapController();
  late List<Papierkorb> _papierkorbListe;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _papierkorbListe = widget.papierkorbListe;
  }

  void aktualisiereMarker(List<Papierkorb> liste) {
    setState(() => _papierkorbListe = liste);
  }

  void zoomZu(Papierkorb pk) {
    _mapController.move(LatLng(pk.lat, pk.lng), 19);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Pflicht bei AutomaticKeepAliveClientMixin

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _papierkorbListe.isNotEmpty
            ? LatLng(
                _papierkorbListe.first.lat, _papierkorbListe.first.lng)
            : const LatLng(50.2007, 10.0760),
        initialZoom: 14,
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
          userAgentPackageName: 'de.stadt.papierkorb_app',
        ),
        Opacity(
          opacity: 0.4,
          child: TileLayer(
            urlTemplate:
                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'de.stadt.papierkorb_app',
          ),
        ),
        MarkerLayer(
          markers: _papierkorbListe.map((pk) {
            return Marker(
              point: LatLng(pk.lat, pk.lng),
              width: 40,
              height: 40,
              child: GestureDetector(
                onTap: () => widget.onDetail(pk),
                child: Tooltip(
                  message: '${pk.qrCode} – ${pk.adresse}',
                  child: const Icon(
                    Icons.delete,
                    color: Colors.orange,
                    size: 30,
                    shadows: [
                      Shadow(
                          color: Colors.black45,
                          blurRadius: 4,
                          offset: Offset(1, 1)),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}