import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'theme/theme.dart';
import 'theme/theme_manager.dart';
import 'common/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Portrait Mode Only
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const UolEmsApp());
}

class UolEmsApp extends StatefulWidget {
  const UolEmsApp({super.key});

  @override
  State<UolEmsApp> createState() => _UolEmsAppState();
}

class _UolEmsAppState extends State<UolEmsApp> {

  @override
  void initState() {
    super.initState();
    themeManager.addListener(themeListener);
  }

  void themeListener() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    themeManager.removeListener(themeListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // --- UPDATE: DYNAMIC STATUS BAR ---
    // Ye check karta hai k abhi Dark mode hai ya Light, aur us hisaab se icons ka rang badalta hai
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      // Agar Dark Mode hai to Icons White (Light) honay chahiyen, warna Black (Dark)
      statusBarIconBrightness: themeManager.isDarkMode ? Brightness.light : Brightness.dark,
      // iOS ke liye logic:
      statusBarBrightness: themeManager.isDarkMode ? Brightness.dark : Brightness.light,
    ));

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'UOL EMS',

      // Theme Settings
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeManager.themeMode,

      home: const SplashScreen(),
    );
  }
}