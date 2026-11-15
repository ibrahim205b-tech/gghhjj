import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'services/controller.dart';
import 'services/sound.dart';
import 'services/storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final dir = await getApplicationDocumentsDirectory();
  final sound = SoundService();
  final controller = AppController(files: JsonFiles(dir), sound: sound);
  // Sounds are loaded first (behind the black launch screen) so the intro's
  // opening boom is not lost; match data loads while the intro plays.
  await sound.preload();
  runApp(HhkkllApp(controller: controller));
  await controller.init();
}
