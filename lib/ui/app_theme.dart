import 'package:flutter/material.dart';
import 'package:forui/forui.dart';

abstract final class AppTheme {
  static const purple = Color(0xFF6135E8);
  static const ink = Color(0xFF171321);
  static const muted = Color(0xFF716B7E);
  static const line = Color(0xFFE9E5F0);
  static const soft = Color(0xFFF5F1FF);
  static const green = Color(0xFF238242);
  static const red = Color(0xFFBF3E50);

  static final forui = FThemeData(
    touch: true,
    typography: FTypography(
      display: FTypeface(fontFamily: 'Roboto'),
      body: FTypeface(fontFamily: 'Roboto'),
    ),
    colors: FColors.neutralLight.copyWith(
      primary: purple,
      primaryForeground: Colors.white,
      background: Colors.white,
      foreground: ink,
      muted: soft,
      mutedForeground: muted,
      border: line,
    ),
  );

  static ThemeData get material {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: purple,
          brightness: Brightness.light,
        ).copyWith(
          primary: purple,
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: ink,
          onSurfaceVariant: muted,
          outline: const Color(0xFFD5CCE7),
          outlineVariant: line,
          primaryContainer: soft,
          error: red,
        );
    final base = ThemeData(
      fontFamily: 'Roboto',
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.white,
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    return base.copyWith(
      textTheme: base.textTheme
          .copyWith(
            headlineLarge: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 40,
              fontWeight: FontWeight.w700,
              letterSpacing: -1.4,
              color: ink,
              height: 1.15,
            ),
            headlineMedium: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.9,
              color: ink,
              height: 1.2,
            ),
            headlineSmall: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              color: ink,
              height: 1.25,
            ),
            titleLarge: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: ink,
            ),
            titleMedium: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
            titleSmall: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
            bodyLarge: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 16,
              height: 1.45,
              color: ink,
            ),
            bodyMedium: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 15,
              height: 1.45,
              color: ink,
            ),
            bodySmall: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 13,
              height: 1.4,
              color: muted,
            ),
            labelLarge: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          )
          .apply(fontFamily: 'Roboto'),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleSpacing: 24,
        toolbarHeight: 68,
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 25,
          fontWeight: FontWeight.w700,
          color: ink,
          letterSpacing: -0.5,
        ),
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 6),
        minVerticalPadding: 8,
        horizontalTitleGap: 12,
        minLeadingWidth: 0,
        iconColor: muted,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: shape,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          shape: shape,
          side: const BorderSide(color: purple),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFAF9FC),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 17,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: purple, width: 1.5),
        ),
        labelStyle: const TextStyle(fontFamily: 'Roboto', color: muted),
        hintStyle: const TextStyle(fontFamily: 'Roboto', color: muted),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: Colors.white,
        selectedColor: soft,
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        labelStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 13,
          color: ink,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: line),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: purple,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: shape,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: soft,
        height: 76,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: 'Roboto',
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
            color: states.contains(WidgetState.selected) ? purple : muted,
          ),
        ),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
        iconColor: purple,
        collapsedIconColor: muted,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  final String title;
  final Widget? action;
  const SectionHeading(this.title, {super.key, this.action});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        ?action,
      ],
    ),
  );
}

class InitialAvatar extends StatelessWidget {
  final String name;
  final double radius;
  const InitialAvatar(this.name, {super.key, this.radius = 22});
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: AppTheme.soft,
    foregroundColor: AppTheme.purple,
    child: Text(
      name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase(),
      style: TextStyle(
        fontFamily: 'Roboto',
        fontSize: radius * 0.7,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class SessionStatusBadge extends StatelessWidget {
  final bool isOpen;
  const SessionStatusBadge({super.key, required this.isOpen});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: isOpen ? const Color(0xFFF0F9F1) : const Color(0xFFF4F3F6),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(
        color: isOpen ? const Color(0xFFC9E7CC) : AppTheme.line,
      ),
    ),
    child: Text(
      isOpen ? 'Đang mở' : 'Đã đóng',
      style: TextStyle(
        fontFamily: 'Roboto',
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: isOpen ? AppTheme.green : AppTheme.muted,
      ),
    ),
  );
}
