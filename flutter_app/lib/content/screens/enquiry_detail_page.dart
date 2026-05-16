// flutter_app/lib/content/screens/enquiry_detail_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rule_post/content/widgets/author_tag.dart'
    show formatAuthorSuffix;
import 'package:rule_post/content/widgets/children_section.dart';
import 'package:rule_post/content/widgets/detail_scaffold.dart';
import 'package:rule_post/content/widgets/status_chip.dart';
import 'package:rule_post/core/buttons/edit_post_button.dart';
import 'package:rule_post/core/buttons/delete_post_button.dart';
import 'package:rule_post/content/widgets/fancy_attachment_tile.dart';
import 'package:rule_post/core/widgets/rules_committee_panel.dart';
import 'package:rule_post/core/models/post_types.dart';
import 'package:rule_post/core/widgets/get_stage_length.dart';
import 'package:rule_post/core/widgets/markdown_display.dart';
import 'package:rule_post/debug/debug.dart' as debug;
import 'package:rule_post/riverpod/admin_providers.dart';
import 'package:rule_post/riverpod/doc_providers.dart';
import 'package:rule_post/riverpod/read_receipts.dart';
import 'package:rule_post/riverpod/user_detail.dart';

/// -------------------- ENQUIRY DETAIL --------------------
class EnquiryDetailPage extends ConsumerStatefulWidget {
  const EnquiryDetailPage({super.key, required this.enquiryId});
  final String enquiryId;

  @override
  ConsumerState<EnquiryDetailPage> createState() => _EnquiryDetailPageState();
}

class _EnquiryDetailPageState extends ConsumerState<EnquiryDetailPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final markEnquiryRead = ref.read(markEnquiryReadProvider);
      markEnquiryRead?.call(widget.enquiryId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final docAsync = ref.watch(enquiryDocProvider(widget.enquiryId));
    final userRole = ref.watch(roleProvider);
    final userTeam = ref.watch(teamProvider);
    final authorsAsync = ref.watch(postAuthorsProvider(widget.enquiryId));

    return docAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, i_) => const Center(child: Text('Failed to load enquiry')),
      data: (data) {
        final d = data ?? const {};
        // Validate schema: warn if expected keys are missing
        debug.validateDocSchema(
          data,
          ['enquiryNumber', 'title', 'postText', 'isOpen', 'isPublished'],
          docType: 'Enquiry',
          docId: widget.enquiryId,
        );
        final title = (d['title'] ?? 'Untitled').toString();
        final enquiryNumber = (d['enquiryNumber'] ?? '—').toString();
        final postText = (d['postText'] ?? '').toString().trim();
        final attachments =
            (d['attachments'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
        final isOpen = d['isOpen'] ?? false;
        final isPublished = d['isPublished'] ?? false;
        final teamsCanRespond = d['teamsCanRespond'] ?? false;
        final teamsCanComment = d['teamsCanComment'] ?? false;
        final stageStarts = (d['stageStarts'] as Timestamp?)?.toDate();
        final stageEnds = (d['stageEnds'] as Timestamp?)?.toDate();
        final fromRC = d['fromRC'] ?? false;
        final publishedAt = _fmtTimestamp(d['publishedAt']);

        final isAdmin = userRole == 'admin';
        final isRC = userTeam == 'RC';
        final lockedResponses =
            !isPublished ||
            (isRC && teamsCanRespond) ||
            (!isRC && (!isOpen || !teamsCanRespond));
        final lockedResponseReason = !lockedResponses
            ? ''
            : !isPublished
            ? "Can't respond to unpublished enquiry"
            : isRC
            ? 'Competitor response window currently open'
            : !d['isOpen']
            ? 'Enquiry closed'
            : 'Responses currently closed';

        debug.d("attachments: $attachments");

        // Extract enquiry author from cache (safely handle all async states)
        final enquiryAuthorTeam = authorsAsync.maybeWhen(
          data: (authors) => authors?[widget.enquiryId],
          orElse: () => null,
        );

        return DetailScaffold(
          headerLines: ['$title${formatAuthorSuffix(enquiryAuthorTeam)}'],
          subHeaderLines: [
            'Rule Enquiry ${enquiryNumber.toString().padLeft(3, '0')}',
          ],
          publishedAt: publishedAt,
          headerButton: isPublished
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    EditPostButton(
                      type: PostType.enquiry,
                      initialTitle: title,
                      initialText: postText,
                      initialAttachments: attachments,
                      postId: widget.enquiryId,
                      isPublished: isPublished,
                    ),
                    const SizedBox(width: 8),
                    DeletePostButton(
                      type: PostType.enquiry,
                      postId: widget.enquiryId,
                    ),
                  ],
                ),
          meta: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (d.containsKey('isOpen') &&
                  !isOpen &&
                  d.containsKey('enquiryConclusion'))
                StatusChip(
                  enquiryConclusionLabels[d['enquiryConclusion']] ?? 'Closed',
                  color: Colors.red,
                ),
              if (d.containsKey('isPublished') && !isPublished)
                StatusChip('Unpublished', color: Colors.orange),
              if (d.containsKey('fromRC') && fromRC)
                StatusChip('Rules Committee Enquiry', color: Colors.blue),
            ],
          ),
          stageMap: {
            'teamsCanRespond': teamsCanRespond,
            'teamsCanComment': teamsCanComment,
            'isOpen': isOpen,
            'isPublished': isPublished,
            'stageStarts': stageStarts,
            'stageEnds': stageEnds,
          },
          commentary: postText.isEmpty ? null : MarkdownDisplay(postText),
          commentaryText: postText,
          attachments: attachments
              .map(
                (m) => FancyAttachmentTile.fromMap(
                  m,
                  previewHeight: MediaQuery.of(context).size.height * 0.6,
                ),
              )
              .toList(),
          footer: ChildrenSection.responses(
            enquiryId: widget.enquiryId,
            lockedResponses: lockedResponses,
            lockedReason: lockedResponseReason,
            authors: authorsAsync.maybeWhen(data: (a) => a, orElse: () => null),
          ),
          adminPanel: (isRC || isAdmin)
              ? AdminCard(
                  titleColour: Colors.red,
                  boldTitle: true,
                  actions: [
                    // AdminAction.testSendDigest(
                    //   context: context,
                    //   userEmail: FirebaseAuth.instance.currentUser?.email,
                    // ),
                    AdminAction.changeStageLength(
                      enquiryId: widget.enquiryId,
                      loadCurrent: () => getStageLength(widget.enquiryId),
                      enabled: isOpen,
                      canTerminate: teamsCanRespond && isOpen && isPublished,
                      context: context,
                    ),
                    AdminAction.publishCompetitorResponses(
                      enquiryId: widget.enquiryId,
                      enabled: teamsCanRespond && isOpen && isPublished,
                      context: context,
                    ),
                    AdminAction.publishRCResponse(
                      enquiryId: widget.enquiryId,
                      enabled: !teamsCanRespond && isOpen && isPublished,
                      context: context,
                    ),
                    AdminAction.closeEnquiry(
                      enquiryId: widget.enquiryId,
                      enabled: isOpen && isPublished,
                      context: context,
                    ),
                  ],
                )
              : null,
        );
      },
    );
  }
}

final enquiryConclusionLabels = {
  'amendment': 'Amendment closed',
  'interpretation': 'Interpretation closed',
  'noResult': 'Enquiry closed with no result',
};

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _fmtTimestamp(dynamic v) {
  if (v == null) return '';
  DateTime dt;
  if (v is Timestamp) {
    dt = v.toDate().toLocal();
  } else if (v is DateTime) {
    dt = v.toLocal();
  } else {
    return '';
  }
  return '${dt.day.toString().padLeft(2, '0')} ${_months[dt.month - 1]} ${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}
