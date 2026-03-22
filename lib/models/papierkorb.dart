class Papierkorb {
  final String id;
  final int nummer;
  final String qrCode;
  final int? strassenId;
  final String? strasseName;
  final String? stadtteil;
  final String? hausnummer;
  final String? beschreibung;
  final String? bauartId;
  final String? bauart;
  final double lat;
  final double lng;
  final String? fotoUrl;
  final String status;
  final DateTime erstelltAm;
  final DateTime? letzteLeering;

  const Papierkorb({
    required this.id,
    required this.nummer,
    required this.qrCode,
    this.strassenId,
    this.strasseName,
    this.stadtteil,
    this.hausnummer,
    this.beschreibung,
    this.bauartId,
    this.bauart,
    required this.lat,
    required this.lng,
    this.fotoUrl,
    required this.status,
    required this.erstelltAm,
    this.letzteLeering,
  });

  factory Papierkorb.fromJson(Map<String, dynamic> json) {
    return Papierkorb(
      id:           json['id'] as String,
      nummer:       json['nummer'] as int,
      qrCode:       json['qr_code'] as String,
      strassenId:   json['strassen_id'] as int?,
      strasseName:  json['strassen_name'] as String?,
      stadtteil:    json['stadtteil'] as String?,
      hausnummer:   json['hausnummer'] as String?,
      beschreibung: json['beschreibung'] as String?,
      bauartId:     json['bauart_id'] as String?,
      bauart:       json['bauart'] as String?,
      lat:          (json['lat'] as num).toDouble(),
      lng:          (json['lng'] as num).toDouble(),
      fotoUrl:      json['foto_url'] as String?,
      status:       json['status'] as String,
      erstelltAm:   DateTime.parse(json['erstellt_am'] as String),
      letzteLeering: json['letzte_leerung'] != null
          ? DateTime.parse(json['letzte_leerung'] as String)
          : null,
    );
  }

  String get adresse {
    final teile = [strasseName, hausnummer].whereType<String>().join(' ');
    return teile.isNotEmpty ? teile : qrCode;
  }

  int? get tageSeitletzterLeerung {
    if (letzteLeering == null) return null;
    return DateTime.now().difference(letzteLeering!).inDays;
  }
}