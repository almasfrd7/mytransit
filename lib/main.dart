import 'package:flutter/material.dart';

import 'screens/home/home_screen.dart';
import 'theme.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) => MaterialApp(
        title: 'MyTransit',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: mode,
        home: const HomeScreen(),
      ),
    );
  }
}

// TODO: expose live polling through a top-level repository so screens don't
// each create their own TransitRepository(TransitApi()). Once a single repo
// instance is shared (e.g. a repository locator or Provider), start the KTMB
// poll in main() and wire live positions into the Live track screen.
