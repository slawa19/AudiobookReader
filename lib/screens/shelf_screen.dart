import 'package:material_ui/material_ui.dart';

import '../library/library.dart';
import 'common.dart';
import 'reader_screen.dart';
import 'services.dart';
import 'settings_screen.dart';

/// The shelf (FR-L2, FR-L4, FR-L5). The last opened book — a large "Continue" card.
class ShelfScreen extends StatefulWidget {
  const ShelfScreen({super.key, required this.services});

  final AppServices services;

  @override
  State<ShelfScreen> createState() => _ShelfScreenState();
}

class _ShelfScreenState extends State<ShelfScreen> {
  AppServices get services => widget.services;
  Library get library => services.library;

  /// A book is opening: a repeated tap while `book.json` is being read does not open a second screen.
  bool _opening = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: Listenable.merge([library, services.audio]),
      builder: (context, _) {
        final books = library.shelf;
        // "Continue" is only for a book that was opened (the last opened one). Never-opened ones go first
        // under the card, new on top; the rest — by time of last opening (FR-L4, rule e).
        final continued = books.where((e) => e.opened).firstOrNull;
        final rows = [
          ...books.where((e) => !e.opened),
          ...books.where((e) => e.opened && e != continued),
        ];
        final jobs = library.addJobs;
        final empty = books.isEmpty && jobs.isEmpty;
        return Scaffold(
          floatingActionButton: empty
              ? null
              : FloatingActionButton(
                  tooltip: l10n.addBook,
                  onPressed: () => services.addBook(context),
                  child: const Icon(Icons.add_rounded, size: 28),
                ),
          // The list does not show through the system bar. The scroll tail
          // lifts the last row entirely above the add button.
          body: SafeArea(
            top: false,
            bottom: !empty,
            child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 8, 12),
                    child: Row(children: [
                      Expanded(
                        child: GestureDetector(
                          key: const Key('shelf-title'),
                          // Prototype only: long press on the heading — "Demo states".
                          onLongPress:
                              services.openDemoStates == null ? null : () => services.openDemoStates!(context),
                          child: Text(l10n.shelfTitle, style: bookTitleStyle(context, 30)),
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.settings,
                        icon: const Icon(Icons.settings_outlined),
                        onPressed: () => Navigator.of(context)
                            .push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(services: services))),
                      ),
                    ]),
                  ),
                ),
              ),
              if (empty)
                SliverFillRemaining(hasScrollBody: false, child: _EmptyShelf(onAdd: () => services.addBook(context)))
              else ...[
                for (final job in jobs) SliverToBoxAdapter(child: _AddJobRow(job: job, library: library)),
                if (continued != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: _ContinueCard(
                          entry: continued, onOpen: () => _open(continued), onMenu: () => _menu(continued)),
                    ),
                  ),
                SliverList.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final e = rows[i];
                    return _BookRow(entry: e, onOpen: () => _open(e), onMenu: () => _menu(e));
                  },
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 56 + 16 + 24)),
              ],
            ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _open(ShelfEntry e) async {
    if (_opening) return;
    _opening = true;
    try {
      final openBook = services.openBook;
      if (openBook != null) {
        await openBook(e);
        return;
      }
      final book = await library.loadBook(e.id);
      library.markOpened(e.id);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(services: services, book: book),
      ));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      _opening = false;
    }
  }

  Future<void> _menu(ShelfEntry e) async {
    final audioBytes = services.audio.bytesForBook(e.id);
    final choice = await showScrollableSheet<String>(context, (context) => _BookMenu(entry: e, audioBytes: audioBytes));
    if (!mounted || choice == null) return;
    final l10n = context.l10n;
    if (choice == 'narration') {
      final ok = await _confirm(context,
          icon: Icons.music_off_rounded,
          title: l10n.deleteNarrationTitle,
          body: l10n.deleteNarrationBody(e.title, formatBytes(l10n, audioBytes)),
          action: l10n.delete);
      if (ok) services.narration.deleteBookNarration(e.id);
    } else if (choice == 'book') {
      final ok = await _confirm(context,
          icon: Icons.delete_outline_rounded,
          title: l10n.deleteBookTitle,
          body: l10n.deleteBookBody(e.title, formatBytes(l10n, e.bookBytes + audioBytes)),
          action: l10n.delete);
      if (ok) services.narration.deleteBook(e.id);
    }
  }
}

Future<bool> _confirm(BuildContext context,
    {required IconData icon, required String title, required String body, required String action}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return AlertDialog(
        icon: Icon(icon),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.l10n.cancel)),
          FilledButton(
            key: const Key('confirm-delete'),
            style: FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError),
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      );
    },
  );
  return ok ?? false;
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.entry, required this.onOpen, required this.onMenu});

  final ShelfEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final fraction = entry.fraction;
    // On a narrow screen with a large font the cover and title are smaller so that a word is not broken in the middle.
    final narrow = MediaQuery.sizeOf(context).width / MediaQuery.textScalerOf(context).scale(1) < 330;
    return Card.filled(
      color: scheme.surfaceContainerLow,
      child: InkWell(
        onTap: onOpen,
        onLongPress: onMenu,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BookCover(entry: entry, width: narrow ? 60 : 92, radius: 10),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
                      child: Text(l10n.continueReading,
                          style: theme.textTheme.labelMedium?.copyWith(color: scheme.onPrimaryContainer)),
                    ),
                    const SizedBox(height: 10),
                    Text(entry.title,
                        style: bookTitleStyle(context, narrow ? 17 : 20), maxLines: 3, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(entry.author, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 14),
                    if (entry.chapterTitle?.isNotEmpty ?? false)
                      Text(entry.chapterTitle!, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value: fraction ?? 0,
                          minHeight: 6,
                          borderRadius: BorderRadius.circular(3),
                          // The 2024 Material 3 look; the flag is marked deprecated, but there is no other way to turn
                          // it on.
                          // ignore: deprecated_member_use
                          year2023: false,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(shelfProgress(l10n, fraction),
                          style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookRow extends StatelessWidget {
  const _BookRow({required this.entry, required this.onOpen, required this.onMenu});

  final ShelfEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final done = (entry.fraction ?? 0) >= 1;
    return InkWell(
      onTap: onOpen,
      onLongPress: onMenu,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            BookCover(entry: entry, width: 52, radius: 6),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.title, style: bookTitleStyle(context, 16.5), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(entry.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (!entry.opened || entry.fraction == null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(l10n.progressNew, style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
              )
            else
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (done) ...[
                  Icon(Icons.check_circle_rounded, size: 16, color: scheme.primary),
                  const SizedBox(width: 4),
                ],
                Text(shelfProgress(l10n, entry.fraction),
                    style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
          ],
        ),
      ),
    );
  }
}

class _AddJobRow extends StatelessWidget {
  const _AddJobRow({required this.job, required this.library});

  final AddJob job;
  final Library library;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final failed = job.status == AddJobStatus.failed;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Card.outlined(
        color: failed ? scheme.surface : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: failed
                    ? Icon(Icons.error_outline_rounded, color: scheme.error)
                    : const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(job.fileName, style: theme.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(failed && job.failure != null ? addFailureText(l10n, job.failure!) : l10n.adding,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: failed ? scheme.onSurface : scheme.onSurfaceVariant)),
                    if (job.technical != null)
                      Text(job.technical!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              if (failed)
                IconButton(
                  tooltip: l10n.dismiss,
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => library.dismissAddJob(job),
                )
              else
                const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 96),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(36)),
            child: Icon(Icons.auto_stories_rounded, size: 52, color: scheme.primary),
          ),
          const SizedBox(height: 24),
          Text(l10n.emptyTitle, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(l10n.emptyBody,
              textAlign: TextAlign.center, style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.addBook),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
          ),
        ],
      ),
    );
  }
}

class _BookMenu extends StatelessWidget {
  const _BookMenu({required this.entry, required this.audioBytes});

  final ShelfEntry entry;
  final int audioBytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Row(children: [
            BookCover(entry: entry, width: 44, radius: 6, elevated: false),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(entry.title, style: bookTitleStyle(context, 17), maxLines: 2, overflow: TextOverflow.ellipsis),
                Text('${entry.author} · ${formatBytes(l10n, entry.bookBytes + audioBytes)}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
              ]),
            ),
          ]),
        ),
        const Divider(indent: 16, endIndent: 16),
        const SizedBox(height: 8),
        if (audioBytes > 0)
          ListTile(
            leading: const Icon(Icons.music_off_rounded),
            title: Text(l10n.deleteNarration),
            trailing: Text(formatBytes(l10n, audioBytes),
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            onTap: () => Navigator.pop(context, 'narration'),
          ),
        ListTile(
          leading: Icon(Icons.delete_outline_rounded, color: scheme.error),
          title: Text(l10n.deleteBook, style: TextStyle(color: scheme.error)),
          onTap: () => Navigator.pop(context, 'book'),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
