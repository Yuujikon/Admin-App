import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design system color constants for the GDC Sari-Sari Store brand.
class GdcColors {
  // GDC Design System Core Brand Colors - Warm Cream Theme
  static const appBackground = Color(0xFFFAF6EE);
  static const whiteSurface = Color(0xFFFFFFFF);
  static const mainText = Color(0xFF172237);
  static const mutedText = Color(0xFF697386);
  static const creamPrimary = Color(0xFFC87533);
  static const darkCream = Color(0xFF7A3E18);
  static const creamActiveBackground = Color(0xFFF3E8D3);
  static const border = Color(0xFFE2D8C6);
  static const strongBorder = Color(0xFFB8AA94);
  static const warningAmber = Color(0xFFE99A1A);
  static const dangerCoral = Color(0xFFE55454);
  static const violetAccent = Color(0xFF8754D2);

  // Backwards Compatibility Palette Aliases
  static const emeraldPrimary = creamPrimary;
  static const darkEmerald = darkCream;
  static const mintActiveBackground = creamActiveBackground;

  static const deepNavy = Color(0xFF12213F);
  static const secondaryNavy = Color(0xFF1C2F55);
  static const deepGreen = mainText;
  static const primaryGreen = creamPrimary;
  static const secondaryGreen = darkCream;
  static const backgroundCream = appBackground;
  static const paper = whiteSurface;

  // Dark Mode Palette
  static const midnight = Color(0xFF1E1B18);
  static const slate = Color(0xFF2B2621);
  static const mutedGreen = Color(0xFFE2A86E);
  static const goldDim = creamPrimary;

  // Universal Semantic Tonal Colors
  static const errorLight = dangerCoral;
  static const errorDark = Color(0xFFF87171);
  static const successLight = Color(0xFF10B981);
  static const successDark = Color(0xFF34D399);
  static const warningLight = warningAmber;
  static const warningDark = Color(0xFFFBBF24);
  static const infoLight = Color(0xFF3B82F6);
  static const infoDark = Color(0xFF60A5FA);
}

/// ThemeData builder utility for Light and Dark Material 3 theme variants.
class GdcTheme {
  /// Returns the custom Material 3 Light theme.
  static ThemeData get light => _buildTheme(Brightness.light);

  /// Returns the custom Material 3 Dark theme.
  static ThemeData get dark => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;

    final primaryColor = isDark ? GdcColors.mutedGreen : GdcColors.emeraldPrimary;
    final secondaryColor =
        isDark ? GdcColors.goldDim : GdcColors.darkEmerald;
    final backgroundColor =
        isDark ? GdcColors.midnight : GdcColors.appBackground;
    final surfaceColor = isDark ? GdcColors.slate : GdcColors.whiteSurface;
    final textColor =
        isDark ? Colors.white.withValues(alpha: 0.95) : GdcColors.mainText;
    final subTextColor = isDark
        ? Colors.white.withValues(alpha: 0.6)
        : GdcColors.mutedText;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : GdcColors.border;

    final errorColor = isDark ? GdcColors.errorDark : GdcColors.errorLight;
    final successColor =
        isDark ? GdcColors.successDark : GdcColors.successLight;
    final warningColor =
        isDark ? GdcColors.warningDark : GdcColors.warningLight;
    final infoColor = isDark ? GdcColors.infoDark : GdcColors.infoLight;

    final textTheme = GoogleFonts.plusJakartaSansTextTheme().copyWith(
      headlineLarge: GoogleFonts.plusJakartaSans(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: textColor),
      headlineMedium: GoogleFonts.plusJakartaSans(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: textColor),
      headlineSmall: GoogleFonts.plusJakartaSans(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: textColor),
      titleLarge: GoogleFonts.plusJakartaSans(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: textColor),
      titleMedium: GoogleFonts.plusJakartaSans(
          fontSize: 14, fontWeight: FontWeight.w600, color: primaryColor),
      titleSmall: GoogleFonts.plusJakartaSans(
          fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
      bodyLarge: TextStyle(fontSize: 14, color: textColor),
      bodyMedium: TextStyle(fontSize: 13, color: subTextColor),
      bodySmall: TextStyle(fontSize: 12, color: subTextColor),
      labelMedium: TextStyle(
          fontSize: 12, color: subTextColor, fontWeight: FontWeight.w600),
      labelSmall: TextStyle(
          fontSize: 11, color: subTextColor, fontWeight: FontWeight.w600),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: backgroundColor,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: brightness,
        primary: primaryColor,
        secondary: secondaryColor,
        error: errorColor,
        surface: surfaceColor,
        onSurface: textColor,
        onSurfaceVariant: subTextColor,
        outline: borderColor,
        outlineVariant: borderColor,
        surfaceContainerLowest: isDark ? GdcColors.midnight : Colors.white,
        surfaceContainerLow: surfaceColor,
        surfaceContainer: isDark
            ? GdcColors.slate.withValues(alpha: 0.5)
            : GdcColors.mintActiveBackground,
        surfaceContainerHigh: isDark ? GdcColors.slate : GdcColors.whiteSurface,
        surfaceContainerHighest:
            isDark ? const Color(0xFF383C40) : const Color(0xFFE8DFC8),
        tertiary: successColor,
        onTertiary: isDark ? GdcColors.midnight : Colors.white,
      ),
      extensions: <ThemeExtension<dynamic>>[
        GdcSemanticColors(
          success: successColor,
          warning: warningColor,
          info: infoColor,
        ),
        const GdcLayoutTheme(
          cardRadius: 16,
          sheetRadius: 24,
          inputRadius: 12,
          buttonRadius: 16,
        ),
      ],
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: backgroundColor,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
        iconTheme: IconThemeData(color: textColor),
        titleTextStyle: GoogleFonts.plusJakartaSans(
          color: textColor,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceColor,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor, width: 1),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: borderColor, width: 1),
        backgroundColor: isDark ? GdcColors.slate : GdcColors.appBackground,
        selectedColor: isDark ? GdcColors.emeraldPrimary : GdcColors.mintActiveBackground,
        labelStyle: TextStyle(
            color: isDark ? Colors.white : GdcColors.mainText,
            fontWeight: FontWeight.w700,
            fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      dividerTheme: DividerThemeData(
        color: borderColor,
        space: 1,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primaryColor, width: 2),
        ),
        filled: true,
        fillColor: isDark ? GdcColors.midnight : GdcColors.whiteSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle:
            TextStyle(color: subTextColor.withValues(alpha: 0.6), fontSize: 13),
        labelStyle: TextStyle(color: subTextColor, fontSize: 13),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          minimumSize: const Size(120, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: BorderSide(color: primaryColor, width: 1.5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          minimumSize: const Size(120, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          minimumSize: const Size(120, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surfaceColor,
        indicatorColor: GdcColors.mintActiveBackground,
        selectedIconTheme: IconThemeData(color: GdcColors.darkEmerald, size: 22),
        unselectedIconTheme: IconThemeData(color: subTextColor, size: 20),
        selectedLabelTextStyle: TextStyle(
          color: GdcColors.darkEmerald,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
        unselectedLabelTextStyle: TextStyle(
          color: subTextColor,
          fontSize: 10,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceColor,
        indicatorColor: GdcColors.mintActiveBackground,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: GdcColors.darkEmerald);
          }
          return IconThemeData(color: subTextColor);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, color: GdcColors.darkEmerald);
          }
          return TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: subTextColor);
        }),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.white;
          }
          return subTextColor;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primaryColor;
          }
          return borderColor;
        }),
      ),
    );
  }
}

class GdcSemanticColors extends ThemeExtension<GdcSemanticColors> {
  final Color success;
  final Color warning;
  final Color info;

  const GdcSemanticColors({
    required this.success,
    required this.warning,
    required this.info,
  });

  @override
  GdcSemanticColors copyWith({Color? success, Color? warning, Color? info}) {
    return GdcSemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
    );
  }

  @override
  GdcSemanticColors lerp(ThemeExtension<GdcSemanticColors>? other, double t) {
    if (other is! GdcSemanticColors) return this;
    return GdcSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
    );
  }
}

extension GdcSemanticColorsExtension on ThemeData {
  GdcSemanticColors get semantic =>
      extension<GdcSemanticColors>() ??
      const GdcSemanticColors(
        success: Colors.green,
        warning: Colors.orange,
        info: Colors.blue,
      );

  GdcLayoutTheme get layout =>
      extension<GdcLayoutTheme>() ??
      const GdcLayoutTheme(
        cardRadius: 16,
        sheetRadius: 24,
        inputRadius: 12,
        buttonRadius: 16,
      );
}

class GdcLayoutTheme extends ThemeExtension<GdcLayoutTheme> {
  final double cardRadius;
  final double sheetRadius;
  final double inputRadius;
  final double buttonRadius;

  const GdcLayoutTheme({
    required this.cardRadius,
    required this.sheetRadius,
    required this.inputRadius,
    required this.buttonRadius,
  });

  @override
  GdcLayoutTheme copyWith(
      {double? cardRadius,
      double? sheetRadius,
      double? inputRadius,
      double? buttonRadius}) {
    return GdcLayoutTheme(
      cardRadius: cardRadius ?? this.cardRadius,
      sheetRadius: sheetRadius ?? this.sheetRadius,
      inputRadius: inputRadius ?? this.inputRadius,
      buttonRadius: buttonRadius ?? this.buttonRadius,
    );
  }

  @override
  GdcLayoutTheme lerp(ThemeExtension<GdcLayoutTheme>? other, double t) {
    if (other is! GdcLayoutTheme) return this;
    return GdcLayoutTheme(
      cardRadius: lerpDouble(cardRadius, other.cardRadius, t),
      sheetRadius: lerpDouble(sheetRadius, other.sheetRadius, t),
      inputRadius: lerpDouble(inputRadius, other.inputRadius, t),
      buttonRadius: lerpDouble(buttonRadius, other.buttonRadius, t),
    );
  }

  double lerpDouble(num a, num b, double t) => a + (b - a) * t;
}

class BrandStyling {
  static TextStyle getStyle(String? brand, {double fontSize = 14}) {
    if (brand == null || brand.isEmpty) {
      return TextStyle(
          fontWeight: FontWeight.w900,
          color: GdcColors.mainText,
          fontSize: fontSize);
    }

    final b = brand.toLowerCase();
    if (b.contains('coca-cola') || b.contains('coke')) {
      return GoogleFonts.lobster(
          color: const Color(0xFFF40009),
          fontWeight: FontWeight.bold,
          fontSize: fontSize);
    } else if (b.contains('pepsi')) {
      return GoogleFonts.bebasNeue(
          color: const Color(0xFF004B93), fontSize: fontSize);
    } else if (b.contains('nestle') || b.contains('nescafe')) {
      return GoogleFonts.merriweather(
          color: const Color(0xFF6B4226),
          fontWeight: FontWeight.w900,
          fontSize: fontSize);
    } else if (b.contains('unilever')) {
      return GoogleFonts.comfortaa(
          color: const Color(0xFF1F36C7),
          fontWeight: FontWeight.bold,
          fontSize: fontSize);
    } else if (b.contains('san miguel')) {
      return GoogleFonts.playfairDisplay(
          color: const Color(0xFF8B4513),
          fontWeight: FontWeight.w900,
          fontSize: fontSize);
    } else if (b.contains('lucky me')) {
      return GoogleFonts.fredoka(
          color: const Color(0xFFFF8C00),
          fontWeight: FontWeight.bold,
          fontSize: fontSize);
    } else if (b.contains('jack') && b.contains('jill')) {
      return GoogleFonts.bubblegumSans(
          color: Colors.red.shade800, fontSize: fontSize);
    }

    return TextStyle(
        fontWeight: FontWeight.w900,
        color: GdcColors.mainText,
        fontSize: fontSize);
  }
}
