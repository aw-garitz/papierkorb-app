import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../models/papierkorb.dart';
import '../models/leerung.dart';

class PapierkorbService {
  // ----------------------------------------------------------
  // PAPIERKÖRBE LADEN
  // ----------------------------------------------------------

  Future<List<Papierkorb>> alleAktiven() async {
    // Zuerst Papierkörbe laden
    final papierkoerbeResponse = await supabase
        .schema('waste')
        .from('papierkörbe')
        .select()
        .inFilter('status', ['ok', 'defekt', 'schmutzig']).order('nummer');

    // Dann Straßennamen laden
    final strassenResponse = await supabase
        .schema('public')
        .from('strassen')
        .select('id, name, stadtteil');

    // Dann heutige Leerungen laden
    final heute = DateTime.now();
    final leerungenResponse = await supabase
        .schema('waste')
        .from('leerungen')
        .select('papierkorb_id')
        .gte('geleert_am',
            DateTime(heute.year, heute.month, heute.day).toIso8601String())
        .lt('geleert_am',
            DateTime(heute.year, heute.month, heute.day + 1).toIso8601String());

    final strassenMap = <int, Map<String, dynamic>>{};
    for (final strasse in strassenResponse as List) {
      strassenMap[strasse['id'] as int] = strasse as Map<String, dynamic>;
    }

    final heuteGeleerteIds = <String>{};
    for (final leerung in leerungenResponse as List) {
      heuteGeleerteIds.add(leerung['papierkorb_id'] as String);
    }

    // Straßennamen und Leerungsstatus zuordnen
    return (papierkoerbeResponse as List).map((json) {
      final strassenId = json['strassen_id'] as int?;
      final strasse = strassenId != null ? strassenMap[strassenId] : null;
      final papierkorbId = json['id'] as String;

      return Papierkorb.fromJson({
        ...json,
        'strassen_name': strasse?['name'],
        'stadtteil': strasse?['stadtteil'],
        'heute_geleert': heuteGeleerteIds.contains(papierkorbId),
      });
    }).toList();
  }

  Future<Papierkorb?> perId(String id) async {
    // Zuerst Papierkorb laden
    final papierkorbResponse = await supabase
        .schema('waste')
        .from('papierkörbe')
        .select()
        .eq('id', id)
        .maybeSingle();

    if (papierkorbResponse == null) return null;

    // Dann Straßennamen laden, falls strassen_id vorhanden
    final strassenId = papierkorbResponse['strassen_id'] as int?;
    Map<String, dynamic>? strasse;

    if (strassenId != null) {
      final strassenResponse = await supabase
          .schema('public')
          .from('strassen')
          .select('name, stadtteil')
          .eq('id', strassenId)
          .maybeSingle();

      strasse = strassenResponse;
    }

    return Papierkorb.fromJson({
      ...papierkorbResponse,
      'strassen_name': strasse?['name'],
      'stadtteil': strasse?['stadtteil'],
    });
  }

  // ----------------------------------------------------------
  // LEERUNGEN
  // ----------------------------------------------------------

  Future<List<Leerung>> leerungenFuer(String papierkorbId,
      {int limit = 10}) async {
    final response = await supabase
        .schema('waste')
        .from('leerungen')
        .select()
        .eq('papierkorb_id', papierkorbId)
        .order('geleert_am', ascending: false)
        .limit(limit);

    return (response as List).map((json) => Leerung.fromJson(json)).toList();
  }

  Future<void> leerungBestaetigen({
    required String papierkorbId,
    String? bemerkung,
    File? foto,
    Uint8List? fotoBytes,
    String? neuerStatus,
    String? befuellung, // NEU: Füllstand
    double? bestaetigungsLat,
    double? bestaetigungsLng,
  }) async {
    String? fotoUrl;

    // Foto-Name basiert nun auf UUID und Zeitstempel
    final String dateiName =
        "${papierkorbId}_${DateTime.now().millisecondsSinceEpoch}.jpg";

    if (fotoBytes != null || foto != null) {
      fotoUrl = await _komprimierenUndHochladen(
        pfad: 'leerungen/$dateiName',
        foto: foto,
        fotoBytes: fotoBytes,
      );
    }

    await supabase.schema('waste').from('leerungen').insert({
      'papierkorb_id': papierkorbId,
      'bemerkung': bemerkung,
      'foto_url': fotoUrl,
      'befuellung': befuellung, // NEU: Füllstand speichern
      'bestaetigungs_lat': bestaetigungsLat,
      'bestaetigungs_lng': bestaetigungsLng,
      'geleert_am': DateTime.now().toIso8601String(),
    });

    if (neuerStatus != null) {
      await supabase
          .schema('waste')
          .from('papierkörbe')
          .update({'status': neuerStatus}).eq('id', papierkorbId);
    }
  }

  // ----------------------------------------------------------
  // MELDUNGEN
  // ----------------------------------------------------------

  Future<List<Map<String, dynamic>>> meldungen() async {
    final response =
        await supabase.schema('waste').from('meldungen_view').select();
    return List<Map<String, dynamic>>.from(response);
  }

  /// Ruft die Anzahl der Meldungen ab, die eine Bemerkung oder ein Foto haben
  /// und noch nicht als erledigt markiert wurden.
  Future<int> getAnzahlOffenerMeldungen() async {
    try {
      final response = await supabase
          .schema('waste')
          .from('meldungen_view')
          .select('id')
          .eq('meldung_erledigt', false);
      
      return (response as List).length;
    } catch (e) {
      
      return 0; // Im Fehlerfall 0 zurückgeben, damit die App nicht abstürzt
    }
  }

  Future<void> meldungErledigen({
    required String typ,
    required String id,
    required String papierkorbId,
    String? bemerkung,
  }) async {
    if (typ == 'leerung') {
      await supabase
          .schema('waste')
          .from('leerungen')
          .update({
            'meldung_erledigt': true,
            'meldung_bemerkung': bemerkung,
          }).eq('id', id);
    }
    await supabase
        .schema('waste')
        .from('papierkörbe')
        .update({'status': 'ok'}).eq('id', papierkorbId);
  }

  // ----------------------------------------------------------
  // EXPORT
  // ----------------------------------------------------------

  Future<List<Map<String, dynamic>>> exportDaten() async {
    final response =
        await supabase.schema('waste').from('papierkörbe_export_view').select();
    return List<Map<String, dynamic>>.from(response);
  }

  // ----------------------------------------------------------
  // ADMIN: ANLEGEN & AKTUALISIEREN
  // ----------------------------------------------------------

  Future<Papierkorb> anlegen({
    required int nummer,
    required int strassenId,
    String? hausnummer,
    String? beschreibung,
    String? bauartId,
    required double lat,
    required double lng,
    File? foto,
    Uint8List? fotoBytes,
  }) async {
    String? fotoUrl;
    // Wir nutzen die Nummer für den ersten Foto-Upload-Pfad
    if (fotoBytes != null || foto != null) {
      fotoUrl = await _komprimierenUndHochladen(
        pfad: 'papierkoerbe/pk_$nummer.jpg',
        foto: foto,
        fotoBytes: fotoBytes,
      );
    }

    final insertRes = await supabase
        .schema('waste')
        .from('papierkörbe')
        .insert({
          'nummer': nummer,
          'strassen_id': strassenId,
          'hausnummer': hausnummer,
          'beschreibung': beschreibung,
          'bauart_id': bauartId,
          'lat': lat,
          'lng': lng,
          'status': 'ok', // Einzig gültiger Status für neue Papierkörbe
          'foto_url': fotoUrl,
          'qr_code':
              'PK-$nummer-${DateTime.now().millisecondsSinceEpoch}', // Eindeutiger QR-Code
        })
        .select()
        .single();

    return Papierkorb.fromJson(insertRes);
  }

  Future<Papierkorb> aktualisieren({
    required String id,
    required int strassenId,
    String? hausnummer,
    String? beschreibung,
    String? bauartId,
    required double lat,
    required double lng,
    required String status,
    File? neuesFoto,
    Uint8List? neuesFotoBytes,
  }) async {
    String? fotoUrl;
    if (neuesFotoBytes != null || neuesFoto != null) {
      fotoUrl = await _komprimierenUndHochladen(
        pfad: 'papierkoerbe/pk_$id.jpg',
        foto: neuesFoto,
        fotoBytes: neuesFotoBytes,
      );
    }

    final updates = <String, dynamic>{
      'strassen_id': strassenId,
      'hausnummer': hausnummer,
      'beschreibung': beschreibung,
      'bauart_id': bauartId,
      'lat': lat,
      'lng': lng,
      'status': status,
      'geodaten_geändert_am': DateTime.now().toIso8601String(),
    };

    if (fotoUrl != null) updates['foto_url'] = fotoUrl;

    await supabase
        .schema('waste')
        .from('papierkörbe')
        .update(updates)
        .eq('id', id);

    final res = await supabase
        .schema('waste')
        .from('papierkörbe')
        .select()
        .eq('id', id)
        .single();
    return Papierkorb.fromJson(res);
  }

  Future<void> loeschen(String id) async {
    await supabase.schema('waste').from('papierkörbe').delete().eq('id', id);
  }

  /// Läuft einmalig über alle bestehenden Einträge, lädt die Bilder, 
  /// komprimiert sie und überschreibt die Originale im Storage.
  Future<int> optimiereBestehendeBilder() async {
    int anzahl = 0;

    // 1. Alle Einträge mit Fotos holen (Leerungen)
    final leerungen = await supabase.schema('waste')
        .from('leerungen')
        .select('id, foto_url')
        .not('foto_url', 'is', null);

    for (final l in leerungen as List) {
      final url = l['foto_url'] as String;
      if (url.isEmpty || !url.contains('papierkorb-fotos/')) continue;

      try {
        // Bild herunterladen
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          final bytes = response.bodyBytes;
          
          // Pfad aus der URL extrahieren (alles nach 'papierkorb-fotos/')
          final pfad = url.split('papierkorb-fotos/').last.split('?').first;

          // Mit der bereits existierenden Methode neu hochladen (überschreibt dank upsert: true)
          await _komprimierenUndHochladen(
            pfad: pfad,
            fotoBytes: bytes,
          );
          anzahl++;
        }
      } catch (e) {
        debugPrint("Fehler bei Optimierung von Leerung ${l['id']}: $e");
      }
    }

    // 2. Das Gleiche für die Stammdaten der Papierkörbe
    final pks = await supabase.schema('waste')
        .from('papierkörbe')
        .select('id, foto_url')
        .not('foto_url', 'is', null);

    for (final pk in pks as List) {
      final url = pk['foto_url'] as String;
      if (url.isEmpty || !url.contains('papierkorb-fotos/')) continue;

      try {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          final bytes = response.bodyBytes;
          final pfad = url.split('papierkorb-fotos/').last.split('?').first;
          await _komprimierenUndHochladen(
            pfad: pfad,
            fotoBytes: bytes,
          );
          anzahl++;
        }
      } catch (e) {
        debugPrint("Fehler bei Optimierung von Papierkorb ${pk['id']}: $e");
      }
    }

    return anzahl;
  }

  // ----------------------------------------------------------
  // HILFSMETHODEN
  // ----------------------------------------------------------

  /// Hilfsmethode zur Komprimierung und zum Upload.
  /// Skaliert Bilder auf max 1024px und reduziert die Qualität auf ca. 50%.
  Future<String> _komprimierenUndHochladen({
    required String pfad,
    File? foto,
    Uint8List? fotoBytes,
  }) async {
    Uint8List data;

    if (kIsWeb) {
      // Auf Web funktioniert flutter_image_compress nicht,
      // daher laden wir die Rohdaten (ImagePicker übernimmt hier die Skalierung).
      data = fotoBytes ?? await foto!.readAsBytes();
    } else {
      // Mobile Komprimierung
      final result = foto != null
          ? await FlutterImageCompress.compressWithFile(
              foto.absolute.path,
              quality: 50,
              minWidth: 1024,
              minHeight: 1024,
            )
          : await FlutterImageCompress.compressWithList(
              fotoBytes!,
              quality: 50,
              minWidth: 1024,
              minHeight: 1024,
            );

      if (result == null) throw Exception('Komprimierung fehlgeschlagen');
      data = result;
    }

    await supabase.storage.from('papierkorb-fotos').uploadBinary(
          pfad,
          data,
          fileOptions:
              const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
    return supabase.storage.from('papierkorb-fotos').getPublicUrl(pfad);
  }

  Future<List<Map<String, dynamic>>> strassen() async {
    final response = await supabase
        .from('strassen')
        .select('id, name, stadtteil')
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> bauarten() async {
    final response = await supabase
        .from('bauart')
        .select('id, beschreibung')
        .order('beschreibung');
    return List<Map<String, dynamic>>.from(response);
  }
}
