import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class GdcColors {
  // Soothing Sage & Sand Palette (Light)
  static const deepSage         = Color(0xFF2C3639);
  static const sageGreen        = Color(0xFF3F4E4F);
  static const parchment        = Color(0xFFF7F3E9);
  static const paper            = Color(0xFFFCF9F2);
  static const earthyGold       = Color(0xFFA27B5C);
  static const sand             = Color(0xFFDCD7C9);
  
  // Dark Mode Palette (Midnight Sage)
  static const midnight         = Color(0xFF1A1C1E); // Deep background
  static const slate            = Color(0xFF2D3135); // Card background
  static const mutedSage        = Color(0xFF8BA688); // Primary in dark mode
  static const goldDim          = Color(0xFFC9A686); // Accents in dark mode
  
  // Semantic (Universal)
  static const errorLight       = Color(0xFFA04747);
  static const errorDark        = Color(0xFFCF6679);
  static const successLight     = Color(0xFF4E6C50);
  static const successDark      = Color(0xFF81C784);
  static const warningLight     = Color(0xFFD4A373);
  static const warningDark      = Color(0xFFFFB74D);
  static const infoLight        = Color(0xFF525E75);
  static const infoDark         = Color(0xFF90CAF9);
}

class GdcTheme {
  static ThemeData get light => _buildTheme(Brightness.light);
  static ThemeData get dark  => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    
    final primaryColor   = isDark ? GdcColors.mutedSage : GdcColors.sageGreen;
    final secondaryColor = isDark ? GdcColors.goldDim : GdcColors.earthyGold;
    final backgroundColor = isDark ? GdcColors.midnight : GdcColors.parchment;
    final surfaceColor    = isDark ? GdcColors.slate : GdcColors.paper;
    final textColor       = isDark ? Colors.white.withValues(alpha: 0.95) : GdcColors.deepSage;
    final subTextColor    = isDark ? Colors.white.withValues(alpha: 0.6)  : GdcColors.deepSage.withValues(alpha: 0.6);
    final borderColor     = isDark ? Colors.white.withValues(alpha: 0.1)  : Colors.black.withValues(alpha: 0.08);

    final errorColor   = isDark ? GdcColors.errorDark   : GdcColors.errorLight;
    final successColor = isDark ? GdcColors.successDark : GdcColors.successLight;
    final warningColor = isDark ? GdcColors.warningDark : GdcColors.warningLight;
    final infoColor    = isDark ? GdcColors.infoDark    : GdcColors.infoLight;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor:      primaryColor,
        brightness:     brightness,
        primary:        primaryColor,
        secondary:      secondaryColor,
        error:          errorColor,
        surface:        backgroundColor,
        onSurface:      textColor,
        onSurfaceVariant: subTextColor,
        outline:        borderColor,
        surfaceContainerLowest: isDark ? GdcColors.midnight : Colors.white,
        surfaceContainerLow:    surfaceColor,
        surfaceContainer:       isDark ? GdcColors.slate.withValues(alpha: 0.5) : GdcColors.sand.withValues(alpha: 0.3),
        tertiary:       successColor,
        onTertiary:     isDark ? GdcColors.midnight : Colors.white,
      ),
      extensions: <ThemeExtension<dynamic>>[
        GdcSemanticColors(
          success: successColor,
          warning: warningColor,
          info:    infoColor,
        ),
      ],
      textTheme: GoogleFonts.plusJakartaSansTextTheme().copyWith(
        headlineMedium: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, letterSpacing: -0.5, color: textColor),
        titleLarge:     GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, letterSpacing: -0.2, color: textColor),
        titleMedium:    GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: primaryColor),
        bodyLarge:      TextStyle(color: textColor),
        bodyMedium:     TextStyle(color: subTextColor),
        labelMedium:    TextStyle(color: subTextColor, fontWeight: FontWeight.w600),
        labelSmall:     TextStyle(color: subTextColor, fontSize: 11),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: backgroundColor,
        centerTitle:     false,
        elevation:       0,
        scrolledUnderElevation: 1,
        iconTheme:       IconThemeData(color: textColor),
        titleTextStyle:  GoogleFonts.plusJakartaSans(
          color:         textColor,
          fontSize:      20,
          fontWeight:    FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color:     surfaceColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: borderColor, width: 1),
        ),
      ),
      chipTheme: ChipThemeData(
        shape:           RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side:            BorderSide.none,
        backgroundColor: isDark ? GdcColors.slate : GdcColors.sand.withValues(alpha: 0.4),
        labelStyle:      TextStyle(color: isDark ? Colors.white : GdcColors.deepSage, fontWeight: FontWeight.w700, fontSize: 11),
        padding:         const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      dividerTheme: DividerThemeData(
        color: borderColor,
        space: 1,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide:   BorderSide(color: borderColor),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide:   BorderSide(color: borderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide:   BorderSide(color: secondaryColor, width: 2),
        ),
        filled:          true,
        fillColor:       isDark ? GdcColors.midnight : GdcColors.paper,
        contentPadding:  const EdgeInsets.all(20),
        hintStyle:       TextStyle(color: subTextColor.withValues(alpha: 0.4)),
        labelStyle:      TextStyle(color: subTextColor),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: isDark ? GdcColors.midnight : GdcColors.parchment,
          minimumSize:     const Size.fromHeight(58),
          shape:           RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation:       0,
          textStyle:       const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: BorderSide(color: primaryColor),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          minimumSize: const Size.fromHeight(58),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceColor,
        indicatorColor:  secondaryColor.withValues(alpha: 0.2),
        iconTheme: WidgetStateProperty.resolveWith((states) {
           if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: primaryColor);
          }
          return IconThemeData(color: subTextColor);
        }),
        labelTextStyle:  WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: primaryColor);
          }
          return TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: subTextColor);
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
  GdcSemanticColors get semantic => extension<GdcSemanticColors>()!;
}
