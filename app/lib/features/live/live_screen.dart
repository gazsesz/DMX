import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../manual_control/manual_control_screen.dart';
import 'live_grid_view.dart';

/// The Live tab: the Grid for running the show, the Desk (the channel
/// sliders that used to be the whole tab) for testing and fine-tuning.
class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  int _view = 0;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    // On a phone the clock chip needs the room: icons only.
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final switcher = SegmentedButton<int>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(value: 0, label: narrow ? null : Text(l.liveViewGrid), tooltip: l.liveViewGrid, icon: const Icon(Icons.grid_on, size: 18)),
        ButtonSegment(value: 1, label: narrow ? null : Text(l.liveViewDesk), tooltip: l.liveViewDesk, icon: const Icon(Icons.tune, size: 18)),
      ],
      selected: {_view},
      onSelectionChanged: (s) => setState(() => _view = s.first),
    );
    return Column(
      children: [
        Material(
          color: Theme.of(context).appBarTheme.backgroundColor,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  switcher,
                  const Spacer(),
                  if (_view == 0)
                    const Flexible(
                      flex: 100,
                      child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: LiveClockChip()),
                    ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(
            index: _view,
            children: const [LiveGridView(), ManualControlScreen()],
          ),
        ),
      ],
    );
  }
}
