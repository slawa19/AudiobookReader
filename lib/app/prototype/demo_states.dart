import 'package:material_ui/material_ui.dart';

import '../../library/library.dart';
import '../../screens/reader_screen.dart';
import '../app.dart';

// ТОЛЬКО ПРОТОТИП. Панель «Состояния для показа»: включает состояния, которые в жизни вызывает сеть
// (preparing, waiting, ошибки 402/404/прочие, конец книги, ход и ошибка скачивания главы, отказы добавления),
// чтобы их можно было посмотреть без Gemini. В настоящем приложении этой панели и входа в неё нет.
// Вход: долгое нажатие на заголовок «Книги» на полке или на название книги в шапке экрана чтения.

Future<void> showDemoStates(BuildContext context, Prototype p) async {
  final inReader = context.findAncestorStateOfType<ReaderScreenState>() != null;
  final action = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => _DemoStatesSheet(prototype: p),
  );
  if (action == null || !context.mounted) return;

  final entry = _currentEntry(p);
  if (entry == null) return;
  final book = await p.library.loadBook(entry.id);
  final pos = p.library.positionOf(entry.id) ?? const ReadingPosition(0, 0);

  if (action.startsWith('player:')) {
    p.narration.demoShow(action.substring(7), book: book, fromBlock: pos.block);
  } else if (action.startsWith('download:')) {
    p.downloads.demoShow(book, book.chapterOf(pos.block), failed: action == 'download:failed');
  } else {
    return;
  }
  if (!inReader && context.mounted) {
    p.library.markOpened(entry.id);
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ReaderScreen(services: p.services, book: book),
    ));
  }
}

ShelfEntry? _currentEntry(Prototype p) {
  final id = p.narration.bookId;
  if (id != null) return p.library.entry(id);
  final shelf = p.library.shelf;
  return shelf.isEmpty ? null : shelf.first;
}

class _DemoStatesSheet extends StatelessWidget {
  const _DemoStatesSheet({required this.prototype});

  final Prototype prototype;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = prototype;
    Widget chip(String label, String action, {Key? key}) => ActionChip(
          key: key ?? Key('demo-$action'),
          label: Text(label),
          onPressed: () => Navigator.pop(context, action),
        );
    Widget section(String title, List<Widget> chips) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: theme.textTheme.titleSmall?.copyWith(color: scheme.primary)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: chips),
          ]),
        );

    return ListenableBuilder(
      listenable: Listenable.merge([p.library, p.settings]),
      builder: (context, _) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
              child: Row(children: [
                Icon(Icons.science_rounded, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(child: Text('Состояния для показа', style: theme.textTheme.titleLarge)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
              child: Text(
                'Только в прототипе. Состояния, которые в жизни вызывают сеть и Gemini. Состояния плеера и скачивания '
                'включаются у книги, которая сейчас открыта или слушается (иначе — у верхней на полке).',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
            section('Панель плеера', [
              chip('Готовлю голос…', 'player:preparing'),
              chip('Жду связь…', 'player:waiting'),
              chip('Играет', 'player:playing'),
              chip('Пауза + таймер сна', 'player:sleep'),
              chip('Ошибка 402: нет денег', 'player:error402'),
              chip('Ошибка 404: модель', 'player:error404'),
              chip('Прочая ошибка Google', 'player:errorOther'),
              chip('Книга закончилась', 'player:end'),
            ]),
            section('Скачать главу', [
              chip('Идёт (40 %)', 'download:running'),
              chip('Ошибка скачивания', 'download:failed'),
            ]),
            section('Добавление книги', [
              ActionChip(key: const Key('demo-add-adding'), label: const Text('Добавляется…'), onPressed: () => p.library.demoAddJob('adding')),
              ActionChip(key: const Key('demo-add-unsupported'), label: const Text('Формат не поддерживается'), onPressed: () => p.library.demoAddJob('unsupported')),
              ActionChip(key: const Key('demo-add-broken'), label: const Text('Не удалось прочитать'), onPressed: () => p.library.demoAddJob('broken')),
              ActionChip(key: const Key('demo-add-drm'), label: const Text('Защищена от копирования'), onPressed: () => p.library.demoAddJob('drm')),
              ActionChip(label: const Text('Убрать строки'), onPressed: p.library.clearAddJobs),
            ]),
            const SizedBox(height: 8),
            SwitchListTile(
              key: const Key('demo-empty'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              title: const Text('Пустая полка'),
              value: p.library.demoEmptyShelf,
              onChanged: p.library.setDemoEmptyShelf,
            ),
            SwitchListTile(
              key: const Key('demo-no-key'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              title: const Text('Нет ключа Gemini'),
              subtitle: const Text('«Слушать» ведёт в настройки на поле ключа'),
              value: !p.settings.hasApiKey,
              onChanged: (noKey) => p.settings.apiKey = noKey ? null : 'AIzaSyD-prototype-key-a1f3',
            ),
          ],
        ),
      ),
    );
  }
}
