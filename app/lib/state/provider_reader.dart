import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reads a provider. Both `WidgetRef.read` (widgets) and `Ref.read`
/// (providers) fit this shape, so shared actions — firing a trigger,
/// blacking out — can be written once and called from either side instead of
/// a widget-only and a headless copy drifting apart.
typedef ReadProvider = T Function<T>(ProviderListenable<T> provider);

/// The container itself, so a caller holding any reader can get one that
/// outlives it — see [stableRead].
final providerContainerProvider = Provider<ProviderContainer>((ref) => ref.container);

/// A reader that keeps working for as long as the app does.
///
/// A widget's `ref.read` throws once that widget is gone. Anything that
/// hands a reader on to a running show — a player asking for the beat rate
/// or the fade on every step — must use this instead, or starting playback
/// from a sheet or an editor leaves the show frozen the moment that sheet
/// closes: the step loop dies on its next read while the player still
/// reports itself as playing.
ReadProvider stableRead(ReadProvider read) => read(providerContainerProvider).read;
