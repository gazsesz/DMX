import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/channel_capability.dart';
import '../theme/app_colors.dart';

/// Pictures and swatches for a mover's wheels, so a gobo or colour slot is
/// picked by what it looks like instead of by a number.
///
/// Both work from what the fixture profile says: an explicit look set in the
/// range editor wins, otherwise the slot's label is read for words like
/// "star" or "light blue" (English and Hungarian), and anything else gets a
/// neutral numbered stand-in rather than a wrong guess.

/// The gobo pictures the app can draw, in the order the range editor offers
/// them.
const goboGlyphNames = <String>[
  'open',
  'dots',
  'star',
  'stripes',
  'spiral',
  'triangle',
  'flower',
  'breakup',
  'ring',
  'cross',
  'square',
  'shake',
];

const _glyphKeywords = <String, List<String>>{
  'open': ['open', 'nyitott', 'no gobo', 'white', 'fehér'],
  'dots': ['dot', 'pont', 'circles', 'bubble'],
  'star': ['star', 'csillag'],
  'stripes': ['stripe', 'bar', 'line', 'csík', 'vonal'],
  'spiral': ['spiral', 'swirl', 'spirál', 'örvény', 'vortex'],
  'triangle': ['triangle', 'három'],
  'flower': ['flower', 'petal', 'virág', 'sun', 'nap'],
  'breakup': ['breakup', 'break-up', 'leaf', 'leaves', 'cloud', 'water', 'levél', 'felhő'],
  'ring': ['ring', 'circle', 'kör', 'gyűrű', 'donut'],
  'cross': ['cross', 'kereszt', 'plus'],
  'square': ['square', 'négyzet', 'grid', 'rács'],
  'shake': ['shake', 'rázás', 'wobble'],
};

/// Which picture to draw for [capability], or null to draw a numbered disc.
String? goboGlyphFor(ChannelCapability capability) {
  final explicit = capability.glyph;
  if (explicit != null && goboGlyphNames.contains(explicit)) return explicit;
  final label = capability.label.toLowerCase();
  // "Shake" ranges usually name the gobo being shaken too; the shake is the
  // more useful thing to show, since the plain gobo has its own slot.
  for (final entry in _glyphKeywords.entries) {
    if (entry.key != 'shake' && entry.key != 'open') continue;
    if (entry.value.any(label.contains)) return entry.key;
  }
  for (final entry in _glyphKeywords.entries) {
    if (entry.value.any(label.contains)) return entry.key;
  }
  return null;
}

/// A round gobo picture: [glyph] drawn in light on black, or [fallbackText]
/// (usually the slot number) when there's no picture for it.
class GoboGlyph extends StatelessWidget {
  final String? glyph;
  final String fallbackText;
  final double size;
  final bool selected;

  const GoboGlyph({super.key, required this.glyph, this.fallbackText = '', this.size = 44, this.selected = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.black,
        shape: BoxShape.circle,
        border: Border.all(color: selected ? AppColors.accent : AppColors.border, width: selected ? 2 : 1.5),
        boxShadow: selected ? [BoxShadow(color: AppColors.accent.withValues(alpha: 0.3), blurRadius: 8)] : null,
      ),
      child: glyph == null
          ? Center(
              child: Text(
                fallbackText,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textDim),
              ),
            )
          : CustomPaint(painter: _GoboPainter(glyph!)),
    );
  }
}

class _GoboPainter extends CustomPainter {
  final String glyph;

  _GoboPainter(this.glyph);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final light = Paint()..color = AppColors.text;
    final stroke = Paint()
      ..color = AppColors.text
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.14
      ..strokeCap = StrokeCap.round;
    switch (glyph) {
      case 'open':
        canvas.drawCircle(c, r * 0.72, light);
      case 'dots':
        canvas.drawCircle(c, r * 0.16, light);
        for (var i = 0; i < 6; i++) {
          final a = i * math.pi / 3;
          canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r * 0.5, r * 0.13, light);
        }
      case 'star':
        canvas.drawPath(_star(c, r * 0.68, r * 0.3, 5), light);
      case 'stripes':
        for (var i = -1; i <= 1; i++) {
          canvas.drawRect(Rect.fromCenter(center: c + Offset(0, i * r * 0.38), width: r * 1.3, height: r * 0.18), light);
        }
      case 'spiral':
        final path = Path();
        for (var t = 0.0; t < 3 * math.pi; t += 0.15) {
          final rr = r * 0.08 + t / (3 * math.pi) * r * 0.6;
          final p = c + Offset(math.cos(t), math.sin(t)) * rr;
          t == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, stroke..strokeWidth = r * 0.12);
      case 'triangle':
        canvas.drawPath(_star(c, r * 0.7, r * 0.35, 3), light);
      case 'flower':
        for (var i = 0; i < 6; i++) {
          final a = i * math.pi / 3;
          canvas.drawOval(
            Rect.fromCenter(center: c + Offset(math.cos(a), math.sin(a)) * r * 0.36, width: r * 0.42, height: r * 0.42),
            light,
          );
        }
      case 'breakup':
        for (final (dx, dy, rr) in [(-0.3, -0.25, 0.2), (0.3, -0.2, 0.13), (-0.2, 0.35, 0.13), (0.28, 0.3, 0.24), (0.0, 0.0, 0.1)]) {
          canvas.drawCircle(c + Offset(dx, dy) * r, rr * r, light);
        }
      case 'ring':
        canvas.drawCircle(c, r * 0.5, stroke..strokeWidth = r * 0.18);
      case 'cross':
        canvas.drawLine(c - Offset(r * 0.55, 0), c + Offset(r * 0.55, 0), stroke..strokeWidth = r * 0.2);
        canvas.drawLine(c - Offset(0, r * 0.55), c + Offset(0, r * 0.55), stroke);
      case 'square':
        for (var i = -1; i <= 1; i += 2) {
          for (var j = -1; j <= 1; j += 2) {
            canvas.drawRect(Rect.fromCenter(center: c + Offset(i * r * 0.26, j * r * 0.26), width: r * 0.36, height: r * 0.36), light);
          }
        }
      case 'shake':
        final path = Path()..moveTo(c.dx - r * 0.6, c.dy);
        for (var i = 0; i <= 12; i++) {
          final x = c.dx - r * 0.6 + i * r * 0.1;
          path.lineTo(x, c.dy + (i.isEven ? -1 : 1) * r * 0.22);
        }
        canvas.drawPath(path, stroke..strokeWidth = r * 0.1);
    }
  }

  Path _star(Offset c, double outer, double inner, int points) {
    final path = Path();
    for (var i = 0; i < points * 2; i++) {
      final radius = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / points;
      final p = c + Offset(math.cos(a), math.sin(a)) * radius;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_GoboPainter old) => old.glyph != glyph;
}

/// Colour-wheel names → swatch colours. Order matters: longer, more
/// specific names come first, so "light blue" isn't read as plain "blue".
const _colorKeywords = <(List<String>, Color)>[
  (['light blue', 'világoskék', 'sky', 'égkék'], Color(0xFF5BC0F0)),
  (['dark blue', 'sötétkék', 'deep blue'], Color(0xFF1A2FB8)),
  (['light green', 'világoszöld', 'lime'], Color(0xFF9BE15D)),
  (['dark green', 'sötétzöld'], Color(0xFF1F7A3A)),
  (['congo', 'uv', 'ultraviolet', 'ultraibolya'], Color(0xFF6A2BD9)),
  (['cto', 'warm', 'meleg', '3200'], Color(0xFFFFC488)),
  (['ctb', 'cold', 'cool', 'hideg', '5600', '6500'], Color(0xFFD5E8FF)),
  (['white', 'fehér', 'open', 'nyitott', 'no function', 'no colo', 'nincs'], Color(0xFFFFFFFF)),
  (['red', 'piros', 'vörös'], Color(0xFFE53935)),
  (['orange', 'narancs', 'amber', 'borostyán'], Color(0xFFFF9800)),
  (['yellow', 'sárga'], Color(0xFFFDD835)),
  (['green', 'zöld'], Color(0xFF43A047)),
  (['cyan', 'türkiz', 'cián', 'turquoise', 'aqua'], Color(0xFF00BCD4)),
  (['blue', 'kék'], Color(0xFF1E40D8)),
  (['magenta', 'bíbor'], Color(0xFFD81B9A)),
  (['pink', 'rózsaszín', 'rose'], Color(0xFFFF6FAE)),
  (['purple', 'violet', 'lila', 'lavender'], Color(0xFF8E3FD0)),
];

Color? _colorFromHex(String hex) {
  final cleaned = hex.trim().replaceFirst('#', '');
  if (cleaned.length != 6) return null;
  final value = int.tryParse(cleaned, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}

Color? _colorFromWords(String text) {
  final lower = text.toLowerCase();
  for (final (words, color) in _colorKeywords) {
    if (words.any(lower.contains)) return color;
  }
  return null;
}

/// What a colour-wheel slot looks like: one colour, two for a split
/// ("half") colour, or null when neither the profile nor the label says.
List<Color>? wheelColorsFor(ChannelCapability capability) {
  final hex = capability.colorHex;
  if (hex != null) {
    final parts = hex.split('/').map(_colorFromHex).whereType<Color>().toList();
    if (parts.isNotEmpty) return parts.take(2).toList();
  }
  // "Red/Yellow", "red + yellow", "Red-Yellow half": two colours named.
  final halves = capability.label.split(RegExp(r'\s*(?:/|\+|&|-|–| and | és )\s*'));
  if (halves.length >= 2) {
    final first = _colorFromWords(halves[0]);
    final second = _colorFromWords(halves.sublist(1).join(' '));
    if (first != null && second != null && first != second) return [first, second];
  }
  final single = _colorFromWords(capability.label);
  return single == null ? null : [single];
}

/// The colours the range editor offers for a wheel slot.
const wheelColorChoices = <String, String>{
  'White': '#FFFFFF',
  'Red': '#E53935',
  'Orange': '#FF9800',
  'Yellow': '#FDD835',
  'Light green': '#9BE15D',
  'Green': '#43A047',
  'Cyan': '#00BCD4',
  'Light blue': '#5BC0F0',
  'Blue': '#1E40D8',
  'Purple': '#8E3FD0',
  'Magenta': '#D81B9A',
  'Pink': '#FF6FAE',
  'UV': '#6A2BD9',
  'CTO': '#FFC488',
  'CTB': '#D5E8FF',
};

/// A colour-wheel swatch: solid, split in two for a half colour, or a grey
/// numbered tile when the colour isn't known.
class WheelSwatch extends StatelessWidget {
  final List<Color>? colors;
  final String fallbackText;
  final double size;
  final bool selected;

  const WheelSwatch({super.key, required this.colors, this.fallbackText = '', this.size = 40, this.selected = false});

  @override
  Widget build(BuildContext context) {
    final colors = this.colors;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors == null ? AppColors.panel2 : colors.first,
        gradient: colors != null && colors.length > 1
            ? LinearGradient(colors: [colors[0], colors[0], colors[1], colors[1]], stops: const [0, 0.5, 0.5, 1])
            : null,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: selected ? AppColors.accent : AppColors.border, width: selected ? 2.5 : 1.5),
      ),
      alignment: Alignment.center,
      child: colors == null
          ? Text(fallbackText, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textDim))
          : null,
    );
  }
}
