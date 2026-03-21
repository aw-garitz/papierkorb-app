import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../models/papierkorb.dart';
import '../models/leerung.dart';

class PapierkorbService {

  // ----------------------------------------------------------
  // PAPIERKÖRBE LADEN
  // ----------------------------------------------------------

  Future<List<Papierkorb>> alleAktiven() async {
    final response = await supabase
        .from('papierkörbe_view')
        .select()
        .eq('status', 'aktiv')
        .order('nummer');

    return (response as List)
        .map((json) => Papierkorb.fromJson(json))
        .toList();
  }

  Future<Papierkorb?> perQrCode(String qrCode) async {
    final response = await supabase
        .from('papierkörbe_view')
        .select()
        .eq('qr_code', qrCode)
        .maybeSingle();

    if (response == null) return null;
    return Papierkorb.fromJson(response);
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

    return (response as List)
        .map((json) => Leerung.fromJson(json))
        .toList();
  }

  // Leerung bestätigen mit optionalem Foto, Bemerkung und Status
  Future<void> leerungBestaetigen({
    required String papierkorbId,
    String? bemerkung,
    File? foto,
    String? neuerStatus,  // null = Status unverändert
    required String papierkorbQrCode,
  }) async {
    String? fotoUrl;

    // Foto hochladen falls vorhanden
    if (foto != null) {
      fotoUrl = await leerungFotoHochladen(foto, papierkorbQrCode);
    }

    // Leerung speichern
    await supabase
        .schema('waste')
        .from('leerungen')
        .insert({
          'papierkorb_id': papierkorbId,
          'bemerkung':     bemerkung,
          'foto_url':      fotoUrl,
        });

    // Status aktualisieren falls geändert
    if (neuerStatus != null) {
      await supabase
          .schema('waste')
          .from('papierkörbe')
          .update({'status': neuerStatus})
          .eq('id', papierkorbId);
    }
  }

  // Foto für Leerung hochladen
  Future<String> leerungFotoHochladen(File foto, String qrCode) async {
    final komprimiert = await FlutterImageCompress.compressWithFile(
      foto.absolute.path,
      quality: 55,
      minWidth: 800,
      minHeight: 800,
    );

    if (komprimiert == null) {
      throw Exception('Foto-Komprimierung fehlgeschlagen');
    }

    // Dateiname: qrCode + Timestamp damit mehrere Fotos möglich
    final ts = DateTime.now().millisecondsSinceEpoch;
    final dateiname = 'leerungen/${qrCode}_$ts.jpg';

    await supabase.storage
        .from('papierkorb-fotos')
        .uploadBinary(
          dateiname,
          komprimiert,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: false,
          ),
        );

    return supabase.storage
        .from('papierkorb-fotos')
        .getPublicUrl(dateiname);
  }

  // ----------------------------------------------------------
  // ADMIN: PAPIERKORB ANLEGEN
  // ----------------------------------------------------------

  Future<Papierkorb> anlegen({
    required String qrCode,
    required int nummer,
    required int strassenId,
    String? hausnummer,
    String? beschreibung,
    required double lat,
    required double lng,
    File? foto,
  }) async {
    String? fotoUrl;
    if (foto != null) {
      fotoUrl = await fotoHochladen(foto, qrCode);
    }

    await supabase
        .schema('waste')
        .from('papierkörbe')
        .insert({
          'qr_code':      qrCode,
          'nummer':       nummer,
          'strassen_id':  strassenId,
          'hausnummer':   hausnummer,
          'beschreibung': beschreibung,
          'lat':          lat,
          'lng':          lng,
          'foto_url':     fotoUrl,
        });

    final response = await supabase
        .from('papierkörbe_view')
        .select()
        .eq('qr_code', qrCode)
        .single();

    return Papierkorb.fromJson(response);
  }

  // ----------------------------------------------------------
  // ADMIN: PAPIERKORB AKTUALISIEREN
  // ----------------------------------------------------------

  Future<Papierkorb> aktualisieren({
    required String id,
    required String qrCode,
    required int strassenId,
    String? hausnummer,
    String? beschreibung,
    required double lat,
    required double lng,
    required String status,
    File? neuesFoto,
  }) async {
    String? fotoUrl;
    if (neuesFoto != null) {
      fotoUrl = await fotoHochladen(neuesFoto, qrCode);
    }

    final updates = <String, dynamic>{
      'strassen_id':  strassenId,
      'hausnummer':   hausnummer,
      'beschreibung': beschreibung,
      'lat':          lat,
      'lng':          lng,
      'status':       status,
      'geodaten_geändert_am': DateTime.now().toIso8601String(),
    };

    if (fotoUrl != null) {
      updates['foto_url'] = fotoUrl;
    }

    await supabase
        .schema('waste')
        .from('papierkörbe')
        .update(updates)
        .eq('id', id);

    final response = await supabase
        .from('papierkörbe_view')
        .select()
        .eq('id', id)
        .single();

    return Papierkorb.fromJson(response);
  }

  Future<void> geodatenAktualisieren({
    required String id,
    required double lat,
    required double lng,
  }) async {
    await supabase
        .schema('waste')
        .from('papierkörbe')
        .update({
          'lat': lat,
          'lng': lng,
          'geodaten_geändert_am': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
  }

  // ----------------------------------------------------------
  // FOTO UPLOAD (Standortfoto)
  // ----------------------------------------------------------

  Future<String> fotoHochladen(File foto, String qrCode) async {
    final komprimiert = await FlutterImageCompress.compressWithFile(
      foto.absolute.path,
      quality: 55,
      minWidth: 800,
      minHeight: 800,
    );

    if (komprimiert == null) {
      throw Exception('Foto-Komprimierung fehlgeschlagen');
    }

    final dateiname = '$qrCode.jpg';

    await supabase.storage
        .from('papierkorb-fotos')
        .uploadBinary(
          dateiname,
          komprimiert,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );

    return supabase.storage
        .from('papierkorb-fotos')
        .getPublicUrl(dateiname);
  }

  // ----------------------------------------------------------
  // STRASSEN
  // ----------------------------------------------------------

  Future<List<Map<String, dynamic>>> strassen() async {
    final response = await supabase
        .from('strassen')
        .select('id, name, stadtteil')
        .order('name', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }
}