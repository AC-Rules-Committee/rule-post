// flutter_app/lib/core/widgets/left_pane_nested.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rule_post/core/buttons/new_post_button.dart' show NewPostButton;
import 'package:rule_post/core/models/post_types.dart';
import 'package:rule_post/core/models/types.dart' show DocView;
import 'package:rule_post/core/widgets/filter_dropdown.dart';
import 'package:rule_post/core/widgets/two_panel_shell.dart';
import 'package:rule_post/core/widgets/unread_dot.dart';
import 'package:rule_post/debug/debug.dart';
import 'package:rule_post/debug/build_logger.dart';
import 'package:rule_post/navigation/nav.dart';
import 'package:rule_post/riverpod/enquiry_filter_provider.dart';
import 'package:rule_post/riverpod/post_providers.dart';
import 'package:rule_post/riverpod/user_detail.dart';

final filterDefault = 'open';

/// ─────────────────────────────────────────────────────────────────────────
/// Left header: title + "New" and "Filter" buttons
/// ─────────────────────────────────────────────────────────────────────────
class LeftPaneHeader extends ConsumerWidget {
  const LeftPaneHeader({super.key, this.title = 'Rule Enquiries'});
  final String title;

  static const double _kControlHeight = 40.0; // keep in sync with controls
  static const double _kHorzPad = 12.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoggedIn = ref.watch(isLoggedInProvider);

    return SizedBox(
      height: _kControlHeight,
      child: Row(
        children: [
          // Title (fills available space, vertically centered)
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                ),
              ),
            ),
          ),

          // Controls block (fixed height, vertically centered)
          SizedBox(
            height: _kControlHeight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoggedIn) ...[
                  NewPostButton(type: PostType.enquiry),
                  const SizedBox(width: 12),
                ],
                const FilterDropdown(
                  height: _kControlHeight,
                  radius: 8,
                  horizontalPad: _kHorzPad,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────
/// LeftPaneNested: Shows enquiries and responses, used for navigation
/// ─────────────────────────────────────────────────────────────────────────
class LeftPaneNested extends ConsumerStatefulWidget {
  const LeftPaneNested({super.key, required this.state});
  final GoRouterState state;

  @override
  ConsumerState<LeftPaneNested> createState() => _LeftPaneNestedState();
}

class _LeftPaneNestedState extends ConsumerState<LeftPaneNested>
    with StateLogger<LeftPaneNested> {
  String? get _enquiryId => widget.state.pathParameters['enquiryId'];
  String? get _responseId => widget.state.pathParameters['responseId'];

  @override
  Widget build(BuildContext context) {
    logBuild();
    return _EnquiriesTree(
      initiallyOpenEnquiryId: _enquiryId,
      initiallyOpenResponseId: _responseId,
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────
/// Enquiries list (within the LeftPaneNested) with expandable responses
/// ─────────────────────────────────────────────────────────────────────────

class _EnquiriesTree extends ConsumerWidget with BuildLogger {
  const _EnquiriesTree({
    required this.initiallyOpenEnquiryId,
    required this.initiallyOpenResponseId,
  });

  final String? initiallyOpenEnquiryId;
  final String? initiallyOpenResponseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    logBuild();
    final filter = ref.watch(enquiryFilterProvider);
    final itemsAsync = ref.watch(
      combinedEnquiriesProvider((statusFilter: filter.status)),
    );

    // If this is the very first load (no stale data yet), show your full-page loader:
    if (itemsAsync.valueOrNull == null) {
      return const Center(
        child: Column(
          children: [
            SizedBox(height: 12),
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Loading enquiries from database...'),
            SizedBox(height: 8),
            Text('(This may take a few seconds to populate)'),
          ],
        ),
      );
    }

    // From here on, we have stale data available (even if we're reloading)
    final isReloading = itemsAsync.isLoading; // true during background refresh
    final docs0 = itemsAsync.valueOrNull!;
    // final uid = FirebaseAuth.instance.currentUser?.uid;

    final rawQ = filter.query.trim().toLowerCase();
    List<DocView> docs = docs0;
    if (rawQ.isNotEmpty) {
      docs = docs.where((d) {
        final data = d.data();
        final title = (data['title'] ?? '').toString().toLowerCase();
        final numStr = (data['enquiryNumber'] ?? '').toString().toLowerCase();
        return title.contains(rawQ) || numStr.contains(rawQ);
      }).toList();
    }

    return Stack(
      children: [
        // Your existing list UI (stale-but-usable)
        ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i];
            final id = d.id;
            final data = d.data();
            final title = (data['title'] ?? 'Untitled').toString();
            final n = (data['enquiryNumber'] ?? 'Unnumbered').toString();
            final isOpen = id == initiallyOpenEnquiryId;
            final isPublished = data['isPublished'] ?? false;
            final isClosed = data['isOpen'] == false;

            return ExpansionTile(
              key: ValueKey('enq_${id}_$isOpen'),
              initiallyExpanded: isOpen,
              maintainState: false,
              backgroundColor: isOpen
                  ? Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: 0.2)
                  : null,
              onExpansionChanged: (expanded) {
                if (expanded && id != initiallyOpenEnquiryId) {
                  TwoPaneScope.of(context)?.closeDrawer();
                  Nav.goEnquiry(context, id);
                }
              },
              title: _RowTile(
                label: 'RE${n.toString().padLeft(3, '0')} - $title',
                isUnread: UnreadDot(id, expanded: (isOpen && isPublished)),
                selected: isOpen && initiallyOpenResponseId == null,
                showSubtitle: isPublished == false,
                leading: isClosed
                    ? const Icon(Icons.lock, size: 14, color: Colors.grey)
                    : null,
                onTap: () {
                  TwoPaneScope.of(context)?.closeDrawer();
                  Nav.goEnquiry(context, id);
                },
              ),
              children: [
                if (isOpen && isPublished)
                  _ResponsesBranch(
                    enquiryId: id,
                    initiallyOpenResponseId: initiallyOpenResponseId,
                  ),
              ],
            );
          },
        ),

        // Subtle top loading bar while fresh data is fetched
        if (isReloading)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: const LinearProgressIndicator(),
          ),
      ],
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────
/// Responses which expand under an enquiry (within LeftPaneNested)
/// ─────────────────────────────────────────────────────────────────────────
class _ResponsesBranch extends StatelessWidget with BuildLogger {
  const _ResponsesBranch({
    required this.enquiryId,
    required this.initiallyOpenResponseId,
  });

  final String enquiryId;
  final String? initiallyOpenResponseId;

  @override
  Widget build(BuildContext context) {
    logBuild();
    final q = FirebaseFirestore.instance
        .collection('enquiries')
        .doc(enquiryId)
        .collection('responses')
        .where('isPublished', isEqualTo: true)
        .orderBy('roundNumber')
        .orderBy('responseNumber');

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          final error = snap.error.toString();
          d('❌ Firestore query error: $error');
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Failed to load responses'),
          );
        }
        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: CircularProgressIndicator(),
          );
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return leafInfo('No responses yet', context);
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0), // add space at the end
          child: Column(
            children: docs.map((d) {
              final id = d.id;
              final data = d.data();
              final label =
                  'Response ${data['roundNumber'] ?? 'x'}.${data['responseNumber'] ?? 'x'}';
              final isOpen = id == initiallyOpenResponseId;
              final isPublished = data['isPublished'] ?? false;

              return Padding(
                padding: const EdgeInsets.only(left: 12.0),
                child: ListTile(
                  key: PageStorageKey('resp_${enquiryId}_$id'),
                  dense: true,
                  visualDensity: const VisualDensity(vertical: -3),
                  minVerticalPadding: 0,
                  title: _RowTile(
                    label: label,
                    selected: isOpen,
                    isUnread: UnreadDot(id, expanded: (isOpen && isPublished)),
                    onTap: () {
                      TwoPaneScope.of(context)?.closeDrawer();
                      Nav.goResponse(context, enquiryId, id);
                    },
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

/// ─────────────────────────────────────────────────────────────────────────
/// Row tile shared style
/// ─────────────────────────────────────────────────────────────────────────
class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.label,
    this.selected = false,
    this.showSubtitle = false,
    this.isUnread = const SizedBox.shrink(),
    this.leading,
    this.onTap,
  });
  final String label;
  final bool selected;
  final bool showSubtitle;
  final Widget isUnread;
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      visualDensity: const VisualDensity(vertical: -3), // tighter
      minVerticalPadding: 0,
      contentPadding: EdgeInsets.zero,
      title: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 4)],
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            isUnread,
          ],
        ),
      ),
      subtitle: showSubtitle
          ? const Text(
              '(Unpublished)',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            )
          : null,
      onTap: onTap,
      selected: selected,
    );
  }
}

// used when there are no responses under an enquiry, and that enquiry is expanded
Widget leafInfo(String text, BuildContext context) => Padding(
  padding: const EdgeInsets.only(
    // left: 24,
    bottom: 8,
  ),
  child: Text(
    text,
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Theme.of(
        context,
      ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
    ),
  ),
);
