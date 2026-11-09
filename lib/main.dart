import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/planner_storage_service.dart';
import 'views/planner_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr_TR', null);
  // Stroke/text writes are debounced; make sure nothing is lost when the app
  // loses focus, goes to background or is closed.
  AppLifecycleListener(
    onInactive: PlannerStorageService.flushPendingWrites,
    onHide: PlannerStorageService.flushPendingWrites,
    onPause: PlannerStorageService.flushPendingWrites,
    onDetach: PlannerStorageService.flushPendingWrites,
    onExitRequested: () async {
      await PlannerStorageService.flushPendingWrites();
      return ui.AppExitResponse.exit;
    },
  );
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
