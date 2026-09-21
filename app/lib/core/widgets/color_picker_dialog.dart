import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/builtin_fixtures.dart';
import '../../state/color_palette_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Picks a colour for a group of fixtures: the named presets and your own
/// saved colours on one side, a full hue/saturation/brightness palette on
/// the other.
///
/// [onPreview] fires on every change while the dialog is open, so the rig
/// follows the slider live — picking a colour by looking at the lamps
/// rather than at the screen is the whole point of doing it here. Returns
/// the chosen `[r, g, b]`, or null if it was dismissed (in which case the
/// caller should put back whatever the group had).
Future<List<int>?> showColorPickerDialog(
  BuildContext context, {
  required List<int> initial,
  ValueChanged<List<int>>? onPreview,
}) {
  return showDialog<List<int>>(
    context: context,
    builder: (context) => ColorPickerDialog(initial: initial, onPreview: onPreview),
  );
}

class ColorPickerDialog extends ConsumerStatefulWidget {
  final List<int> initial;
  final ValueChanged<List<int>>? onPreview;

  const ColorPickerDialog({super.key, required this.initial, this.onPreview});

  @override
  ConsumerState<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

enum _Tab { swatches, palette }

class _ColorPickerDialogState extends ConsumerState<ColorPickerDialog> {
  _Tab _tab = _Tab.swatches;
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    final rgb = widget.initial;
    _hsv = HSVColor.fromColor(Color.fromARGB(255, rgb[0], rgb[1], rgb[2]));
    // A black or grey start has no hue of its own, which would drop the
    // palette's hue slider to red with no way to tell why. Keep it, but
    // open on something the user can actually see moving.
    if (_hsv.saturation == 0 && _hsv.value == 0) _hsv = const HSVColor.fromAHSV(1, 0, 1, 1);
  }

  List<int> get _rgb {
    final colour = _hsv.toColor();
    return [(colour.r * 255).round(), (colour.g * 255).round(), (colour.b * 255).round()];
  }

  void _setHsv(HSVColor value) {
    setState(() => _hsv = value);
    widget.onPreview?.call(_rgb);
  }

  void _pick(List<int> rgb) {
    widget.onPreview?.call(rgb);
    Navigator.of(context).pop(rgb);
  }

  @override
  Widget build(BuildContext context) {
    final custom = ref.watch(customColorsProvider);

    return AlertDialog(
      backgroundColor: AppColors.panel,
      insetPadding: const EdgeInsets.all(20),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      title: Row(
        children: [
          const Expanded(
            child: Text('Colour', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
          SegmentedButton<_Tab>(
            segments: const [
              ButtonSegment(value: _Tab.swatches, label: Text('Swatches')),
              ButtonSegment(value: _Tab.palette, label: Text('Palette')),
            ],
            selected: {_tab},
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onSelectionChanged: (selection) => setState(() => _tab = selection.first),
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: _tab == _Tab.swatches ? _swatches(custom) : _palette(custom),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () => _pick(_rgb), child: const Text('Use colour')),
      ],
    );
  }

  Widget _swatches(List<SavedColor> custom) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel('PRESETS'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in colorPresets.entries)
              _Swatch(rgb: entry.value, tooltip: entry.key, onTap: () => _pick(entry.value)),
          ],
        ),
        const SizedBox(height: 14),
        const _SectionLabel('MY COLOURS'),
        if (custom.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'Mix one on the Palette tab and save it — it shows up here, in every project.',
              style: TextStyle(fontSize: 11, color: AppColors.textFaint),
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final colour in custom)
                _NamedSwatch(
                  colour: colour,
                  onTap: () => _pick(colour.rgb),
                  onLongPress: () => _showColorOptions(colour),
                ),
            ],
          ),
      ],
    );
  }

  /// Rename or delete a saved colour — long-press on its swatch. Deleting
  /// stays a deliberate second step (not the long-press itself) now that
  /// there's something to lose besides the colour: its name.
  Future<void> _showColorOptions(SavedColor colour) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.panel,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(colour.name == null ? 'Name this colour' : 'Rename'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.danger),
              title: const Text('Delete', style: TextStyle(color: AppColors.danger)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'delete') {
      ref.read(customColorsProvider.notifier).remove(colour.rgb);
    } else if (action == 'rename') {
      final controller = TextEditingController(text: colour.name ?? '');
      final name = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.panel,
          title: const Text('Colour name'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'e.g. Deep Blue'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
          ],
        ),
      );
      if (name != null) ref.read(customColorsProvider.notifier).rename(colour.rgb, name);
    }
  }

  Widget _palette(List<SavedColor> custom) {
    final rgb = _rgb;
    final saved = custom.any((c) => c.rgb[0] == rgb[0] && c.rgb[1] == rgb[1] && c.rgb[2] == rgb[2]);
    final hueOnly = HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Color.fromARGB(255, rgb[0], rgb[1], rgb[2]),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border, width: 1.5),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('#${hexOf(rgb)}'.toUpperCase(), style: appMonoStyle(fontSize: 13)),
                  Text(
                    'R ${rgb[0]} · G ${rgb[1]} · B ${rgb[2]}',
                    style: appMonoStyle(fontSize: 11, color: AppColors.textDim),
                  ),
                  const SizedBox(height: 6),
                  OutlinedButton.icon(
                    onPressed: saved ? null : () => ref.read(customColorsProvider.notifier).add(rgb),
                    icon: Icon(saved ? Icons.check : Icons.bookmark_add_outlined, size: 16),
                    label: Text(saved ? 'Saved' : 'Save colour', style: const TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const _SectionLabel('HUE'),
        _GradientSlider(
          value: _hsv.hue / 360,
          colors: const [
            Color(0xFFFF0000),
            Color(0xFFFFFF00),
            Color(0xFF00FF00),
            Color(0xFF00FFFF),
            Color(0xFF0000FF),
            Color(0xFFFF00FF),
            Color(0xFFFF0000),
          ],
          onChanged: (v) => _setHsv(_hsv.withHue((v * 360).clamp(0, 360))),
        ),
        const _SectionLabel('SATURATION'),
        _GradientSlider(
          value: _hsv.saturation,
          colors: [Colors.white, hueOnly],
          onChanged: (v) => _setHsv(_hsv.withSaturation(v)),
        ),
        // Brightness here is the colour's own, not the dimmer: a par can
        // dims by scaling its emitters, which is exactly what this does.
        const _SectionLabel('BRIGHTNESS'),
        _GradientSlider(
          value: _hsv.value,
          colors: [Colors.black, HSVColor.fromAHSV(1, _hsv.hue, _hsv.saturation, 1).toColor()],
          onChanged: (v) => _setHsv(_hsv.withValue(v)),
        ),
        if (custom.isNotEmpty) ...[
          const SizedBox(height: 8),
          const _SectionLabel('MY COLOURS'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final colour in custom)
                _NamedSwatch(
                  colour: colour,
                  size: 34,
                  onTap: () => _setHsv(
                    HSVColor.fromColor(Color.fromARGB(255, colour.rgb[0], colour.rgb[1], colour.rgb[2])),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textFaint),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  final List<int> rgb;
  final String tooltip;
  final VoidCallback onTap;

  const _Swatch({required this.rgb, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Color.fromARGB(255, rgb[0], rgb[1], rgb[2]),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.border, width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// A saved colour's swatch with its name underneath — unlike a tooltip,
/// visible without a hover, which is the only kind of pointer a touch
/// console has.
class _NamedSwatch extends StatelessWidget {
  final SavedColor colour;
  final double size;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _NamedSwatch({required this.colour, required this.onTap, this.onLongPress, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      onLongPress: onLongPress,
      child: SizedBox(
        width: size + 12,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: Color.fromARGB(255, colour.rgb[0], colour.rgb[1], colour.rgb[2]),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppColors.border, width: 1.5),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              colour.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.textFaint),
            ),
          ],
        ),
      ),
    );
  }
}

/// A slider whose track *is* the range it picks from — the only honest way
/// to show a hue.
class _GradientSlider extends StatelessWidget {
  final double value;
  final List<Color> colors;
  final ValueChanged<double> onChanged;

  const _GradientSlider({required this.value, required this.colors, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: colors),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppColors.border),
            ),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 18,
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            ),
            child: Slider(value: value.clamp(0, 1), onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}
