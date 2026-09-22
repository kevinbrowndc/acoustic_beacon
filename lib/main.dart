import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'presentation/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final preferences = await SharedPreferences.getInstance();
  runApp(BeaconApp(preferences: preferences));
}
