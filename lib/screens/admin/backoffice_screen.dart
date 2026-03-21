import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/papierkorb.dart';
import '../../services/papierkorb_service.dart';
import 'qr_generator_screen.dart';

class BackofficeScreen extends StatefulWidget {
  const BackofficeScreen({super.key});

  @override
  State<BackofficeScreen> createState() => _BackofficeScreenState();
}

class _BackofficeScreenState extends State<BackofficeScreen>
    with SingleTickerProviderStateMixin {
  final _service = PapierkorbService();
  final _mapController = MapController();
  final _suchCtrl = TextEditingController();
  late final TabController _tabController;

  List<Papierkorb> _alle = [];
  List<Papierkorb> _gefiltert = [];
  bool _laedt = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _suchCtrl.addListener(_filtern);
    _laden();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _suchCtrl.dispose();
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
    } catch (e) {
      setState(() => _laedt = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Laden: $e')),
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
            final qrCode = pk.qrCode.toLowerCase();
            return strasse.contains(suche) ||
                   beschreibung.contains(suche) ||
                   qrCode.contains(suche);
          }).toList();
  });
}

  void _zoomAufMarker(Papierkorb pk) {
    _tabController.animateTo(1);
    Future.delayed(const Duration(milliseconds: 300), () {
      _mapController.move(LatLng(pk.lat, pk.lng), 19);
    });
  }

  void _oeffneDetail(Papierkorb pk) {
    Navigator.pushNamed(
      context,
      '/fahrer/detail',
      arguments: {'papierkorb': pk, 'readonly': true},
    );
  }

  Future<void> _onKarteLongPress(TapPosition _, LatLng punkt) async {
    Papierkorb? naechster;
    double minAbstand = double.infinity;
    const distance = Distance();

    for (final pk in _alle) {
      final d = distance(LatLng(pk.lat, pk.lng), punkt);
      if (d < minAbstand && d < 50) {
        minAbstand = d;
        naechster = pk;
      }
    }

    if (naechster == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kein Papierkorb in der Nähe — näher heranzoomen'),
        ),
      );
      return;
    }

    final bestaetigt = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${naechster!.qrCode} verschieben?'),
        content: Text(
          'Neue Position:\n'
          '${punkt.latitude.toStringAsFixed(6)}, '
          '${punkt.longitude.toStringAsFixed(6)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Verschieben'),
          ),
        ],
      ),
    );

    if (bestaetigt != true) return;

    try {
      await _service.geodatenAktualisieren(
        id:  naechster.id,
        lat: punkt.latitude,
        lng: punkt.longitude,
      );
      await _laden();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Position aktualisiert ✓'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Backoffice (${_alle.length} Körbe)'),
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
            Tab(icon: Icon(Icons.list), text: 'Liste'),
            Tab(icon: Icon(Icons.map_outlined), text: 'Karte'),
            Tab(icon: Icon(Icons.qr_code), text: 'QR-Codes'),
          ],
        ),
      ),
      body: _laedt
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildListe(),
                _buildKarte(),
                const QrGeneratorScreen(),
              ],
            ),
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
              hintText: 'Nach Straße, Beschreibung oder QR-Code suchen...',
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
                borderRadius: BorderRadius.circular(12),
              ),
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
              child: Text(
                '${_gefiltert.length} Treffer',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          ),
        Expanded(
          child: _gefiltert.isEmpty
              ? Center(
                  child: Text(
                    'Keine Papierkörbe gefunden',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                )
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
                          ? Text(
                              pk.beschreibung!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            )
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

  Widget _buildKarte() {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _alle.isNotEmpty
            ? LatLng(_alle.first.lat, _alle.first.lng)
            : const LatLng(50.2007, 10.0760),
        initialZoom: 14,
        onLongPress: _onKarteLongPress,
      ),
      children: [
        // CartoDB Voyager — schöner, detaillierter als Standard-OSM
        TileLayer(
  urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
  userAgentPackageName: 'de.stadt.papierkorb_app',
),
Opacity(
  opacity: 0.4,
  child: TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    userAgentPackageName: 'de.stadt.papierkorb_app',
  ),
),
        MarkerLayer(
          markers: _alle.map((pk) {
            return Marker(
              point: LatLng(pk.lat, pk.lng),
              width: 40,
              height: 40,
              child: GestureDetector(
                onTap: () => _oeffneDetail(pk),
                child: Tooltip(
                  message: '${pk.qrCode} – ${pk.adresse}',
                  child: Icon(
                    Icons.delete,
                    size: 34,
                    color: Colors.yellow.shade700,
                    shadows: const [
                      Shadow(
                        color: Colors.black45,
                        blurRadius: 4,
                        offset: Offset(1, 1),
                      ),
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