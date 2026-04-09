class Papierkorb {
  final String id;
  final int nummer;
  final int? strassenId;
  final String? strassenName;
  final String? stadtteil;
  final String? hausnummer;
  final String adresse;
  final String? beschreibung;
  final String? bauartId;
  final String? bauart;
  final double lat;
  final double lng;
  final String? fotoUrl;
  final String status;
  final DateTime erstelltAm;
  final DateTime? letzteLeerung;
  final bool heuteGeleert;

  Papierkorb({
    required this.id,
    required this.nummer,
    this.strassenId,
    this.strassenName,
    this.stadtteil,
    this.hausnummer,
    required this.adresse,
    this.beschreibung,
    this.bauartId,
    this.bauart,
    required this.lat,
    required this.lng,
    this.fotoUrl,
    required this.status,
    required this.erstelltAm,
    this.letzteLeerung,
    this.heuteGeleert = false,
  });

  factory Papierkorb.fromJson(Map<String, dynamic> json) {
    return Papierkorb(
      id: json['id'] as String? ?? '',
      nummer: json['nummer'] as int? ?? 0,
      strassenId: json['strassen_id'] as int?,
      strassenName: json['strassen_name'] as String?,
      stadtteil: json['stadtteil'] as String?,
      hausnummer: json['hausnummer'] as String?,
      adresse: json['adresse'] as String? ??
          json['strassen_name'] as String? ??
          'Unbekannt',
      beschreibung: json['beschreibung'] as String?,
      bauartId: json['bauart_id'] as String?,
      bauart: json['bauart'] as String?,
      lat: (json['lat'] as num? ?? 0.0).toDouble(),
      lng: (json['lng'] as num? ?? 0.0).toDouble(),
      fotoUrl: json['foto_url'] as String?,
      status: json['status'] as String? ?? 'aktiv',
      erstelltAm: json['erstellt_am'] != null
          ? DateTime.parse(json['erstellt_am'] as String)
          : DateTime.now(),
      letzteLeerung: json['letzte_leerung'] != null
          ? DateTime.parse(json['letzte_leerung'] as String)
          : null,
      heuteGeleert: json['heute_geleert'] as bool? ?? false,
    );
  }
}
