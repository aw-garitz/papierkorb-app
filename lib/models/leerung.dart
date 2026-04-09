class Leerung {
  final String id;
  final String papierkorbId;
  final String? benutzerId;
  final DateTime geleertAm;
  final String? bemerkung;
  final String? fotoUrl;
  final String? befuellung; // NEU: Füllstand
  final bool twice;
  final double? bestaetigungsLat;
  final double? bestaetigungsLng;

  const Leerung({
    required this.id,
    required this.papierkorbId,
    this.benutzerId,
    required this.geleertAm,
    this.bemerkung,
    this.fotoUrl,
    this.befuellung, // NEU: Füllstand
    required this.twice,
    this.bestaetigungsLat,
    this.bestaetigungsLng,
  });

  factory Leerung.fromJson(Map<String, dynamic> json) {
    return Leerung(
      id: json['id'] as String,
      papierkorbId: json['papierkorb_id'] as String,
      benutzerId: json['benutzer_id'] as String?,
      geleertAm: DateTime.parse(json['geleert_am'] as String),
      bemerkung: json['bemerkung'] as String?,
      fotoUrl: json['foto_url'] as String?,
      befuellung: json['befuellung'] as String?, // NEU: Füllstand auslesen
      twice: json['twice'] as bool? ?? false,
      bestaetigungsLat: (json['bestaetigungs_lat'] as num?)?.toDouble(),
      bestaetigungsLng: (json['bestaetigungs_lng'] as num?)?.toDouble(),
    );
  }
}
