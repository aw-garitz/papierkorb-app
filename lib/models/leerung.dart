class Leerung {
  final String id;
  final String papierkorbId;
  final String? benutzerId;
  final DateTime geleertAm;
  final String? bemerkung;
  final bool twice;

  const Leerung({
    required this.id,
    required this.papierkorbId,
    this.benutzerId,
    required this.geleertAm,
    this.bemerkung,
    required this.twice,
  });

  factory Leerung.fromJson(Map<String, dynamic> json) {
    return Leerung(
      id:           json['id'] as String,
      papierkorbId: json['papierkorb_id'] as String,
      benutzerId:   json['benutzer_id'] as String?,
      geleertAm:    DateTime.parse(json['geleert_am'] as String),
      bemerkung:    json['bemerkung'] as String?,
      twice:        json['twice'] as bool? ?? false,
    );
  }
}