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

  Future<void> leerungBestaetigen({
    required String papierkorbId,
    required String papierkorbQrCode,
    String? bemerkung,
    File? foto,
    Uint8List? fotoBytes,
    String? neuerStatus,
  }) async {
    String? fotoUrl;

    if (fotoBytes != null) {
      fotoUrl = await _uploadBytes(
        fotoBytes,
        'leerungen/${papierkorbQrCode}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
    } else if (foto != null) {
      fotoUrl = await _uploadFile(foto,
          'leerungen/${papierkorbQrCode}_${DateTime.now().millisecondsSinceEpoch}.jpg');
    }

    await supabase
        .schema('waste')
        .from('leerungen')
        .insert({
          'papierkorb_id': papierkorbId,
          'bemerkung':     bemerkung,
          'foto_url':      fotoUrl,
        });

    if (neuerStatus != null) {
      await supabase
          .schema('waste')
          .from('papierkörbe')
          .update({'status': neuerStatus})
          .eq('id', papierkorbId);
    }
  }

  // ----------------------------------------------------------
  // MELDUNGEN
  // ----------------------------------------------------------

  Future<List<Map<String, dynamic>>> meldungen() async {
    final response = await supabase
        .from('meldungen_view')
        .select();
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> meldungErledigen({
    required String typ,
    required String id,
    required String papierkorbId,
  }) async {
    if (typ == 'leerung') {
      await supabase
          .schema('waste')
          .from('leerungen')
          .update({'meldung_erledigt': true})
          .eq('id', id);
    }
    await supabase
        .schema('waste')
        .from('papierkörbe')
        .update({'status': 'aktiv'})
        .eq('id', papierkorbId);
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
    String? bauartId,
    required double lat,
    required double lng,
    File? foto,
    Uint8List? fotoBytes,
  }) async {
    String? fotoUrl;
    if (fotoBytes != null) {
      fotoUrl = await _uploadBytes(fotoBytes, '$qrCode.jpg');
    } else if (foto != null) {
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
          'bauart_id':    bauartId,
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
    String? bauartId,
    required double lat,
    required double lng,
    required String status,
    File? neuesFoto,
    Uint8List? neuesFotoBytes,
  }) async {
    String? fotoUrl;
    if (neuesFotoBytes != null) {
      fotoUrl = await _uploadBytes(neuesFotoBytes, '$qrCode.jpg');
    } else if (neuesFoto != null) {
      fotoUrl = await fotoHochladen(neuesFoto, qrCode);
    }

    final updates = <String, dynamic>{
      'strassen_id':  strassenId,
      'hausnummer':   hausnummer,
      'beschreibung': beschreibung,
      'bauart_id':    bauartId,
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
  // FOTO UPLOAD
  // ----------------------------------------------------------

  Future<String> fotoHochladen(File foto, String qrCode) async {
    final komprimiert = await FlutterImageCompress.compressWithFile(
      foto.absolute.path,
      quality: 55,
      minWidth: 800,
      minHeight: 800,
    );
    if (komprimiert == null) throw Exception('Komprimierung fehlgeschlagen');
    return _uploadBytes(komprimiert, '$qrCode.jpg');
  }

  Future<String> _uploadBytes(Uint8List bytes, String pfad) async {
    await supabase.storage
        .from('papierkorb-fotos')
        .uploadBinary(
          pfad,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    return supabase.storage
        .from('papierkorb-fotos')
        .getPublicUrl(pfad);
  }

  Future<String> _uploadFile(File foto, String pfad) async {
    final komprimiert = await FlutterImageCompress.compressWithFile(
      foto.absolute.path,
      quality: 55,
      minWidth: 800,
      minHeight: 800,
    );
    if (komprimiert == null) throw Exception('Komprimierung fehlgeschlagen');
    return _uploadBytes(komprimiert, pfad);
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

  // ----------------------------------------------------------
  // BAUARTEN
  // ----------------------------------------------------------

  Future<List<Map<String, dynamic>>> bauarten() async {
    final response = await supabase
        .from('bauart')
        .select('id, beschreibung')
        .order('beschreibung', ascending: true);
    return List<Map<String, dynamic>>.from(response);
  }
}