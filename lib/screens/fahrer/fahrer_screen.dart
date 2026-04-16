import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/papierkorb.dart';
import '../../services/papierkorb_service.dart';
import '../../utils/gps_utils.dart';
import 'detail_screen.dart';

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

  Position? _aktuellePosition;
  List<Papierkorb> _alle = [];
  List<Papierkorb> _gefiltert = [];
  bool _laedt = true;
  String _geleertFilter = 'alle'; // 'alle', 'geleert', 'nicht_geleert'

  final _karteKey = GlobalKey<_KarteTabState>();
  Timer? _gpsTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _suchCtrl.addListener(_filtern);
    _initialisiereDaten();
    _starteGpsUpdates();
  }

  @override
  void dispose() {
    _gpsTimer?.cancel();
    _tabController.dispose();
    _suchCtrl.dispose();
    super.dispose();
  }

  void _starteGpsUpdates() {
    _gpsTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 2),
        );

        if (mounted) {
          setState(() {
            _aktuellePosition = position;
          });
          _karteKey.currentState?.aktualisierePosition(position);
        }
      } catch (e) {
        debugPrint("GPS-Update Fehler: $e");
      }
    });
  }

  Future<void> _ladeDaten({bool mitVollbildLaden = false}) async {
    if (mitVollbildLaden) setState(() => _laedt = true);
    try {
      final liste = await _service.alleAktiven();
      if (mounted) {
        setState(() {
          _alle = liste;
          _laedt = false;
        });
        // Wendet Suche und Geleert-Filter auf die neuen Daten an
        _filtern();
        // Aktualisiert die Marker auf der Karte
        _karteKey.currentState?.aktualisiereMarker(liste, _aktuellePosition);
      }
    } catch (e) {
      debugPrint("Fehler beim Laden: $e");
      if (mounted) setState(() => _laedt = false);
    }
  }

  Future<void> _initialisiereDaten() async {
    setState(() => _laedt = true);
    try {
      // GPS beim Start einmalig abfragen für die Kartenausrichtung
      Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      if (mounted) {
        setState(() {
          _aktuellePosition = pos;
        });
      }
    } catch (e) {
      debugPrint("GPS Initialisierungsfehler: $e");
    }
    await _ladeDaten();
  }

  Future<void> _oeffneDetails(Papierkorb pk) async {
    final res = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetailScreen(papierkorb: pk)),
    );

    if (res == true) {
      // Nach erfolgreichem Speichern Daten sofort im Hintergrund neu laden
      await _ladeDaten();
    }
  }

  void _filtern() {
    final suche = _suchCtrl.text.toLowerCase();
    setState(() {
      _gefiltert = _alle.where((pk) {
        // Text-Suche
        final matchAdresse = pk.adresse.toLowerCase().contains(suche);
        final matchNummer = pk.nummer.toString().contains(suche);
        final matchStrasse =
            (pk.strassenName ?? "").toLowerCase().contains(suche);
        final matchStadtteil =
            (pk.stadtteil ?? "").toLowerCase().contains(suche);
        final textMatch =
            matchAdresse || matchNummer || matchStrasse || matchStadtteil;

        // Geleert-Filter
        bool geleertMatch;
        switch (_geleertFilter) {
          case 'geleert':
            geleertMatch = _istHeuteGeleert(pk);
            break;
          case 'nicht_geleert':
            geleertMatch = !_istHeuteGeleert(pk);
            break;
          case 'alle':
          default:
            geleertMatch = true;
            break;
        }

        return textMatch && geleertMatch;
      }).toList();

      // Gefilterte Liste auch sortieren: 1. nach Stadtteil, 2. nach Straßennamen (wie Backoffice)
      _gefiltert.sort((a, b) {
        // Stadtteil vergleichen (null kommt am Ende)
        final stadtteilA = a.stadtteil?.toLowerCase() ?? '';
        final stadtteilB = b.stadtteil?.toLowerCase() ?? '';
        final stadtteilCompare = stadtteilA.compareTo(stadtteilB);
        if (stadtteilCompare != 0) return stadtteilCompare;

        // Bei gleichem Stadtteil nach Straße sortieren
        final strasseA = a.adresse.toLowerCase();
        final strasseB = b.adresse.toLowerCase();
        return strasseA.compareTo(strasseB);
      });
    });
  }

  bool _istHeuteGeleert(Papierkorb pk) {
    return pk.heuteGeleert;
  }

  void _geheZuPapierkorbAufKarte(Papierkorb pk) {
    _tabController.animateTo(1);
    // Erhöhter Delay für saubere Zentrierung nach Tab-Wechsel
    Future.delayed(const Duration(milliseconds: 350), () {
      _karteKey.currentState?.fokussierePapierkorb(pk);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Abholer-Tour (${_gefiltert.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.gps_fixed),
            onPressed: _initialisiereDaten,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.list), text: 'Liste'),
            Tab(icon: Icon(Icons.map), text: 'Karte'),
          ],
        ),
      ),
      body: _laedt
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildListenTab(),
                _KarteTab(
                  key: _karteKey,
                  initialeListe: _alle,
                  aktuellePosition: _aktuellePosition,
                  onMarkerTap: _oeffneDetails,
                  heuteGeleertChecker: _istHeuteGeleert,
                ),
              ],
            ),
    );
  }

  Widget _buildListenTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            controller: _suchCtrl,
            decoration: InputDecoration(
              hintText: "Suchen nach Straße, Nummer oder Stadtteil...",
              prefixIcon: const Icon(Icons.search),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'alle', label: Text('Alle')),
                ButtonSegment(value: 'nicht_geleert', label: Text('Offen')),
                ButtonSegment(value: 'geleert', label: Text('Erledigt')),
              ],
              selected: {_geleertFilter},
              onSelectionChanged: (newSelection) {
                setState(() {
                  _geleertFilter = newSelection.first;
                });
                _filtern(); // Filter neu anwenden
              },
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _gefiltert.length,
            itemBuilder: (context, i) {
              final pk = _gefiltert[i];
              final erledigt = _istHeuteGeleert(pk);
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        erledigt ? Colors.green : Colors.blue.shade100,
                    child: Text('${pk.nummer}',
                        style: TextStyle(
                            color: erledigt
                                ? Colors.white
                                : Colors.blue.shade900)),
                  ),
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${pk.strassenName ?? "Unbekannte Straße"} ${pk.hausnummer ?? ""}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      if (pk.beschreibung != null &&
                          pk.beschreibung!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2.0),
                          child: Text(
                            pk.beschreibung!,
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(pk.stadtteil ?? "Kein Stadtteil hinterlegt"),
                  trailing: erledigt
                      ? const Icon(Icons.check_circle,
                          color: Colors.green, size: 30)
                      : IconButton(
                          icon: const Icon(Icons.map_outlined),
                          onPressed: () => _geheZuPapierkorbAufKarte(pk),
                          tooltip: 'Auf Karte zeigen',
                        ),
                  onTap: () => _oeffneDetails(pk),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _KarteTab extends StatefulWidget {
  final List<Papierkorb> initialeListe;
  final Position? aktuellePosition;
  final Function(Papierkorb) onMarkerTap;
  final bool Function(Papierkorb) heuteGeleertChecker;

  const _KarteTab(
      {super.key,
      required this.initialeListe,
      this.aktuellePosition,
      required this.onMarkerTap,
      required this.heuteGeleertChecker});

  @override
  State<_KarteTab> createState() => _KarteTabState();
}

class _KarteTabState extends State<_KarteTab>
    with AutomaticKeepAliveClientMixin {
  final _mapController = MapController();
  List<Papierkorb> _markerListe = [];
  Position? _pos;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _markerListe = widget.initialeListe;
    _pos = widget.aktuellePosition;
  }

  void aktualisiereMarker(List<Papierkorb> neueListe, Position? neuePos) {
    if (mounted) {
      setState(() {
        _markerListe = neueListe;
        _pos = neuePos;
      });
    }
  }

  void aktualisierePosition(Position neuePos) {
    if (mounted) {
      setState(() {
        _pos = neuePos;
      });
    }
  }

  void fokussierePapierkorb(Papierkorb pk) {
    _mapController.move(LatLng(pk.lat, pk.lng), 18);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _pos != null
            ? LatLng(_pos!.latitude, _pos!.longitude)
            : (_markerListe.isNotEmpty
                ? LatLng(_markerListe.first.lat, _markerListe.first.lng)
                : const LatLng(50.2, 10.0)),
        initialZoom: 15,
      ),
      children: [
        // Satellitenbild als Basis
        TileLayer(
          urlTemplate:
              'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
          userAgentPackageName: 'de.eigene.app.papierkorb',
        ),
        // Halbtransparente Straßenkarte darüber
        Opacity(
          opacity: 0.4,
          child: TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'de.eigene.app.papierkorb',
          ),
        ),
        MarkerLayer(
          markers: [
            if (_pos != null)
              Marker(
                point: LatLng(_pos!.latitude, _pos!.longitude),
                width: 20,
                height: 20,
                child:
                    const Icon(Icons.my_location, color: Colors.blue, size: 25),
              ),
            ..._markerListe.map((pk) {
              final erledigt = widget.heuteGeleertChecker(pk);
              final imRadius = _pos != null &&
                  GpsUtils.istImRadius(
                      _pos!.latitude, _pos!.longitude, pk.lat, pk.lng);

              return Marker(
                point: LatLng(pk.lat, pk.lng),
                width: 70,
                height: 70,
                child: GestureDetector(
                  onTap: () => widget.onMarkerTap(pk),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        if (imRadius) // Gelber Schimmer für alle Marker im Radius
                          BoxShadow(
                            color: Colors.yellow.withOpacity(0.8),
                            blurRadius: 25,
                            spreadRadius: 8,
                          ),
                      ],
                    ),
                    child: Icon(
                      erledigt ? Icons.check_circle : Icons.delete,
                      color: erledigt
                          ? Colors.green
                          : Colors.orange, // Immer orange für normale Marker
                      size: 38,
                    ),
                  ),
                ),
              );
            }).toList(),
          ],
        ),
      ],
    );
  }
}
