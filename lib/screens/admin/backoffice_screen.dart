import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:excel/excel.dart';
import 'package:papierkorb_app/screens/admin/einmessen_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/papierkorb.dart';
import '../../models/leerung.dart';
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
  String _filterStatus = 'alle';
  int _anzahlOffenerMeldungen = 0; // Neue State-Variable für die Badge-Anzeige

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
      // Hauptdaten laden (Papierkörbe)
      final liste = await _service.alleAktiven();
      
      // Badge-Anzahl isoliert laden, damit ein Fehler hier nicht die Hauptliste blockiert
      int count = 0;
      try {
        count = await _service.getAnzahlOffenerMeldungen();
      } catch (e) {
        debugPrint("Hinweis: Badge-Anzahl konnte nicht geladen werden (evtl. DB-View unvollständig): $e");
      }

      liste.sort((a, b) {
        final stadtteilA = a.stadtteil?.toLowerCase() ?? '';
        final stadtteilB = b.stadtteil?.toLowerCase() ?? '';
        final stadtteilCompare = stadtteilA.compareTo(stadtteilB);
        if (stadtteilCompare != 0) return stadtteilCompare;
        return a.adresse.toLowerCase().compareTo(b.adresse.toLowerCase());
      });
      if (mounted) {
        setState(() {
          _alle = liste;
          _anzahlOffenerMeldungen = count;
          _laedt = false;
        });
        _filtern(); // Wendet Suche/Filter an und befüllt _gefiltert
        _karteKey.currentState?.aktualisiereMarker(_gefiltert);
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
        final textMatch = pk.adresse.toLowerCase().contains(suche) ||
            pk.nummer.toString().contains(suche) ||
            (pk.stadtteil ?? "").toLowerCase().contains(suche);

        bool statusMatch = true;
        switch (_filterStatus) {
          case 'geleert':
            statusMatch = pk.heuteGeleert;
            break;
          case 'nicht_geleert':
            statusMatch = !pk.heuteGeleert;
            break;
          default:
            statusMatch = true;
        }
        return textMatch && statusMatch;
      }).toList();
    });
  }

  bool _istHeuteGeleert(Papierkorb pk) => pk.heuteGeleert;

  // --- Excel Sheet Füll-Methoden ---

  void _fuellePapierkoerbeSheet(Sheet sheet) {
    final headers = [
      'ID',
      'Nummer',
      'Straße',
      'Hausnummer',
      'Stadtteil',
      'Bauart',
      'Status',
      'Beschreibung',
      'Latitude',
      'Longitude',
      'Erstellt am'
    ];
    for (int i = 0; i < headers.length; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(headers[i]);
    }
    for (int i = 0; i < _gefiltert.length; i++) {
      final pk = _gefiltert[i];
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1))
          .value = TextCellValue(pk.id);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1))
          .value = IntCellValue(pk.nummer);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1))
          .value = TextCellValue(pk.strassenName ?? '');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: i + 1))
          .value = TextCellValue(pk.hausnummer ?? '');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: i + 1))
          .value = TextCellValue(pk.stadtteil ?? '');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: i + 1))
          .value = TextCellValue(pk.bauart ?? '');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: i + 1))
          .value = TextCellValue(pk.status);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: i + 1))
          .value = TextCellValue(pk.beschreibung ?? '');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: i + 1))
          .value = DoubleCellValue(pk.lat);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: i + 1))
          .value = DoubleCellValue(pk.lng);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 10, rowIndex: i + 1))
          .value = TextCellValue(pk.erstelltAm.toIso8601String());
    }
  }

  Future<void> _fuelleLeerungenSheet(Sheet sheet) async {
    final headers = [
      'ID',
      'Papierkorb ID',
      'Geleert am',
      'Befüllung',
      'Bemerkung',
      'Benutzer ID'
    ];
    for (int i = 0; i < headers.length; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(headers[i]);
    }

    final response = await Supabase.instance.client
        .schema('waste')
        .from('leerungen')
        .select()
        .order('geleert_am', ascending: false)
        .limit(10000);

    final leerungen =
        (response as List).map((json) => Leerung.fromJson(json)).toList();

    for (int i = 0; i < leerungen.length; i++) {
      final l = leerungen[i];
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1))
          .value = TextCellValue(l.id);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1))
          .value = TextCellValue(l.papierkorbId);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1))
          .value = TextCellValue(l.geleertAm.toIso8601String());
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: i + 1))
          .value = TextCellValue(l.befuellung ?? '');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: i + 1))
          .value = TextCellValue(l.bemerkung ?? '');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: i + 1))
          .value = TextCellValue(l.benutzerId ?? '');
    }
  }

  // --- Export Methoden ---
  // Auf Flutter Web macht excel.save(fileName: ...) den Download direkt –
  // kein manueller Blob/Anchor nötig!

  Future<void> _exportierePapierkoerbe() async {
    try {
      final excel = Excel.createExcel();
      excel.rename('Sheet1', 'Papierkörbe');
      _fuellePapierkoerbeSheet(excel['Papierkörbe']);
      excel.save(fileName: 'Papierkörbe_Excel_P.xlsx');

      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Papierkörbe Excel heruntergeladen')),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Export: $e')),
        );
    }
  }

  Future<void> _exportiereLeerungen() async {
    try {
      final excel = Excel.createExcel();
      excel.rename('Sheet1', 'Leerungen');
      await _fuelleLeerungenSheet(excel['Leerungen']);
      excel.save(fileName: 'Papierkörbe_Excel_L.xlsx');

      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Leerungen Excel heruntergeladen')),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Leerungen-Export: $e')),
        );
    }
  }

  Future<void> _exportiereAlles() async {
    try {
      final excel = Excel.createExcel();
      excel.rename('Sheet1', 'Papierkörbe');
      _fuellePapierkoerbeSheet(excel['Papierkörbe']);
      await _fuelleLeerungenSheet(excel['Leerungen']);
      excel.save(fileName: 'Papierkörbe_Excel.xlsx');

      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backoffice Excel heruntergeladen')),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler beim Export: $e')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Backoffice Cockpit (${_gefiltert.length})'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.table_chart),
            tooltip: 'Excel Export',
            onSelected: (value) {
              if (value == 'papierkoerbe') {
                _exportierePapierkoerbe();
              } else if (value == 'leerungen') {
                _exportiereLeerungen();
              } else if (value == 'alles') {
                _exportiereAlles();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'alles',
                child: Row(children: [
                  Icon(Icons.table_chart, size: 20),
                  SizedBox(width: 8),
                  Text('Alles exportieren (2 Sheets)'),
                ]),
              ),
              const PopupMenuItem(
                value: 'papierkoerbe',
                child: Row(children: [
                  Icon(Icons.table_chart, size: 20),
                  SizedBox(width: 8),
                  Text('Nur Papierkörbe'),
                ]),
              ),
              const PopupMenuItem(
                value: 'leerungen',
                child: Row(children: [
                  Icon(Icons.table_chart, size: 20),
                  SizedBox(width: 8),
                  Text('Nur Leerungen'),
                ]),
              ),
            ],
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _laden),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(icon: Icon(Icons.list), text: 'Liste'),
            const Tab(icon: Icon(Icons.layers), text: 'Karte'),
            Tab(
              icon: Badge(
                isLabelVisible: _anzahlOffenerMeldungen > 0, // Nur anzeigen, wenn > 0
                label: Text('$_anzahlOffenerMeldungen'),
                child: const Icon(Icons.warning_amber),
              ),
              text: 'Meldungen',
            ),
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
                        context, '/admin/edit',
                        arguments: pk);
                    if (res == true) _laden();
                  },
                  heuteGeleertChecker: _istHeuteGeleert,
                ),
                MeldungenScreen(
                  onMeldungErledigt: () {
                    // Callback vom MeldungenScreen, um die Badge-Anzahl zu aktualisieren
                    _service.getAnzahlOffenerMeldungen().then((count) {
                      if (mounted) setState(() => _anzahlOffenerMeldungen = count);
                    }).catchError((e) => debugPrint("Fehler beim Badge-Update: $e"));
                  },
                ),
              ],
            ),
      floatingActionButton: _tabController.index == 0
          ? Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
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
                FloatingActionButton.extended(
                  onPressed: () async {
                    final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const EinmessenScreen()));
                    if (result == true) {
                      _laden(); // Lädt die Liste und Karte im HomeScreen sofort neu
                    }
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
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: erledigt
                                  ? Colors.green
                                  : Colors.orange.shade100,
                              child: Text(
                                pk.nummer.toString(),
                                style: TextStyle(
                                  color: erledigt
                                      ? Colors.white
                                      : Colors.orange.shade900,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
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
                                        fontSize: 16),
                                  ),
                                  if (pk.beschreibung != null &&
                                      pk.beschreibung!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        "Standort: ${pk.beschreibung}",
                                        style: TextStyle(
                                            color: Colors.grey.shade700,
                                            fontSize: 13,
                                            fontStyle: FontStyle.italic),
                                      ),
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
                                    context, '/admin/edit',
                                    arguments: pk);
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
                                            backgroundColor: Colors.green),
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
                                            backgroundColor: Colors.red),
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
                        offset: Offset(1, 1))
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
