import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/start_screen.dart';
import 'screens/fahrer/fahrer_screen.dart';
import 'screens/fahrer/detail_screen.dart';
import 'screens/admin/einmessen_screen.dart';
import 'screens/admin/backoffice_screen.dart';
import 'models/papierkorb.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDateFormatting('de_DE');

  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const PapierkorbApp());
}

final supabase = Supabase.instance.client;

class PapierkorbApp extends StatelessWidget {
  const PapierkorbApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Papierkorb-App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
      ),
      // Web → Backoffice, Handy → Startscreen
      initialRoute: kIsWeb ? '/admin/backoffice' : '/start',
      routes: {
        '/start':            (_) => const StartScreen(),
        '/fahrer':           (_) => const FahrerScreen(),
        '/admin/einmessen':  (_) => const EinmessenScreen(),
        '/admin/backoffice': (_) => const BackofficeScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/fahrer/detail') {
          final args = settings.arguments;
          if (args is Papierkorb) {
            return MaterialPageRoute(
              builder: (_) => DetailScreen(papierkorb: args),
            );
          }
          if (args is Map<String, dynamic>) {
            return MaterialPageRoute(
              builder: (_) => DetailScreen(
                papierkorb: args['papierkorb'] as Papierkorb,
                readonly:   args['readonly'] as bool? ?? false,
              ),
            );
          }
        }
        return null;
      },
    );
  }
}