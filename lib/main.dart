import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'views/planner_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr_TR', null);
  runApp(const MeetNotesApp());
}

class MeetNotesApp extends StatelessWidget {
  const MeetNotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MeetNotes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          primary: const Color(0xFF2563EB),
          surface: Colors.white,
        ),
        useMaterial3: true,
        fontFamily: null,
      ),
      home: const PlannerScreen(),
    );
  }
}
