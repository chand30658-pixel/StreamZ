import 'package:flutter/material.dart';
import 'src/app.dart';
import 'src/services/jio_api.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(StreamzTvApp(api: JioApi()));
}
