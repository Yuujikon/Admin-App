import 'package:flutter/material.dart';
import '../config/theme.dart';

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
              PopupMenuButton<String>(
                tooltip: 'Exclusion Filters',
                onSelected: null,
                itemBuilder: (context) {
                  return _localFilterOuts.keys.map((key) {
                    final isChecked = _localFilterOuts[key] ?? false;
                    return PopupMenuItem<String>(
                      enabled: false,
                      child: StatefulBuilder(
                        builder: (context, setMenuState) {
                          return InkWell(
                            onTap: () {
                              final updated = !isChecked;
                              setState(() {
                                _localFilterOuts[key] = updated;
                              });
                              setMenuState(() {});
                              if (widget.onFilterOutChanged != null) {
                                widget.onFilterOutChanged!(_localFilterOuts);
                              }
                            },
                            child: Row(
                              children: [
                                Checkbox(
                                  value: isChecked,
                                  onChanged: (val) {
                                    setState(() {
                                      _localFilterOuts[key] = val ?? false;
                                    });
                                    setMenuState(() {});
                                    if (widget.onFilterOutChanged != null) {
                                      widget.onFilterOutChanged!(
                                          _localFilterOuts);
                                    }
                                  },
                                ),
                                Expanded(
                                  child: Text(
                                    key,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    );
                  }).toList();
                },
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: _localFilterOuts.values.any((v) => v)
                        ? theme.colorScheme.primaryContainer
                        : (isDark
                            ? theme.colorScheme.surfaceContainerHigh
                            : Colors.white),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.filter_alt_outlined,
                        size: 18,
                        color: _localFilterOuts.values.any((v) => v)
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurface,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Filter Out',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _localFilterOuts.values.any((v) => v)
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Date Range Preset Filter Menu
            if (widget.dateFilter != null) ...[
              const SizedBox(width: 8),
              PopupMenuButton<AdminDateFilter>(
                tooltip: 'Date Range Filter',
                initialValue: widget.dateFilter,
                onSelected: widget.onDateFilterChanged,
                itemBuilder: (context) => AdminDateFilter.values
                    .map(
                      (f) => PopupMenuItem(
                        value: f,
                        child: Row(
                          children: [
                            Icon(
                              f == widget.dateFilter
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(f.label, style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: widget.dateFilter != AdminDateFilter.all
                        ? theme.colorScheme.primaryContainer
                        : (isDark
                            ? theme.colorScheme.surfaceContainerHigh
                            : Colors.white),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 16,
                        color: widget.dateFilter != AdminDateFilter.all
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurface,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.dateFilter!.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: widget.dateFilter != AdminDateFilter.all
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_drop_down_rounded,
                        size: 18,
                        color: widget.dateFilter != AdminDateFilter.all
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onSurface,
                      ),
                    ],
                  ),
                ),
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
