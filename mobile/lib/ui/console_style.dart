import 'package:material_ui/material_ui.dart';

abstract final class ConsoleColors {
  static const background = Color(0xff101923);
  static const surface = Color(0xff1b2836);
  static const primary = Color(0xff25c7c9);
  static const success = Color(0xff54c98a);
  static const warning = Color(0xffe6ae52);
  static const danger = Color(0xffe36b72);
  static const secondary = Color(0xffa9b8c8);
  static const text = Color(0xfff2f6fa);

  static Color successOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? success
      : const Color(0xff216744);
  static Color warningOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? warning
      : const Color(0xff855609);
}

ThemeData consoleTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors =
      ColorScheme.fromSeed(
        seedColor: ConsoleColors.primary,
        brightness: brightness,
      ).copyWith(
        primary: dark ? ConsoleColors.primary : const Color(0xff00696c),
        onPrimary: dark ? const Color(0xff042f31) : Colors.white,
        primaryContainer: dark
            ? const Color(0xff163c43)
            : const Color(0xffd3f2f1),
        onPrimaryContainer: dark
            ? const Color(0xffa2f3ee)
            : const Color(0xff12464a),
        surface: dark ? ConsoleColors.background : const Color(0xfff2f6f8),
        surfaceContainer: dark ? ConsoleColors.surface : Colors.white,
        surfaceContainerLow: dark
            ? const Color(0xff17232f)
            : const Color(0xfff9fbfc),
        surfaceContainerHigh: dark
            ? const Color(0xff243443)
            : const Color(0xffe5eef1),
        onSurface: dark ? ConsoleColors.text : const Color(0xff172a36),
        onSurfaceVariant: dark
            ? ConsoleColors.secondary
            : const Color(0xff4b606e),
        outlineVariant: dark
            ? const Color(0xff344250)
            : const Color(0xffcdd9df),
        error: dark ? ConsoleColors.danger : const Color(0xffad3646),
      );
  final base = ThemeData(useMaterial3: true, colorScheme: colors);
  final typography = base.textTheme
      .apply(bodyColor: colors.onSurface, displayColor: colors.onSurface)
      .copyWith(
        headlineSmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: colors.onSurface,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: colors.onSurface,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: colors.onSurface,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 1.45,
          color: colors.onSurface,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          height: 1.4,
          color: colors.onSurfaceVariant,
        ),
      )
      .apply(
        fontFamily: 'Roboto',
        fontFamilyFallback: const [
          'Noto Sans CJK SC',
          'Microsoft YaHei',
          'PingFang SC',
        ],
      );
  return base.copyWith(
    scaffoldBackgroundColor: colors.surface,
    textTheme: typography,
    appBarTheme: AppBarThemeData(
      centerTitle: false,
      backgroundColor: colors.surface,
      foregroundColor: colors.onSurface,
      scrolledUnderElevation: 0,
      titleTextStyle: typography.headlineSmall,
    ),
    cardTheme: CardThemeData(
      color: colors.surfaceContainer,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerTheme: DividerThemeData(
      color: colors.outlineVariant,
      space: 1,
      thickness: 0.6,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.surface,
      elevation: 0,
      indicatorColor: colors.primaryContainer,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 22,
          color: states.contains(WidgetState.selected)
              ? colors.primary
              : colors.onSurfaceVariant,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => typography.bodySmall!.copyWith(
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? colors.primary
              : colors.onSurfaceVariant,
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
        side: const WidgetStatePropertyAll(BorderSide.none),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.primary
              : colors.surfaceContainer,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.onPrimary
              : colors.onSurfaceVariant,
        ),
        textStyle: WidgetStatePropertyAll(typography.labelLarge),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      filled: true,
      fillColor: colors.surfaceContainerLow,
    ),
  );
}

class ConsoleCard extends StatelessWidget {
  const ConsoleCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainer,
    borderRadius: BorderRadius.circular(16),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class ConsoleHeading extends StatelessWidget {
  const ConsoleHeading(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
      ),
      ?trailing,
    ],
  );
}
