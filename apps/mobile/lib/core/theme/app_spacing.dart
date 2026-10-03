import 'package:flutter/material.dart';
class AppSpacing {
  AppSpacing._();

  static const double xs   = 4;
  static const double sm   = 8;
  static const double md   = 12;
  static const double lg   = 16;
  static const double xl   = 20;
  static const double xl2  = 24;
  static const double xl3  = 32;
  static const double xl4  = 40;
  static const double xl5  = 48;
  static const double xl6  = 56;
  static const double xl7  = 64;

  static const double buttonPaddingH  = 16; 
  static const double buttonPaddingV  = 8;  
  static const double buttonHeight    = 48; 
  static const double inputHeight     = 48;
  static const double cardPadding     = 24;
  static const double screenPadding   = 24;
  static const double sectionGap      = 20;
  static const double itemGap         = 8;  
  static const double otpBoxSize      = 48;
  static const double otpBoxGap       = 8;

  static const double radiusXs    = 4;
  static const double radiusSm    = 8;
  static const double radiusMd    = 12;
  static const double radiusLg    = 16;
  static const double radiusXl    = 24; 
  static const double radiusFull  = 100;

  static BorderRadius get roundedSm  => BorderRadius.circular(radiusSm);
  static BorderRadius get roundedMd  => BorderRadius.circular(radiusMd);
  static BorderRadius get roundedLg  => BorderRadius.circular(radiusLg);
  static BorderRadius get roundedXl  => BorderRadius.circular(radiusXl);
  static BorderRadius get roundedFull => BorderRadius.circular(radiusFull);

  static const EdgeInsets screenInsets = EdgeInsets.symmetric(horizontal: screenPadding);
  static const EdgeInsets cardInsets   = EdgeInsets.all(cardPadding);
  static const EdgeInsets buttonInsets = EdgeInsets.symmetric(
    horizontal: buttonPaddingH,
    vertical: buttonPaddingV,
  );
}
