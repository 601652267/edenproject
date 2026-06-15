import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'flavors.dart';
import 'pages/EdenRemotePlayerPage/eden_remote_player_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  F.appFlavor = Flavor.eden;

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(683, 512),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (BuildContext context, Widget? child) {
        return MaterialApp(
          title: 'Eden Spine',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFDB5979),
              brightness: Brightness.dark,
            ),
            textTheme: TextTheme(
              bodyMedium: TextStyle(fontSize: 14.sp),
              titleMedium: TextStyle(fontSize: 16.sp),
              titleLarge: TextStyle(fontSize: 20.sp),
            ),
            useMaterial3: true,
          ),
          home: const EdenRemotePlayerPage(),
          builder: EasyLoading.init(),
        );
      },
    );
  }
}

// 11200011应该有立绘2 但是立绘2的按钮没有显示，
