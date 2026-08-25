import 'package:flutter/material.dart';

abstract final class AppColors {
  static const forest = Color(0xFF07543B);
  static const forestDark = Color(0xFF043D2C);
  static const teal = Color(0xFF009688);
  static const cyan = Color(0xFF07889B);
  static const amber = Color(0xFFF5A800);
  static const blue = Color(0xFF246BCE);
  static const danger = Color(0xFFD92D20);
  static const mint = Color(0xFFF1F8F5);
  static const canvas = Color(0xFFF7FAF8);
  static const ink = Color(0xFF18332A);
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.forest,
    primary: AppColors.forest,
    secondary: AppColors.teal,
    surface: Colors.white,
    error: AppColors.danger,
    brightness: Brightness.light,
  );
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(color: Color(0xFFBCD4CA)),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.canvas,
    fontFamily: 'Roboto',
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
      },
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.forestDark,
      foregroundColor: Colors.white,
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 2,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.w800,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: AppColors.teal, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 2,
      shadowColor: AppColors.forest.withValues(alpha: .13),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 50),
        side: const BorderSide(color: AppColors.teal, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.forestDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.tint = Colors.white,
    this.borderColor,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final Color tint;
  final Color? borderColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        padding: padding,
        decoration: BoxDecoration(
          color: tint,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor ?? const Color(0xFFD9E7E1)),
          boxShadow: [
            BoxShadow(
              color: AppColors.forest.withValues(alpha: .09),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: child,
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text,
      {super.key, required this.icon, this.color = AppColors.forest});

  final String text;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w900, color: color),
            ),
          ),
        ],
      );
}

class GradientActionButton extends StatelessWidget {
  const GradientActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.colors = const [AppColors.teal, AppColors.forest],
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: onPressed == null ? .45 : 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors),
            borderRadius: BorderRadius.circular(14),
            boxShadow: onPressed == null
                ? null
                : [
                    BoxShadow(
                      color: colors.last.withValues(alpha: .25),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
          ),
          child: FilledButton.icon(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
            ),
            icon: Icon(icon),
            label: Text(label),
          ),
        ),
      );
}
