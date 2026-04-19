import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/start_screen.dart';
import 'screens/login_screen.dart';
import 'screens/fahrer/fahrer_screen.dart';
import 'screens/fahrer/detail_screen.dart';
import 'screens/admin/einmessen_screen.dart';
import 'screens/admin/backoffice_screen.dart';
import 'screens/admin/edit_screen.dart';
import 'screens/admin/meldung_detail_screen.dart';
import 'models/papierkorb.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Datum-Formatierung für Deutschland (wichtig für die Leerungs-Anzeige)
  await initializeDateFormatting('de_DE');

  // Env laden
  await dotenv.load(fileName: '.env');

  // Supabase Initialisierung
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  runApp(const PapierkorbApp());
}

// Globaler Zugriff auf Supabase
final supabase = Supabase.instance.client;

class PapierkorbApp extends StatelessWidget {
  const PapierkorbApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Papierkorb-App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor:
              const Color(0xFF2E7D32), // Ein schönes "Abfallwirtschafts-Grün"
        ),
        useMaterial3: true,
        // Optional: App-weites AppBar Design für PC-Look
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 2,
        ),
      ),
      home: StreamBuilder<AuthState>(
        stream: supabase.auth.onAuthStateChange,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }

          final session = snapshot.data?.session;
          if (session == null) {
            return const LoginScreen();
          }

          // Wir nutzen 'waste_role', um Konflikte mit anderen Apps in derselben DB zu vermeiden
          final userRole = session.user.appMetadata['waste_role'] ?? 'fahrer';
          final isWeb = kIsWeb || Platform.isMacOS || Platform.isWindows || Platform.isLinux;

          if (isWeb) {
            if (userRole == 'admin') {
              return const BackofficeScreen();
            } else {
              return const WebAccessDeniedScreen();
            }
          } else {
            if (userRole == 'admin') {
              return const StartScreen();
            } else {
              return const FahrerScreen();
            }
          }
        },
      ),
      routes: {
        '/start': (_) => const StartScreen(),
        '/fahrer': (_) => const FahrerScreen(),
        '/admin/einmessen': (_) => const EinmessenScreen(),
        '/admin/backoffice': (_) => const BackofficeScreen(),
      },
      onGenerateRoute: (settings) {
        // Dynamische Route für den DetailScreen (Fahrer)
        if (settings.name == '/fahrer/detail') {
          final args = settings.arguments;
          if (args is Papierkorb) {
            return MaterialPageRoute(
              builder: (_) => DetailScreen(papierkorb: args),
            );
          }
        }

        // Dynamische Route für den EditScreen (Backoffice PC)
        if (settings.name == '/admin/edit') {
          final args = settings.arguments;
          if (args is Papierkorb) {
            return MaterialPageRoute(
              builder: (_) => EditScreen(papierkorb: args),
            );
          }
        }

        // Dynamische Route für den MeldungDetailScreen
        if (settings.name == '/admin/meldung-detail') {
          final args = settings.arguments;
          if (args is Map<String, dynamic>) {
            return MaterialPageRoute(
              builder: (_) => MeldungDetailScreen(meldung: args),
            );
          }
        }

        return null;
      },
    );
  }
}

class WebAccessDeniedScreen extends StatelessWidget {
  const WebAccessDeniedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.desktop_access_disabled, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            const Text('Kein Zugriff', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Die Web-Anwendung ist nur für Admins reserviert.'),
            const SizedBox(height: 24),
            TextButton(onPressed: () => supabase.auth.signOut(), child: const Text('Abmelden'))
          ],
        ),
      ),
    );
  }
}
