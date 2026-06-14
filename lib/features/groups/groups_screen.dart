import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/gradient_background.dart';
import '../../models/channel_group.dart';
import '../../providers/groups_provider.dart';

class GroupsScreen extends ConsumerStatefulWidget {
  const GroupsScreen({super.key});

  @override
  ConsumerState<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends ConsumerState<GroupsScreen> {
  final _searchController = TextEditingController();
  Timer? _searchTimer;
  String _query = '';

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value.trim().toLowerCase());
    });
  }

  void _openGroup(ChannelGroup group) {
    context.go('/channels?group=${Uri.encodeComponent(group.name)}');
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(groupsProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.go('/');
      },
      child: Scaffold(
        body: GradientBackground(
          variant: GradientVariant.list,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.tvEdgeSm,
              AppSpacing.md,
              AppSpacing.tvEdgeSm,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ───────────────────────────────────────────────
                Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: () => context.go('/'),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Browse Groups',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const Spacer(),
                    // Channel/group count badge
                    groupsAsync.whenData(
                      (groups) {
                        final filtered = _filtered(groups);
                        return _CountBadge(
                          label: 'Groups',
                          value: '${filtered.length}',
                        );
                      },
                    ).value ??
                        const SizedBox.shrink(),
                    const SizedBox(width: AppSpacing.sm),
                    // Search field
                    SizedBox(
                      width: 400,
                      child: TextField(
                        controller: _searchController,
                        autofocus: false,
                        onChanged: _onSearchChanged,
                        style: Theme.of(context).textTheme.bodyLarge,
                        decoration: const InputDecoration(
                          hintText: 'Filter groups…',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // ── Group grid ───────────────────────────────────────────
                Expanded(
                  child: groupsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(
                      child: Text('Failed to load groups: $e'),
                    ),
                    data: (groups) {
                      final visible = _filtered(groups);
                      if (visible.isEmpty) {
                        return Center(
                          child: Text(
                            _query.isEmpty
                                ? 'No groups found. Add a playlist in Settings.'
                                : 'No groups matching "$_query".',
                            style: Theme.of(context).textTheme.titleLarge,
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      return GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 280,
                          mainAxisExtent: 130,
                          crossAxisSpacing: AppSpacing.sm,
                          mainAxisSpacing: AppSpacing.sm,
                        ),
                        itemCount: visible.length,
                        itemBuilder: (context, index) => _GroupTile(
                          group: visible[index],
                          onTap: () => _openGroup(visible[index]),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<ChannelGroup> _filtered(List<ChannelGroup> groups) {
    if (_query.isEmpty) return groups;
    return groups
        .where((g) => g.name.toLowerCase().contains(_query))
        .toList();
  }
}

// ── Group tile ────────────────────────────────────────────────────────────────

class _GroupTile extends StatefulWidget {
  const _GroupTile({required this.group, required this.onTap});

  final ChannelGroup group;
  final VoidCallback onTap;

  @override
  State<_GroupTile> createState() => _GroupTileState();
}

class _GroupTileState extends State<_GroupTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final initial = widget.group.name.isNotEmpty
        ? widget.group.name[0].toUpperCase()
        : '#';

    return FocusableActionDetector(
      onShowFocusHighlight: (focused) => setState(() => _focused = focused),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _focused ? 1.04 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              gradient: _focused
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.focusCardStart, AppColors.focusCardEnd],
                    )
                  : null,
              color: _focused
                  ? null
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.05)),
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              border: Border.all(
                color: _focused
                    ? AppColors.darkBorderFocused
                    : (isDark
                        ? AppColors.darkBorder
                        : AppColors.lightBorder),
                width: _focused ? 2 : 1,
              ),
              boxShadow: _focused
                  ? [
                      BoxShadow(
                        color: AppColors.focusCardStart.withValues(alpha: 0.35),
                        blurRadius: 20,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar: first letter of group name
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _focused
                        ? Colors.white.withValues(alpha: 0.25)
                        : AppColors.oceanMid.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initial,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                const Spacer(),
                Text(
                  widget.group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: _focused ? Colors.white : null,
                      ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '${widget.group.count} channels',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: _focused
                            ? Colors.white70
                            : AppColors.darkOnSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Count badge (reused from home) ───────────────────────────────────────────

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 4,
        vertical: AppSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
