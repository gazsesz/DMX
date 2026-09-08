import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app.dart';

void main() {
  // This app runs at venues on the lighting node's own isolated Wi-Fi, with
  // no internet — never let google_fonts try to fetch a font over the
  // network; just fall back to the platform default instead of throwing.
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(const ProviderScope(child: DmxControllerApp()));
}
