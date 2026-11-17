import 'package:material_ui/material_ui.dart';

import '../../library/fake_library.dart';
import '../../screens/common.dart';
import '../../screens/reader_screen.dart';
import '../app.dart';

/// Prototype only: instead of the system file picker, a sheet with several "files", each of which
/// shows its own add outcome (FR-L2, FR-L3, FR-B2, FR-B6).
Future<void> showDemoFilePicker(BuildContext context, Prototype p) async {
  final picked = await showScrollableSheet<({String name, String kind})>(context, (context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      sheetTitle(context, l10n.pickerTitle),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        child: Text(l10n.pickerNote, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ),
      for (final f in FakeLibrary.demoFiles)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ListTile(
            key: Key('pick-${f.kind}'),
            leading: const Icon(Icons.description_outlined),
            title: Text(f.name),
            onTap: () => Navigator.pop(context, f),
          ),
        ),
      const SizedBox(height: 12),
    ]);
  });
  if (picked == null || !context.mounted) return;
  final existing = p.library.addDemoFile(picked.name, picked.kind);
  if (existing != null) {
    // The same file is already on the shelf — the existing book opens (FR-L3).
    final book = await p.library.loadBook(existing);
    p.library.markOpened(existing);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ReaderScreen(services: p.services, book: book),
    ));
  }
}
