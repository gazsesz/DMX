import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reads a provider. Both `WidgetRef.read` (widgets) and `Ref.read`
/// (providers) fit this shape, so shared actions — firing a trigger,
/// blacking out — can be written once and called from either side instead of
/// a widget-only and a headless copy drifting apart.
typedef ReadProvider = T Function<T>(ProviderListenable<T> provider);
