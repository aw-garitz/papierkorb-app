import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/papierkorb.dart';
import '../../services/papierkorb_service.dart';
import 'meldungen_screen.dart';

class BackofficeScreen extends StatefulWidget {
  const BackofficeScreen({super.key});

  @override
  State<BackofficeScreen> createState() => _BackofficeScreenState();
}

class _BackofficeScreenState extends State<BackofficeScreen>
    with SingleTickerProviderStateMixin {
  final _service = PapierkorbService();
  final _suchCtrl = TextEditingController();
  late final TabController _tabController;
  final _karteKey = GlobalKey<_KarteTabState>();

  List<Papierkorb> _alle = [];
  List<Papierkorb> _gefiltert = [];
  bool _laedt = true;
  String _filterStatus = 'alle'; // 'alle', 'geleert', 'nicht_geleert'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
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
    if (!mounted) return;
    setState(() => _laedt = true);
    try {
      final liste = await _service.alleAktiven();
      // Sortieren: 1. nach Stadtteil, 2. nach Straßennamen
      liste.sort((a, b) {
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
      if (mounted) {
        setState(() {
          _alle = liste;
          _gefiltert = liste;
          _laedt = false;
        });
        _karteKey.currentState?.aktualisiereMarker(liste);
      }
    } catch (e) {
      if (mounted) setState(() => _laedt = false);
      debugPrint("Fehler beim Laden: $e");
    }
  }

  void _filtern() {
    final suche = _suchCtrl.text.toLowerCase();
    setState(() {
      _gefiltert = _alle.where((pk) {
        // Text-Suche
        final matchAdresse = pk.adresse.toLowerCase().contains(suche);
        final matchNummer = pk.nummer.toString().contains(suche);
        final matchStadt = (pk.stadtteil ?? "").toLowerCase().contains(suche);
        final textMatch = matchAdresse || matchNummer || matchStadt;

        // Status-Filter
        bool statusMatch = true;
        switch (_filterStatus) {
          case 'geleert':
            statusMatch = pk.heuteGeleert;
            break;
          case 'nicht_geleert':
            statusMatch = !pk.heuteGeleert;
            break;
          case 'alle':
          default:
            statusMatch = true;
            break;
        }

        return textMatch && statusMatch;
      }).toList();
    });
  }

  bool _istHeuteGeleert(Papierkorb pk) {
    return pk.heuteGeleert;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Backoffice Cockpit (${_gefiltert.length})'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _laden),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.list), text: 'Liste'),
            Tab(icon: Icon(Icons.layers), text: 'Karte'),
            Tab(icon: Icon(Icons.warning_amber), text: 'Meldungen'),
          ],
        ),
      ),
      body: _laedt
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildListe(),
                _KarteTab(
                  key: _karteKey,
                  initialeListe: _alle,
                  onMarkerTap: (pk) async {
                    final res = await Navigator.pushNamed(
                      context,
                      '/admin/edit',
                      arguments: pk,
                    );
                    if (res == true) _laden();
                  },
                  heuteGeleertChecker: _istHeuteGeleert,
                ),
                const MeldungenScreen(),
              ],
            ),
      floatingActionButton: _tabController.index == 0
          ? Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Filter-Buttons zentriert unten
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildFilterChip('alle', 'Alle'),
                      const SizedBox(width: 8),
                      _buildFilterChip('geleert', 'Geleert'),
                      const SizedBox(width: 8),
                      _buildFilterChip('nicht_geleert', 'Nicht geleert'),
                    ],
                  ),
                ),
                // FloatingActionButton rechts
                FloatingActionButton.extended(
                  onPressed: () async {
                    final res =
                        await Navigator.pushNamed(context, '/admin/einmessen');
                    if (res == true) _laden();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Neuer Papierkorb'),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ],
            )
          : null,
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _filterStatus == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _filterStatus = value;
          _filtern();
        });
      },
      backgroundColor: Colors.grey.shade200,
      selectedColor: Colors.blue.shade100,
      checkmarkColor: Colors.blue,
      labelStyle: TextStyle(
        color: isSelected ? Colors.blue.shade800 : Colors.grey.shade700,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildListe() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            controller: _suchCtrl,
            decoration: InputDecoration(
              hintText: "Suchen (Straße, Nummer, Stadtteil)...",
              prefixIcon: const Icon(Icons.search),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
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
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                elevation: 2,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      // Linke Seite: Avatar + Text
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: erledigt
                                  ? Colors.green
                                  : Colors.orange.shade100,
                              child: Text(pk.nummer.toString(),
                                  style: TextStyle(
                                      color: erledigt
                                          ? Colors.white
                                          : Colors.orange.shade900,
                                      fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      "${pk.adresse} ${pk.hausnummer ?? ''}${pk.stadtteil != null ? ' - ${pk.stadtteil}' : ''}",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                  if (pk.beschreibung != null &&
                                      pk.beschreibung!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                          "Standort: ${pk.beschreibung}",
                                          style: TextStyle(
                                              color: Colors.grey.shade700,
                                              fontSize: 13,
                                              fontStyle: FontStyle.italic)),
                                    ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        erledigt
                                            ? Icons.check_circle
                                            : Icons.pending_actions,
                                        size: 14,
                                        color: erledigt
                                            ? Colors.green
                                            : Colors.orange,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        erledigt
                                            ? "Heute bereits geleert"
                                            : "Heute noch offen",
                                        style: TextStyle(
                                          color: erledigt
                                              ? Colors.green
                                              : Colors.orange.shade800,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Rechte Seite: Buttons nebeneinander
                      Expanded(
                        flex: 2,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              onPressed: () {
                                _tabController.animateTo(1);
                                Future.delayed(
                                    const Duration(milliseconds: 350), () {
                                  _karteKey.currentState?.zoomZu(pk);
                                });
                              },
                              icon: const Icon(Icons.map_outlined, size: 24),
                              tooltip: 'Auf Karte zeigen',
                              style: IconButton.styleFrom(
                                padding: const EdgeInsets.all(10),
                                minimumSize: const Size(44, 44),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              onPressed: () async {
                                final res = await Navigator.pushNamed(
                                  context,
                                  '/admin/edit',
                                  arguments: pk,
                                );
                                if (res == true) _laden();
                              },
                              icon: const Icon(Icons.edit_note, size: 24),
                              tooltip: 'Details bearbeiten',
                              style: IconButton.styleFrom(
                                padding: const EdgeInsets.all(10),
                                minimumSize: const Size(44, 44),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Papierkorb löschen'),
                                    content: Text(
                                        'Möchten Sie Papierkorb #${pk.nummer} wirklich löschen?\n\nAdresse: ${pk.adresse} ${pk.hausnummer ?? ''}'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Abbrechen'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Colors.red,
                                          foregroundColor: Colors.white,
                                        ),
                                        child: const Text('Löschen'),
                                      ),
                                    ],
                                  ),
                                );

                                if (confirmed == true) {
                                  try {
                                    await _service.loeschen(pk.id);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              'Papierkorb erfolgreich gelöscht'),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                      _laden();
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content:
                                              Text('Fehler beim Löschen: $e'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                              icon: const Icon(Icons.delete, size: 24),
                              tooltip: 'Papierkorb löschen',
                              style: IconButton.styleFrom(
                                padding: const EdgeInsets.all(10),
                                minimumSize: const Size(44, 44),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                foregroundColor: Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
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
  final Function(Papierkorb) onMarkerTap;
  final bool Function(Papierkorb) heuteGeleertChecker;

  const _KarteTab({
    super.key,
    required this.initialeListe,
    required this.onMarkerTap,
    required this.heuteGeleertChecker,
  });

  @override
  State<_KarteTab> createState() => _KarteTabState();
}

class _KarteTabState extends State<_KarteTab>
    with AutomaticKeepAliveClientMixin {
  final _mapController = MapController();
  List<Papierkorb> _m = [];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _m = widget.initialeListe;
  }

  void aktualisiereMarker(List<Papierkorb> l) {
    if (mounted) setState(() => _m = l);
  }

  void zoomZu(Papierkorb pk) {
    _mapController.move(LatLng(pk.lat, pk.lng), 18);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _m.isNotEmpty
            ? LatLng(_m.first.lat, _m.first.lng)
            : const LatLng(50.2, 10.0),
        initialZoom: 14,
      ),
      children: [
        TileLayer(
          urlTemplate:
              'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
          userAgentPackageName: 'de.eigene.app.backoffice',
        ),
        Opacity(
          opacity: 0.6,
          child: TileLayer(
            urlTemplate:
                'https://{s}.basemaps.cartocdn.com/light_only_labels/{z}/{x}/{y}{r}.png',
            userAgentPackageName: 'de.eigene.app.backoffice',
          ),
        ),
        MarkerLayer(
          markers: _m.map((pk) {
            final erledigt = widget.heuteGeleertChecker(pk);
            return Marker(
              point: LatLng(pk.lat, pk.lng),
              width: 70,
              height: 70,
              child: GestureDetector(
                onTap: () => widget.onMarkerTap(pk),
                child: Icon(
                  erledigt ? Icons.check_circle : Icons.delete,
                  color: erledigt ? Colors.green : Colors.orange,
                  size: 38,
                  shadows: const [
                    Shadow(
                        color: Colors.black45,
                        blurRadius: 4,
                        offset: Offset(1, 1)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
