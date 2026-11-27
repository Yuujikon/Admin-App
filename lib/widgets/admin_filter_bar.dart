import 'package:flutter/material.dart';
import '../config/theme.dart';
import 'gdc_popup_menu.dart';

/// Pre-defined date range filter options for data lists.
enum AdminDateFilter { all, today, thisWeek, thisMonth }

extension AdminDateFilterExt on AdminDateFilter {
  String get label => switch (this) {
        AdminDateFilter.all => 'All Time',
        AdminDateFilter.today => 'Today',
        AdminDateFilter.thisWeek => 'This Week',
        AdminDateFilter.thisMonth => 'This Month',
      };

  bool matches(DateTime date) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    switch (this) {
      case AdminDateFilter.all:
        return true;
      case AdminDateFilter.today:
        return date
            .isAfter(todayStart.subtract(const Duration(milliseconds: 1)));
      case AdminDateFilter.thisWeek:
        final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));
        return date
            .isAfter(weekStart.subtract(const Duration(milliseconds: 1)));
      case AdminDateFilter.thisMonth:
        final monthStart = DateTime(now.year, now.month, 1);
        return date
            .isAfter(monthStart.subtract(const Duration(milliseconds: 1)));
    }
  }
}

/// A comprehensive, reusable automated search and filtering bar component for admin data views.
/// Provides real-time text searching, category chips, status filters, date range filters,
/// filter-out exclusion toggles, active filter badges, and item match count display.
class AdminFilterBar extends StatefulWidget {
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final String searchHint;

  // Category Filtering
  final List<String>? categoryOptions;
  final String? selectedCategory;
  final ValueChanged<String>? onCategoryChanged;

  // Status Filtering
  final List<String>? statusOptions;
  final String? selectedStatus;
  final ValueChanged<String>? onStatusChanged;

  // Date Filtering
  final AdminDateFilter? dateFilter;
  final ValueChanged<AdminDateFilter>? onDateFilterChanged;

  // Exclusions / Filter-Out Toggles
  final Map<String, bool>? filterOutOptions;
  final ValueChanged<Map<String, bool>>? onFilterOutChanged;

  // Summary Count
  final int totalCount;
  final int filteredCount;
  final String itemUnit;

  // Extra Custom Controls
  final List<Widget>? extraActions;

  const AdminFilterBar({
    super.key,
    required this.searchQuery,
    required this.onSearchChanged,
    this.searchHint = 'Search by name, ID, barcode or details…',
    this.categoryOptions,
    this.selectedCategory,
    this.onCategoryChanged,
    this.statusOptions,
    this.selectedStatus,
    this.onStatusChanged,
    this.dateFilter,
    this.onDateFilterChanged,
    this.filterOutOptions,
    this.onFilterOutChanged,
    required this.totalCount,
    required this.filteredCount,
    this.itemUnit = 'items',
    this.extraActions,
  });

  @override
  State<AdminFilterBar> createState() => _AdminFilterBarState();
}

class _AdminFilterBarState extends State<AdminFilterBar> {
  late TextEditingController _searchCtrl;
  late Map<String, bool> _localFilterOuts;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController(text: widget.searchQuery);
    _localFilterOuts = Map.from(widget.filterOutOptions ?? {});
  }

  @override
  void didUpdateWidget(AdminFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != _searchCtrl.text) {
      _searchCtrl.text = widget.searchQuery;
    }
    if (widget.filterOutOptions != null) {
      _localFilterOuts = Map.from(widget.filterOutOptions!);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters {
    if (widget.searchQuery.isNotEmpty) return true;
    if (widget.selectedCategory != null && widget.selectedCategory != 'All') {
      return true;
    }
    if (widget.selectedStatus != null && widget.selectedStatus != 'All') {
      return true;
    }
    if (widget.dateFilter != null && widget.dateFilter != AdminDateFilter.all) {
      return true;
    }
    if (_localFilterOuts.values.any((v) => v)) return true;
    return false;
  }

  void _clearAllFilters() {
    _searchCtrl.clear();
    widget.onSearchChanged('');
    if (widget.onCategoryChanged != null) widget.onCategoryChanged!('All');
    if (widget.onStatusChanged != null) widget.onStatusChanged!('All');
    if (widget.onDateFilterChanged != null) {
      widget.onDateFilterChanged!(AdminDateFilter.all);
    }
    if (widget.onFilterOutChanged != null) {
      final reset = _localFilterOuts.map((k, v) => MapEntry(k, false));
      setState(() => _localFilterOuts = reset);
      widget.onFilterOutChanged!(reset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Row: Search Input Field + Filter-Out & Extra Action buttons
        Row(
          children: [
            Expanded(
              child: Container(
                height: 46,
                decoration: BoxDecoration(
                  color: isDark
                      ? theme.colorScheme.surfaceContainerHigh
                      : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color:
                        theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: widget.searchHint,
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.cancel_rounded, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              widget.onSearchChanged('');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  onChanged: (val) => widget.onSearchChanged(val.trim()),
                ),
              ),
            ),

            // Exclusion / Filter Out Button
            if (widget.filterOutOptions != null &&
                widget.filterOutOptions!.isNotEmpty) ...[
              const SizedBox(width: 8),
              Builder(
                builder: (context) {
                  final activeExclusions =
                      _localFilterOuts.values.where((v) => v).length;
                  return PopupMenuButton<String>(
                    tooltip: 'Exclusion Filters',
                    onSelected: null,
                    position: PopupMenuPosition.under,
                    offset: const Offset(0, 8),
                    elevation: 12,
                    shadowColor:
                        Colors.black.withValues(alpha: isDark ? 0.5 : 0.14),
                    surfaceTintColor: Colors.transparent,
                    color: theme.colorScheme.surface,
                    clipBehavior: Clip.antiAlias,
                    menuPadding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    constraints: const BoxConstraints(minWidth: 220),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: isDark ? 0.45 : 0.85),
                        width: 1,
                      ),
                    ),
                    itemBuilder: (context) {
                      return <PopupMenuEntry<String>>[
                        buildGdcPopupMenuHeader<String>(
                          context,
                          'Exclude From View',
                        ),
                        ..._localFilterOuts.keys.map((key) {
                          return PopupMenuItem<String>(
                            enabled: false,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 2, vertical: 2),
                            height: 44,
                            child: StatefulBuilder(
                              builder: (context, setMenuState) {
                                final isChecked =
                                    _localFilterOuts[key] ?? false;
                                void toggle() {
                                  setState(() {
                                    _localFilterOuts[key] = !isChecked;
                                  });
                                  setMenuState(() {});
                                  widget.onFilterOutChanged
                                      ?.call(_localFilterOuts);
                                }

                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: toggle,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isChecked
                                            ? theme.colorScheme.primary
                                                .withValues(
                                                    alpha: isDark ? 0.16 : 0.09)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                        border: isChecked
                                            ? Border.all(
                                                color: theme.colorScheme.primary
                                                    .withValues(alpha: 0.24),
                                                width: 1,
                                              )
                                            : null,
                                      ),
                                      child: Row(
                                        children: [
                                          AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 140),
                                            width: 20,
                                            height: 20,
                                            decoration: BoxDecoration(
                                              color: isChecked
                                                  ? theme.colorScheme.primary
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: isChecked
                                                    ? theme.colorScheme.primary
                                                    : theme.colorScheme
                                                        .onSurfaceVariant
                                                        .withValues(alpha: 0.5),
                                                width: 1.6,
                                              ),
                                            ),
                                            alignment: Alignment.center,
                                            child: isChecked
                                                ? Icon(
                                                    Icons.check_rounded,
                                                    size: 14,
                                                    color: theme
                                                        .colorScheme.onPrimary,
                                                  )
                                                : null,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              key,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: isChecked
                                                    ? FontWeight.w700
                                                    : FontWeight.w600,
                                                color: isChecked
                                                    ? theme.colorScheme.primary
                                                    : theme
                                                        .colorScheme.onSurface,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        }),
                      ];
                    },
                    child: GdcPopupPillTrigger(
                      label: 'Filter Out',
                      icon: Icons.filter_alt_outlined,
                      isActive: activeExclusions > 0,
                      activeBadgeCount: activeExclusions,
                      height: 46,
                      borderRadius: 14,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  );
                },
              ),
            ],

            // Date Range Preset Filter Menu
            if (widget.dateFilter != null) ...[
              const SizedBox(width: 8),
              GdcPopupMenuButton<AdminDateFilter>.pill(
                tooltip: 'Date Range Filter',
                menuTitle: 'Date Range',
                initialValue: widget.dateFilter,
                label: widget.dateFilter!.label,
                icon: Icons.calendar_today_rounded,
                isActive: widget.dateFilter != AdminDateFilter.all,
                height: 46,
                borderRadius: 14,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                onSelected: (f) => widget.onDateFilterChanged?.call(f),
                options: AdminDateFilter.values.map((f) {
                  final icon = switch (f) {
                    AdminDateFilter.all => Icons.all_inclusive_rounded,
                    AdminDateFilter.today => Icons.today_rounded,
                    AdminDateFilter.thisWeek => Icons.view_week_rounded,
                    AdminDateFilter.thisMonth => Icons.calendar_month_rounded,
                  };
                  return GdcPopupOption<AdminDateFilter>(
                    value: f,
                    label: f.label,
                    icon: icon,
                    isSelected: f == widget.dateFilter,
                  );
                }).toList(),
              ),
            ],

            if (widget.extraActions != null) ...widget.extraActions!,
          ],
        ),

        const SizedBox(height: 10),

        // Scrollable Filter Chips Row (Categories & Statuses)
        if ((widget.categoryOptions != null &&
                widget.categoryOptions!.length > 1) ||
            (widget.statusOptions != null &&
                widget.statusOptions!.length > 1)) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Category Chips
                if (widget.categoryOptions != null)
                  ...widget.categoryOptions!.map((cat) {
                    final isSelected = widget.selectedCategory == cat ||
                        (widget.selectedCategory == null && cat == 'All');
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        selected: isSelected,
                        label: Text(cat),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected
                              ? (isDark ? GdcColors.darkEmerald : Colors.white)
                              : theme.colorScheme.onSurface,
                        ),
                        backgroundColor: isDark
                            ? theme.colorScheme.surfaceContainerHigh
                            : const Color(0xFFF1F5F9),
                        selectedColor: isDark
                            ? GdcColors.emeraldPrimary
                            : GdcColors.darkEmerald,
                        checkmarkColor:
                            isDark ? GdcColors.darkEmerald : Colors.white,
                        onSelected: (val) {
                          if (widget.onCategoryChanged != null) {
                            widget.onCategoryChanged!(cat);
                          }
                        },
                      ),
                    );
                  }),

                // Divider if both Category & Status exist
                if (widget.categoryOptions != null &&
                    widget.statusOptions != null)
                  Container(
                    height: 24,
                    width: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    color: theme.colorScheme.outlineVariant,
                  ),

                // Status Chips
                if (widget.statusOptions != null)
                  ...widget.statusOptions!.map((st) {
                    final isSelected = widget.selectedStatus == st ||
                        (widget.selectedStatus == null && st == 'All');
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        selected: isSelected,
                        label: Text(st),
                        labelStyle: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.w500,
                          color: isSelected
                              ? theme.colorScheme.onSecondaryContainer
                              : theme.colorScheme.onSurface,
                        ),
                        selectedColor: theme.colorScheme.secondaryContainer,
                        onSelected: (val) {
                          if (widget.onStatusChanged != null) {
                            widget.onStatusChanged!(st);
                          }
                        },
                      ),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],

        // Bottom Info & Active Filter Badges Bar
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Results Match Summary Count
            Text(
              'Showing ${widget.filteredCount} of ${widget.totalCount} ${widget.itemUnit}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),

            // Clear All Filters Button
            if (_hasActiveFilters)
              InkWell(
                onTap: _clearAllFilters,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.filter_alt_off_rounded,
                        size: 14,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Reset Filters',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
