import 'package:flutter/material.dart';

import 'api.dart';
import 'screens/movies_screen.dart';

void main() => runApp(const ShowtimeApp());

class ShowtimeApp extends StatelessWidget {
  const ShowtimeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final api = ShowtimeApi();
    return MaterialApp(
      title: 'Pune Cinemas',
      debugShowCheckedModeBanner: false,
      theme: _theme,
      home: MoviesScreen(api: api),
    );
  }
}

const seedColour = Color(0xFFE11D48);

final _theme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: seedColour,
    brightness: Brightness.dark,
  ).copyWith(surface: const Color(0xFF0B0B10)),
  scaffoldBackgroundColor: const Color(0xFF0B0B10),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF0B0B10),
    surfaceTintColor: Colors.transparent,
    centerTitle: false,
  ),
);
