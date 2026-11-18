import 'package:flutter/material.dart';

import 'screens/player_screen.dart';
import 'services/jio_api.dart';
import 'theme.dart';

class StreamzTvApp extends StatelessWidget {
  const StreamzTvApp({super.key, required this.api});
  final JioApi api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StreamZ TV',
      debugShowCheckedModeBanner: false,
      theme: buildTvTheme(),
      home: PlayerScreen(api: api, initialGuide: true),
    );
  }
}
