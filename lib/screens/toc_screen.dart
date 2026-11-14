import 'package:material_ui/material_ui.dart';

import '../book/model.dart';
import '../playback/chapter_download.dart';
import '../tts/voices.dart';
import 'common.dart';
import 'services.dart';

/// Оглавление (FR-R4) и «Скачать главу» для текущей главы (FR-D2, А§6.7). Возвращает выбранную главу.
class TocScreen extends StatefulWidget {
  const TocScreen({super.key, required this.services, required this.book, required this.current});

  final AppServices services;
  final Book book;
  final int current;

  @override
  State<TocScreen> createState() => _TocScreenState();
}

class _TocScreenState extends State<TocScreen> {
  final _currentKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _currentKey.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0.3);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final book = widget.book;
    final downloads = widget.services.downloads;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: l10n.close, icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l10n.contents),
          Text(book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ]),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([downloads, widget.services.settings, widget.services.library]),
        builder: (context, _) {
          // Готовность и оценка — для действующего профиля голоса книги (FR-D2, правило g).
          final profile = downloads.profileFor(book.id);
          final task = downloads.task;
          final running = task != null && task.status == DownloadStatus.running;
          // Блок задачи (ход или ошибка) — у той главы, которой она принадлежит, даже если читатель уже в другой;
          // предложение скачать — у текущей главы и только когда никакая задача не идёт.
          int? blockAt(int i) {
            if (task != null && task.bookId == book.id && task.chapter == i) return i;
            if (i == widget.current && !running && !downloads.isVoiced(book.id, i, profile)) return i;
            return null;
          }

          return ListView(
            padding: EdgeInsets.fromLTRB(12, 4, 12, 24 + MediaQuery.paddingOf(context).bottom),
            children: [
              for (var i = 0; i < book.chapters.length; i++) ...[
                _ChapterTile(
                  key: i == widget.current ? _currentKey : Key('chapter-$i'),
                  chapter: book.chapters[i],
                  current: i == widget.current,
                  voiced: downloads.isVoiced(book.id, i, profile),
                  onTap: () => Navigator.pop(context, i),
                ),
                if (blockAt(i) != null)
                  _DownloadBlock(services: widget.services, book: book, chapter: i, profile: profile)
                else if (i == widget.current)
                  const SizedBox(height: 4),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ChapterTile extends StatelessWidget {
  const _ChapterTile({super.key, required this.chapter, required this.current, required this.voiced, required this.onTap});

  final Chapter chapter;
  final bool current;
  final bool voiced;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final top = chapter.level == 1;
    // На подсветке выбранной строки — основной цвет текста: второстепенный на `hl` в сепии даёт 4,2 (№17 ревью).
    final markColor = current ? scheme.onSurface : scheme.onSurfaceVariant;
    return Padding(
      padding: EdgeInsets.only(left: (chapter.level - 1) * 24.0, top: top ? 6 : 0),
      child: ListTile(
        selected: current,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        minTileHeight: 52,
        title: Text(
          chapter.title,
          style: bookTitleStyle(context, top ? 17 : 16, weight: top || current ? FontWeight.w700 : FontWeight.w400)
              .copyWith(color: current ? scheme.primary : scheme.onSurface),
        ),
        trailing: voiced
            ? Row(key: const Key('voiced-mark'), mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.download_done_rounded, size: 18, color: markColor),
                const SizedBox(width: 4),
                Text(context.l10n.voiced, style: theme.textTheme.labelMedium?.copyWith(color: markColor)),
              ])
            : null,
        onTap: onTap,
      ),
    );
  }
}

class _DownloadBlock extends StatelessWidget {
  const _DownloadBlock({required this.services, required this.book, required this.chapter, required this.profile});

  final AppServices services;
  final Book book;
  final int chapter;
  final VoiceProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final downloads = services.downloads;
    final task = downloads.task;
    final mine = task != null && task.bookId == book.id && task.chapter == chapter;
    // Оценка — остаток для действующего профиля: после «Остановить» и после ошибки — не цена всей главы.
    final est = downloads.estimate(book, chapter, profile);
    final minutes = (est.seconds / 60).ceil();
    final indent = (book.chapters[chapter].level - 1) * 24.0 + 16;

    final List<Widget> children;
    if (mine && task.status == DownloadStatus.running) {
      children = [
        Text(l10n.downloading((task.readySeconds / 60).floor(), (task.totalSeconds / 60).ceil()),
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          value: task.fraction,
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
          // Внешний вид Material 3 2024 года; флаг помечен устаревшим, но другого способа включить его нет.
          // ignore: deprecated_member_use
          year2023: false,
        ),
        const SizedBox(height: 8),
        Text(l10n.downloadingWhileOpen, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('download-stop'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: downloads.stop,
            icon: const Icon(Icons.stop_rounded),
            label: Text(l10n.stopDownload),
          ),
        ),
      ];
    } else {
      final failed = mine && task.status == DownloadStatus.failed;
      children = [
        if (failed) ...[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.error_outline_rounded, size: 20, color: scheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l10n.downloadFailed, style: theme.textTheme.titleSmall),
                Text(l10n.google(task.googleMessage ?? ''),
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
        ],
        // Оценка — отдельной строкой перед кнопкой (FR-D2).
        Text(l10n.notVoicedEstimate(minutes, est.dollars),
            key: const Key('download-estimate'),
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            key: const Key('download-start'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: () => downloads.start(book, chapter, profile),
            icon: Icon(failed ? Icons.refresh_rounded : Icons.download_rounded),
            label: Text(failed ? l10n.downloadAgain : l10n.downloadChapter),
          ),
        ),
      ];
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(indent, 4, 8, 12),
      child: Card.outlined(
        shape: RoundedRectangleBorder(
          side: BorderSide(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(20),
        ),
        color: scheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      ),
    );
  }
}
