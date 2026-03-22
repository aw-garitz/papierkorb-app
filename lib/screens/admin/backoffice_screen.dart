import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/papierkorb.dart';
import '../../services/papierkorb_service.dart';
import 'qr_generator_screen.dart';
import 'meldungen_screen.dart';

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
  int _meldungsAnzahl = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging &&
          _tabController.previousIndex == 3) {
        _laden();
      }
    });
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
      final meldungen = await _service.meldungen();
      setState(() {
        _alle = liste;
        _gefiltert = liste;
        _meldungsAnzahl = meldungen.length;
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
              final bauart = (pk.bauart ?? '').toLowerCase();
              return strasse.contains(suche) ||
                  beschreibung.contains(suche) ||
                  qrCode.contains(suche) ||
                  bauart.contains(suche);
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
      arguments: {'papierkorb': pk, 'readonly': false},
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
            content: Text('Kein Papierkorb in der Nähe — näher heranzoomen')),
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
            backgroundColor: Colors.green),
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
          tabs: [
            const Tab(icon: Icon(Icons.list), text: 'Liste'),
            const Tab(icon: Icon(Icons.map_outlined), text: 'Karte'),
            const Tab(icon: Icon(Icons.qr_code), text: 'QR-Codes'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_outlined, size: 18),
                  const SizedBox(width: 4),
                  const Text('Meldungen'),
                  if (_meldungsAnzahl > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$_meldungsAnzahl',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
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
                const MeldungenScreen(),
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
              hintText:
                  'Nach Straße, Beschreibung, Bauart oder QR-Code suchen...',
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
          child: _gefiltert.isEmpty
              ? Center(
                  child: Text('Keine Papierkörbe gefunden',
                      style: TextStyle(color: Colors.grey.shade500)))
              : ListView.separated(
                  itemCount: _gefiltert.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final pk = _gefiltert[i];

                    // Subtitle: Beschreibung · Bauart
                    final subteileParts = [
                      if (pk.beschreibung != null) pk.beschreibung!,
                      if (pk.bauart != null) pk.bauart!,
                    ];
                    final subtitel = subteileParts.join(' · ');

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: pk.status == 'aktiv'
                            ? Colors.green.shade100
                            : pk.status == 'defekt'
                                ? Colors.orange.shade100
                                : Colors.red.shade100,
                        child: Text(
                          '${pk.nummer}',
                          style: TextStyle(
                            color: pk.status == 'aktiv'
                                ? Colors.green.shade800
                                : pk.status == 'defekt'
                                    ? Colors.orange.shade800
                                    : Colors.red.shade800,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      title: Text(pk.adresse),
                      subtitle: subtitel.isNotEmpty
                          ? Text(
                              subtitel,
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
        TileLayer(
          urlTemplate:
              'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
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
                    size: 36,
                    color: pk.status == 'aktiv'
                        ? Colors.orange
                        : pk.status == 'defekt'
                            ? Colors.red
                            : Colors.grey,
                    shadows: const [
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