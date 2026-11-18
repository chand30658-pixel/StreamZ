import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'services/jio_api.dart';
import 'theme.dart';

class StreamzTvApp extends StatelessWidget {
  const StreamzTvApp({super.key, required this.api});
  final JioApi api;
  @override Widget build(BuildContext context) => MaterialApp(
    title: 'StreamZ', debugShowCheckedModeBanner: false,
    theme: buildTvTheme(), home: HomeScreen(api: api),
  );
}
