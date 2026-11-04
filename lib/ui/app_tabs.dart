import 'package:flutter/material.dart';

import 'app_theme.dart';

/// One tab treatment for peer sections and list filters across the app.
class AppTabs extends StatelessWidget implements PreferredSizeWidget {
  final TabController controller;
  final List<String> labels;
  final ValueChanged<int>? onTap;

  const AppTabs({
    super.key,
    required this.controller,
    required this.labels,
    this.onTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scrollable =
          constraints.maxWidth < 340 ||
          MediaQuery.textScalerOf(context).scale(15) > 18;
      return TabBar(
        controller: controller,
        onTap: onTap,
        isScrollable: scrollable,
        tabAlignment: scrollable ? TabAlignment.start : TabAlignment.fill,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        labelPadding: EdgeInsets.symmetric(horizontal: scrollable ? 18 : 8),
        labelColor: AppTheme.purple,
        unselectedLabelColor: AppTheme.muted,
        labelStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: 'Roboto',
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        indicatorSize: TabBarIndicatorSize.label,
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(color: AppTheme.purple, width: 3),
          borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
        ),
        dividerColor: AppTheme.line,
        overlayColor: WidgetStateProperty.all(AppTheme.soft),
        tabs: [
          for (final label in labels)
            Tab(height: 52, child: Text(label, maxLines: 1)),
        ],
      );
    },
  );
}

class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  const AppEmptyState({super.key, required this.icon, required this.title});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 64),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppTheme.soft,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon, color: AppTheme.purple, size: 28),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    ),
  );
}
