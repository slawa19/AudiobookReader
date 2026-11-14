import 'package:material_ui/material_ui.dart';

import '../../library/fake_library.dart';
import '../../screens/reader_screen.dart';
import '../../screens/strings.dart';
import '../app.dart';

/// Только прототип: вместо системного окна выбора файла — лист с несколькими «файлами», каждый из которых
/// показывает свой исход добавления (FR-L2, FR-L3, FR-B2, FR-B6).
Future<void> showDemoFilePicker(BuildContext context, Prototype p) async {
  final picked = await showModalBottomSheet<({String name, String kind})>(
    context: context,
    useSafeArea: true,
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      return SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
            child: Text(S.pickerTitle, style: theme.textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(S.pickerNote, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
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
        ]),
      );
    },
  );
  if (picked == null || !context.mounted) return;
  final existing = p.library.addDemoFile(picked.name, picked.kind);
  if (existing != null) {
    // Тот же файл уже на полке — открывается имеющаяся книга (FR-L3).
    final book = await p.library.loadBook(existing);
    p.library.markOpened(existing);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ReaderScreen(services: p.services, book: book),
    ));
  }
}
