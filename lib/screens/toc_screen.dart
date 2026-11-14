import 'package:material_ui/material_ui.dart';

import '../book/model.dart';
import '../playback/chapter_download.dart';
import '../tts/voices.dart';
import 'common.dart';
import 'services.dart';
import 'strings.dart';

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
    final book = widget.book;
    final downloads = widget.services.downloads;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: S.close, icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(S.contents),
          Text(book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        ]),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([downloads, widget.services.settings]),
        builder: (context, _) => ListView(
          padding: EdgeInsets.fromLTRB(12, 4, 12, 24 + MediaQuery.paddingOf(context).bottom),
          children: [
            for (var i = 0; i < book.chapters.length; i++) ...[
              _ChapterTile(
                key: i == widget.current ? _currentKey : Key('chapter-$i'),
                chapter: book.chapters[i],
                current: i == widget.current,
                voiced: downloads.isVoiced(book.id, i),
                onTap: () => Navigator.pop(context, i),
              ),
              if (i == widget.current) _DownloadBlock(services: widget.services, book: book, chapter: i),
            ],
          ],
        ),
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
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.download_done_rounded, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(S.voiced, style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
              ])
            : null,
        onTap: onTap,
      ),
    );
  }
}

class _DownloadBlock extends StatelessWidget {
  const _DownloadBlock({required this.services, required this.book, required this.chapter});

  final AppServices services;
  final Book book;
  final int chapter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final downloads = services.downloads;
    if (downloads.isVoiced(book.id, chapter)) return const SizedBox(height: 4);
    final task = downloads.task;
    final mine = task != null && task.bookId == book.id && task.chapter == chapter;
    final est = downloads.estimate(book, chapter, TtsModel.byId(services.settings.modelId), DateTime(2026, 11, 14));
    final minutes = (est.seconds / 60).ceil();
    final indent = (book.chapters[chapter].level - 1) * 24.0 + 16;

    final List<Widget> children;
    if (mine && task.status == DownloadStatus.running) {
      children = [
        Text(S.downloading((task.readySeconds / 60).floor(), minutes), style: theme.textTheme.bodyMedium),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          value: task.fraction,
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
          // ignore: deprecated_member_use
          year2023: false,
        ),
        const SizedBox(height: 8),
        Text(S.downloadingWhileOpen, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const Key('download-stop'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: downloads.stop,
            icon: const Icon(Icons.stop_rounded),
            label: const Text(S.stopDownload),
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
                Text(S.downloadFailed, style: theme.textTheme.titleSmall),
                Text(S.google(task.googleMessage ?? ''),
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
        ],
        Text(S.notVoiced(minutes), style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            key: const Key('download-start'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: () => downloads.start(book, chapter, TtsModel.byId(services.settings.modelId)),
            icon: const Icon(Icons.download_rounded),
            label: Text(S.downloadChapter(S.dollars(est.dollars))),
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
