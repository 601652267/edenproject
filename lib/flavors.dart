enum Flavor {
  dev,
  eden,
}

class F {
  static late final Flavor appFlavor;

  static String get name => appFlavor.name;

  static String get title {
    switch (appFlavor) {
      case Flavor.dev:
        return '伊甸园的骄傲DEV';
      case Flavor.eden:
        return '伊甸园的骄傲';
    }
  }

}
