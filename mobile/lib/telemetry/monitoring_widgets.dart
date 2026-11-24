import 'package:material_ui/material_ui.dart';

import '../ui/console_style.dart';

String captureProfileLabel(String? value) => switch (value) {
  'light' => '轻量',
  'balanced' => '均衡',
  'extended' => '扩展',
  _ => '档位未确认',
};

enum MonitorStatus {
  normal('正常', Icons.check_circle),
  limited('受限', Icons.warning_rounded),
  failed('异常', Icons.error),
  unknown('未知', Icons.remove_circle);

  const MonitorStatus(this.label, this.icon);
  final String label;
  final IconData icon;

  Color color(BuildContext context) => switch (this) {
    normal => ConsoleColors.successOf(context),
    limited => ConsoleColors.warningOf(context),
    failed => Theme.of(context).colorScheme.error,
    unknown => Theme.of(context).colorScheme.onSurfaceVariant,
  };

  Widget indicator(BuildContext context, {double size = 18}) =>
      Icon(icon, size: size, color: color(context), semanticLabel: label);
}

Future<void> showMonitoringSheet(
  BuildContext context,
  WidgetBuilder builder, {
  double heightFraction = .76,
}) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => SafeArea(
    top: false,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * heightFraction,
        ),
        child: Builder(builder: builder),
      ),
    ),
  ),
);

class MonitoringSheetBody extends StatelessWidget {
  const MonitoringSheetBody(this.title, {super.key, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
    shrinkWrap: true,
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
    children: [ConsoleHeading(title), const SizedBox(height: 12), ...children],
  );
}
