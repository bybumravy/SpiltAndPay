import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Uses only the space occupied by the value; the label gets the rest.
class LabelValueRow extends StatelessWidget {
  final Widget label;
  final Widget value;
  final double maxValueFraction;
  const LabelValueRow({
    super.key,
    required this.label,
    required this.value,
    this.maxValueFraction = 0.48,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final maxValueWidth = constraints.hasBoundedWidth
          ? constraints.maxWidth * maxValueFraction
          : 200.0;
      var stack = false;
      if (value case Text(data: final String text)) {
        final style = DefaultTextStyle.of(context).style
            .merge((value as Text).style);
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        stack = constraints.hasBoundedWidth && painter.width > maxValueWidth;
        painter.dispose();
      }
      if (stack) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            label,
            const SizedBox(height: 6),
            DefaultTextStyle.merge(textAlign: TextAlign.end, child: value),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: label),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxValueWidth),
            child: DefaultTextStyle.merge(
              textAlign: TextAlign.end,
              child: value,
            ),
          ),
        ],
      );
    },
  );
}

/// The group shrinks with its content; extra people use one count slot.
class MemberAvatarGroup extends StatelessWidget {
  final List<String> names;
  const MemberAvatarGroup({super.key, required this.names});
  static const diameter = 36.0;
  static const step = 24.0;

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) return const SizedBox.shrink();
    final visible = names.length.clamp(1, 3);
    return Semantics(
      label: '${names.length} thành viên',
      child: ExcludeSemantics(
        child: SizedBox(
          width: diameter + (visible - 1) * step,
          height: diameter,
          child: Stack(
            children: [
              for (var i = 0; i < visible; i++)
                Positioned(
                  left: i * step,
                  child: CircleAvatar(
                    radius: diameter / 2,
                    backgroundColor: Colors.white,
                    child: names.length > 3 && i == 2
                        ? CircleAvatar(
                            radius: 16,
                            backgroundColor: AppTheme.soft,
                            foregroundColor: AppTheme.purple,
                            child: Text(
                              '+${names.length - 2}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : InitialAvatar(names[i], radius: 16),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
