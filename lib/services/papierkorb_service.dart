import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../models/papierkorb.dart';
import '../models/leerung.dart';

class PapierkorbService {

  // ----------------------------------------------------------
  // PAPIERKÖRBE LADEN — über public.papierkörbe_view
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

  // Suche per QR-Code String — der einzige Weg einen Korb zu finden
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
    String? bemerkung,
  }) async {
    await supabase
        .schema('waste')
        .from('leerungen')
        .insert({
          'papierkorb_id': papierkorbId,
          'bemerkung':     bemerkung,
        });
  }

  // ----------------------------------------------------------
  // ADMIN: PAPIERKORB ANLEGEN
  // ----------------------------------------------------------

  Future<Papierkorb> anlegen({
    required String qrCode,    // z.B. "pk_0001"
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

    // Zurücklesen über View
    final response = await supabase
        .from('papierkörbe_view')
        .select()
        .eq('qr_code', qrCode)
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
          'geodaten_geaendert_am': DateTime.now().toIso8601String(),
        })
        .eq('id', id);
  }

  // ----------------------------------------------------------
  // FOTO UPLOAD — Dateiname = qr_code
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

    // Dateiname = qr_code, z.B. pk_0001.jpg
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
        .order('name');

    return List<Map<String, dynamic>>.from(response);
  }
}