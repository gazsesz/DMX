import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/fixtures/fixture_library_asset.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../state/fixture_providers.dart';

/// Browses the fixture library that ships with the app: pick a
/// manufacturer, pick a model, pick a DMX mode, and it lands in the
/// project's fixture list ready to patch.
///
/// Two lists rather than one flat searchable table, because 1738 fixtures
/// across 147 brands is too many to scroll — but the search box searches
/// across every brand at once for when you know the model name and not who
/// makes it.
class FixtureLibraryBrowser extends ConsumerStatefulWidget {
  const FixtureLibraryBrowser({super.key});

  @override
  ConsumerState<FixtureLibraryBrowser> createState() => _FixtureLibraryBrowserState();
}

class _FixtureLibraryBrowserState extends ConsumerState<FixtureLibraryBrowser> {
  final _search = TextEditingController();
  late Future<List<LibraryManufacturer>> _manufacturers;
  LibraryManufacturer? _selected;
  Future<List<LibraryFixture>>? _fixtures;

  /// Results of a cross-manufacturer search, filled in on demand — this is
  /// the one operation that has to open every manufacturer file, so it only
  /// runs when someone actually types.
  List<LibraryFixture>? _searchResults;
  bool _searching = false;

  FixtureLibraryAsset get _asset => ref.read(fixtureLibraryAssetProvider);

  @override
  void initState() {
    super.initState();
    _manufacturers = _asset.manufacturers();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(LibraryManufacturer manufacturer) {
    setState(() {
      _selected = manufacturer;
      _fixtures = _asset.fixturesOf(manufacturer);
    });
  }

  Future<void> _runSearch(String rawQuery) async {
    final query = rawQuery.trim().toLowerCase();
    if (query.length < 2) {
      setState(() {
        _searchResults = null;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    final all = await _manufacturers;
    final matches = <LibraryFixture>[];
    for (final manufacturer in all) {
      // A brand-name match brings in everything it makes; otherwise only
      // the models whose name matches.
      final brandMatches = manufacturer.name.toLowerCase().contains(query);
      if (!brandMatches && matches.length > 200) continue;
      final fixtures = await _asset.fixturesOf(manufacturer);
      for (final fixture in fixtures) {
        if (brandMatches || fixture.model.toLowerCase().contains(query)) {
          matches.add(fixture);
        }
      }
      if (matches.length > 400) break;
    }
    if (!mounted || _search.text.trim().toLowerCase() != query) return;
    setState(() {
      _searchResults = matches;
      _searching = false;
    });
  }

  /// Adds [mode] of [fixture] to the project and closes the browser,
  /// handing the new profile back so the caller can patch it immediately.
  void _add(LibraryFixture fixture, LibraryMode mode) {
    final profile = ref
        .read(fixtureLibraryProvider.notifier)
        .addProfile(fixture.toProfile(mode));
    Navigator.of(context).pop(profile);
  }

  Future<void> _pickMode(LibraryFixture fixture) async {
    if (fixture.modes.length == 1) {
      _add(fixture, fixture.modes.first);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.panel,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(
                '${fixture.manufacturer} ${fixture.model}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Pick the DMX mode the fixture itself is set to — the channel '
                'layout differs between modes.',
                style: TextStyle(fontSize: 10.5, color: AppColors.textFaint),
              ),
            ),
            for (final mode in fixture.modes)
              ListTile(
                dense: true,
                leading: const Icon(Icons.tune, size: 18, color: AppColors.accent2),
                title: Text(mode.name, style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                  '${mode.channelCount} channels · '
                  '${mode.channels.where((c) => c.hasCapabilities).length} with named ranges',
                  style: appMonoStyle(fontSize: 10, color: AppColors.textFaint),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _add(fixture, mode);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _fixtureTile(LibraryFixture fixture, {bool showBrand = false}) {
    final modes = fixture.modes.length == 1
        ? '${fixture.modes.first.channelCount} channels'
        : '${fixture.modes.length} modes · '
              '${fixture.modes.map((m) => m.channelCount).reduce((a, b) => a < b ? a : b)}'
              '-${fixture.modes.map((m) => m.channelCount).reduce((a, b) => a > b ? a : b)} channels';
    return ListTile(
      dense: true,
      title: Text(
        showBrand ? '${fixture.manufacturer} ${fixture.model}' : fixture.model,
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        '${fixture.type} · $modes',
        style: appMonoStyle(fontSize: 10, color: AppColors.textFaint),
      ),
      trailing: const Icon(Icons.add, size: 18, color: AppColors.accent),
      onTap: () => _pickMode(fixture),
    );
  }

  Widget _manufacturerList() {
    return FutureBuilder<List<LibraryManufacturer>>(
      future: _manufacturers,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not read the bundled library.\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textFaint),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final manufacturers = snapshot.data!;
        return ListView.builder(
          itemCount: manufacturers.length,
          itemBuilder: (context, index) {
            final manufacturer = manufacturers[index];
            return ListTile(
              dense: true,
              title: Text(manufacturer.name, style: const TextStyle(fontSize: 13)),
              trailing: Text(
                '${manufacturer.fixtureCount}',
                style: appMonoStyle(fontSize: 11, color: AppColors.textFaint),
              ),
              onTap: () => _open(manufacturer),
            );
          },
        );
      },
    );
  }

  Widget _modelList() {
    return FutureBuilder<List<LibraryFixture>>(
      future: _fixtures,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final fixtures = snapshot.data!;
        return ListView.builder(
          itemCount: fixtures.length,
          itemBuilder: (context, index) => _fixtureTile(fixtures[index]),
        );
      },
    );
  }

  Widget _searchList() {
    if (_searching) return const Center(child: CircularProgressIndicator());
    final results = _searchResults ?? const <LibraryFixture>[];
    if (results.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Nothing matched', style: TextStyle(color: AppColors.textFaint)),
        ),
      );
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) => _fixtureTile(results[index], showBrand: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    final searching = _search.text.trim().length >= 2;
    final title = searching
        ? 'Search'
        : _selected?.name ?? 'Fixture Library';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: _selected != null && !searching
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _selected = null;
                  _fixtures = null;
                }),
              )
            : null,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: 'Search all manufacturers and models',
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 17),
                        onPressed: () {
                          _search.clear();
                          _runSearch('');
                        },
                      ),
              ),
              onChanged: (value) {
                setState(() {});
                _runSearch(value);
              },
            ),
          ),
          Expanded(
            child: searching
                ? _searchList()
                : _selected == null
                    ? _manufacturerList()
                    : _modelList(),
          ),
          const _LibraryFooter(),
        ],
      ),
    );
  }
}

/// The Apache-2.0 attribution the bundled definitions require, and a plain
/// statement of where they come from so nobody wonders why an unfamiliar
/// fixture is in the list.
class _LibraryFooter extends StatelessWidget {
  const _LibraryFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: const Text(
        'Fixture definitions from the Q Light Controller Plus project, '
        'used under the Apache License 2.0.',
        style: TextStyle(fontSize: 9.5, color: AppColors.textFaint),
      ),
    );
  }
}
