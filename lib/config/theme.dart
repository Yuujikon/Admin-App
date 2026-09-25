import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class GdcColors {
  // Color Hunt Palette: EDF1D6, 9DC08B, 609966, 40513B
  static const deepGreen         = Color(0xFF40513B); // Darkest - Headers/Text
  static const primaryGreen      = Color(0xFF609966); // Main Action
  static const secondaryGreen    = Color(0xFF9DC08B); // Secondary/Accent
  static const backgroundCream   = Color(0xFFEDF1D6); // Background
  
  static const paper             = Color(0xFFF7F9E8); // Slightly lighter surface
  
  // Dark Mode Palette (Muted Forest)
  static const midnight          = Color(0xFF1A1C1E); 
  static const slate             = Color(0xFF2D3135); 
  static const mutedGreen        = Color(0xFF609966); 
  static const goldDim           = Color(0xFF9DC08B); 
  
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
    
    final primaryColor   = isDark ? GdcColors.mutedGreen : GdcColors.primaryGreen;
    final secondaryColor = isDark ? GdcColors.goldDim : GdcColors.secondaryGreen;
    final backgroundColor = isDark ? GdcColors.midnight : GdcColors.backgroundCream;
    final surfaceColor    = isDark ? GdcColors.slate : GdcColors.paper;
    final textColor       = isDark ? Colors.white.withValues(alpha: 0.95) : GdcColors.deepGreen;
    final subTextColor    = isDark ? Colors.white.withValues(alpha: 0.6)  : GdcColors.deepGreen.withValues(alpha: 0.6);
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
        surfaceContainer:       isDark ? GdcColors.slate.withValues(alpha: 0.5) : GdcColors.secondaryGreen.withValues(alpha: 0.3),
        tertiary:       successColor,
        onTertiary:     isDark ? GdcColors.midnight : Colors.white,
      ),
      extensions: <ThemeExtension<dynamic>>[
        GdcSemanticColors(
          success: successColor,
          warning: warningColor,
          info:    infoColor,
        ),
        GdcLayoutTheme(
          cardRadius: 24,
          sheetRadius: 32,
          inputRadius: 18,
          buttonRadius: 20,
        ),
      ],
      textTheme: GoogleFonts.plusJakartaSansTextTheme().copyWith(
        headlineLarge: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: textColor),
        headlineMedium: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: textColor),
        titleLarge:     GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: textColor),
        titleMedium:    GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: primaryColor),
        titleSmall:     GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: textColor),
        bodyLarge:      TextStyle(fontSize: 13, color: textColor),
        bodyMedium:     TextStyle(fontSize: 12, color: subTextColor),
        bodySmall:      TextStyle(fontSize: 11, color: subTextColor),
        labelMedium:    TextStyle(fontSize: 11, color: subTextColor, fontWeight: FontWeight.w600),
        labelSmall:     TextStyle(fontSize: 10, color: subTextColor, fontWeight: FontWeight.w600),
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
        backgroundColor: isDark ? GdcColors.slate : GdcColors.secondaryGreen.withValues(alpha: 0.4),
        labelStyle:      TextStyle(color: isDark ? Colors.white : GdcColors.deepGreen, fontWeight: FontWeight.w700, fontSize: 11),
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
          foregroundColor: isDark ? GdcColors.midnight : GdcColors.backgroundCream,
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
  GdcSemanticColors get semantic => extension<GdcSemanticColors>() ?? const GdcSemanticColors(
    success: Colors.green,
    warning: Colors.orange,
    info: Colors.blue,
  );

  GdcLayoutTheme get layout => extension<GdcLayoutTheme>() ?? const GdcLayoutTheme(
    cardRadius: 24,
    sheetRadius: 32,
    inputRadius: 18,
    buttonRadius: 20,
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
  GdcLayoutTheme copyWith({double? cardRadius, double? sheetRadius, double? inputRadius, double? buttonRadius}) {
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
      cardRadius:   lerpDouble(cardRadius, other.cardRadius, t)!,
      sheetRadius:  lerpDouble(sheetRadius, other.sheetRadius, t)!,
      inputRadius:  lerpDouble(inputRadius, other.inputRadius, t)!,
      buttonRadius: lerpDouble(buttonRadius, other.buttonRadius, t)!,
    );
  }

  double lerpDouble(num a, num b, double t) => a + (b - a) * t;
}

class BrandStyling {
  static TextStyle getStyle(String? brand, {double fontSize = 14}) {
    if (brand == null || brand.isEmpty) {
      return TextStyle(fontWeight: FontWeight.w900, color: GdcColors.deepGreen, fontSize: fontSize);
    }
    
    final b = brand.toLowerCase();
    if (b.contains('coca-cola') || b.contains('coke')) {
      return GoogleFonts.lobster(color: const Color(0xFFF40009), fontWeight: FontWeight.bold, fontSize: fontSize);
    } else if (b.contains('pepsi')) {
      return GoogleFonts.bebasNeue(color: const Color(0xFF004B93), fontSize: fontSize);
    } else if (b.contains('nestle') || b.contains('nescafe')) {
      return GoogleFonts.merriweather(color: const Color(0xFF6B4226), fontWeight: FontWeight.w900, fontSize: fontSize);
    } else if (b.contains('unilever')) {
      return GoogleFonts.comfortaa(color: const Color(0xFF1F36C7), fontWeight: FontWeight.bold, fontSize: fontSize);
    } else if (b.contains('san miguel')) {
      return GoogleFonts.playfairDisplay(color: const Color(0xFF8B4513), fontWeight: FontWeight.w900, fontSize: fontSize);
    } else if (b.contains('lucky me')) {
      return GoogleFonts.fredoka(color: const Color(0xFFFF8C00), fontWeight: FontWeight.bold, fontSize: fontSize);
    } else if (b.contains('jack') && b.contains('jill')) {
       return GoogleFonts.bubblegumSans(color: Colors.red.shade800, fontSize: fontSize);
    }
    
    return TextStyle(fontWeight: FontWeight.w900, color: GdcColors.deepGreen, fontSize: fontSize);
  }
}
