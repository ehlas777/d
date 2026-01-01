import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // PolyDub Brand Colors - Golden Ratio & Cyber Aesthetics
  static const Color primaryBlue = Color(0xFF1E88E5);      // "Poly"
  static const Color primaryPurple = Color(0xFF7B2CBF);    // "Dub"
  static const Color accentCyan = Color(0xFF00BCD4);       // Cyan accent
  static const Color accentMagenta = Color(0xFFE91E63);    // Magenta accent

  // Refined "Success" Color - Teal/Cyan instead of plain Green
  static const Color successTeal = Color(0xFF00BFA5); 

  // Background & Surface - Deep & Clean
  static const Color backgroundColor = Color(0xFFF0F4F8); // Slightly cooler grey/blue tint
  static const Color cardColor = Color(0xFFFFFFFF);
  static const Color surfaceLight = Color(0xFFF8F9FB); 
  
  // Text Colors - avoiding pure black
  static const Color textPrimary = Color(0xFF0F172A); // Slate 900
  static const Color textSecondary = Color(0xFF475569); // Slate 600
  static const Color textOnGradient = Color(0xFFFFFFFF);
  
  // Backward compatibility
  static const Color accentColor = primaryBlue;
  
  // Status Colors
  static const Color errorColor = Color(0xFFEF4444);
  static const Color successColor = successTeal; // Map success to Teal
  static const Color warningColor = Color(0xFFF59E0B);
  
  // Borders & Dividers
  static const Color borderColor = Color(0xFFE2E8F0);
  static const Color borderLight = Color(0xFFF1F5F9);

  // Golden Ratio (Phi)
  static const double phi = 1.618;

  // Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryBlue, primaryPurple],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient accentGradient = LinearGradient(
    colors: [accentCyan, primaryBlue],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient purpleCyanGradient = LinearGradient(
    colors: [primaryPurple, accentCyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Gradient for Success states
  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF00BFA5), Color(0xFF00BCD4)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.light(
      primary: primaryBlue,
      secondary: primaryPurple,
      tertiary: accentCyan,
      surface: cardColor,
      error: errorColor,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: textPrimary,
    ),
    scaffoldBackgroundColor: backgroundColor,
    
    // Text Theme with Golden Ratio Scale (Base 16)
    // 16 * 1.618 = 25.8 (~26)
    // 26 * 1.618 = 42
    // 42 * 1.618 = 68 (Too large for mobile usually, limiting top end)
    textTheme: TextTheme(
      // Display - Top Heirarchy
      displayLarge: GoogleFonts.outfit(
        fontSize: 42, 
        fontWeight: FontWeight.w700,
        color: textPrimary,
        height: 1.2,
      ),
      displayMedium: GoogleFonts.outfit(
        fontSize: 34, // 26 * 1.3 roughly or scaled down phi
        fontWeight: FontWeight.w700,
        color: textPrimary,
      ),
      displaySmall: GoogleFonts.outfit(
        fontSize: 26,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      
      // Headlines
      headlineLarge: GoogleFonts.outfit(
        fontSize: 26,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      headlineMedium: GoogleFonts.outfit(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      headlineSmall: GoogleFonts.outfit(
        fontSize: 20, 
        fontWeight: FontWeight.w600,
        color: textPrimary,
      ),
      
      // Body - The Base (16)
      bodyLarge: GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        color: textPrimary,
        height: 1.5, // Better readability
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: textPrimary,
        height: 1.5,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12, // 16 / 1.33
        fontWeight: FontWeight.w400,
        color: textSecondary,
      ),
      
      // Labels
      labelLarge: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: textPrimary,
        letterSpacing: 0.5,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: textSecondary,
        letterSpacing: 0.5,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: textSecondary,
        letterSpacing: 0.5,
      ),
    ),
    
    cardTheme: CardTheme(
      color: cardColor,
      elevation: 0,
      shadowColor: primaryBlue.withOpacity(0.08), // Branded shadow
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    
    iconTheme: const IconThemeData(
      color: textSecondary,
      size: 24,
    ),
    
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primaryBlue,
      foregroundColor: Colors.white,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: textPrimary,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
             color: primaryBlue.withOpacity(0.2),
             blurRadius: 8,
             offset: const Offset(0, 4),
          )
        ],
      ),
      textStyle: GoogleFonts.inter(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    ),
    
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primaryBlue,
      linearTrackColor: borderColor,
    ),
    
    dividerTheme: const DividerThemeData(
      color: borderColor,
      thickness: 1,
      space: 1,
    ),
    
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: surfaceLight,
        foregroundColor: primaryBlue,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: borderColor, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: borderColor, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primaryPurple, width: 2), // Purple focus
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: errorColor, width: 1),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: GoogleFonts.inter(
        fontSize: 14,
        color: textSecondary,
      ),
      hintStyle: GoogleFonts.inter(
        fontSize: 14,
        color: textSecondary,
      ),
    ),
  );

  // Gradient Button
  static Widget gradientButton({
    required String text,
    required VoidCallback onPressed,
    Gradient? gradient,
    double? width,
    double? height,
    IconData? icon,
    bool isLoading = false,
  }) {
    return Container(
      width: width,
      height: height ?? 48,
      decoration: BoxDecoration(
        gradient: gradient ?? primaryGradient,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: (gradient ?? primaryGradient).colors.first.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        text,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  // Glassmorphism Card
  static Widget glassCard({
    required Widget child,
    EdgeInsets? padding,
    double? width,
    double? height,
    Color? color,
  }) {
    return Container(
      width: width,
      height: height,
      padding: padding ?? const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color ?? cardColor.withOpacity(0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }

  // Modern Card with hover effect
  static Widget modernCard({
    required Widget child,
    EdgeInsets? padding,
    double? width,
    double? height,
    VoidCallback? onTap,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderLight, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: padding ?? const EdgeInsets.all(24),
            child: child,
          ),
        ),
      ),
    );
  }

  // Icon button with tooltip
  static Widget iconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color? color,
    double? size,
  }) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, color: color ?? textSecondary, size: size ?? 24),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: surfaceLight,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  // Backward compatibility - alias to modernCard
  static Widget card({
    required Widget child,
    EdgeInsets? padding,
    double? width,
    double? height,
  }) {
    return modernCard(
      child: child,
      padding: padding,
      width: width,
      height: height,
    );
  }

  // Gradient Text
  static Widget gradientText(
    String text, {
    required Gradient gradient,
    TextStyle? style,
  }) {
    return ShaderMask(
      shaderCallback: (bounds) => gradient.createShader(
        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      ),
      child: Text(
        text,
        style: (style ?? GoogleFonts.outfit(
          fontSize: 24,
          fontWeight: FontWeight.w700,
        )).copyWith(color: Colors.white),
      ),
    );
  }
}
