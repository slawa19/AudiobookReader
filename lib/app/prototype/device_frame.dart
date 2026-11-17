import 'package:material_ui/material_ui.dart';

import '../../library/settings.dart';

/// Только прототип в браузере: приложение внутри рамки телефона заданного размера в dp, с переключателем
/// размеров и масштаба шрифта. Окно браузера любой ширины не растягивает экран телефона.
class DeviceFrame extends StatefulWidget {
  const DeviceFrame({super.key, required this.child, this.settings});

  final Widget child;

  /// Для быстрого переключателя языка интерфейса над рамкой.
  final AppSettings? settings;

  @override
  State<DeviceFrame> createState() => _DeviceFrameState();
}

class _Device {
  const _Device(this.label, this.width, this.height, this.textScale);

  final String label;
  final double width;
  final double height;
  final double textScale;
}

const _devices = [
  _Device('360 × 800', 360, 800, 1),
  _Device('393 × 852', 393, 852, 1),
  _Device('412 × 915', 412, 915, 1),
  _Device('320 × 640, шрифт ×1,3', 320, 640, 1.3),
];

class _DeviceFrameState extends State<DeviceFrame> {
  int _device = 2;

  @override
  Widget build(BuildContext context) {
    final d = _devices[_device];
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Читалка — прототип',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFA8431F), brightness: Brightness.dark),
      ),
      home: Builder(builder: (context) {
        final outer = MediaQuery.of(context);
        final phone = outer.copyWith(
          size: Size(d.width, d.height),
          padding: const EdgeInsets.only(top: 32, bottom: 20),
          viewPadding: const EdgeInsets.only(top: 32, bottom: 20),
          viewInsets: EdgeInsets.zero,
          textScaler: TextScaler.linear(d.textScale),
        );
        return Scaffold(
          backgroundColor: const Color(0xFF1E1C1A),
          body: SafeArea(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    SegmentedButton<int>(
                      segments: [
                        for (var i = 0; i < _devices.length; i++)
                          ButtonSegment(value: i, label: Text(_devices[i].label)),
                      ],
                      selected: {_device},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => setState(() => _device = s.first),
                    ),
                    if (widget.settings != null)
                      ListenableBuilder(
                        listenable: widget.settings!,
                        builder: (context, _) => SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: '', label: Text('Система')),
                            ButtonSegment(value: 'ru', label: Text('RU')),
                            ButtonSegment(value: 'en', label: Text('EN')),
                            ButtonSegment(value: 'pl', label: Text('PL')),
                            ButtonSegment(value: 'de', label: Text('DE')),
                            ButtonSegment(value: 'uk', label: Text('UK')),
                          ],
                          selected: {widget.settings!.language ?? ''},
                          showSelectedIcon: false,
                          onSelectionChanged: (s) => widget.settings!.language = s.first.isEmpty ? null : s.first,
                        ),
                      ),
                    Text(
                      'Долгое нажатие на «Книги» — состояния для показа',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: FittedBox(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B0A09),
                        borderRadius: BorderRadius.circular(46),
                        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 12))],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(36),
                        child: SizedBox(
                          width: d.width,
                          height: d.height,
                          child: MediaQuery(data: phone, child: widget.child),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }
}
