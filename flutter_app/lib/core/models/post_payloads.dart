// flutter_app/lib/core/models/post_payloads.dart
import 'package:flutter/foundation.dart';

import 'package:rule_post/core/models/attachments.dart';
import 'package:rule_post/core/models/post_types.dart';

// Immutable structure used to pass data to backend functions for creating/editing posts.
@immutable
final class PostPayload {
  final PostType postType;
  final String? title;
  final String? postText;
  final List<TempAttachment> attachments;
  final List<String> parentIds;
  final String? postId;
  final bool? isPublished;
  final EditAttachmentMap editAttachments;
  final bool closeEnquiryOnPublish;
  final String? enquiryConclusion; // "amendment", "interpretation", "noResult"

  const PostPayload._({
    required this.postType,
    required this.title,
    required this.postText,
    required this.attachments,
    required this.parentIds,
    required this.postId,
    required this.isPublished,
    required this.editAttachments,
    required this.closeEnquiryOnPublish,
    required this.enquiryConclusion,
  });

  /// Single entry-point: pick behaviour based on `postType`.
  factory PostPayload({
    required PostType postType,
    String? title,
    String? postText,
    List<TempAttachment>? attachments,
    List<String>? parentIds,
    String? postId,
    bool? isPublished,
    EditAttachmentMap? editAttachments,
    bool closeEnquiryOnPublish = false,
    String? enquiryConclusion,
  }) {
    // String normaliser: trim -> null if empty
    String? norm(String? s) {
      if (s == null) return null;
      final t = s.trim();
      return t.isEmpty ? null : t;
    }

    // List<String> normaliser: null -> [], trim & drop empties, freeze
    List<String> cleanStrings(List<String>? xs) => List<String>.unmodifiable(
      (xs ?? const <String>[]).map((s) => s.trim()).where((s) => s.isNotEmpty),
    );

    // List<TempAttachment> normaliser: null -> [], freeze
    List<TempAttachment> cleanAttachments(List<TempAttachment>? xs) =>
        List<TempAttachment>.unmodifiable(xs ?? const <TempAttachment>[]);

    final normTitle = norm(title);
    final normText = norm(postText);
    final normPostId = norm(postId);
    final safeParents = cleanStrings(parentIds);
    final safeAtts = cleanAttachments(attachments);
    final safeEditAtts = editAttachments ?? EditAttachmentMap();

    final isEdit = normPostId != null;
    final hasText = normText != null && normText.isNotEmpty;

    // ── 1️⃣ Type-specific validation ─────────────────────────────────────────────
    switch (postType) {
      case PostType.enquiry:
        if (!isEdit) {
          if (normTitle == null) {
            throw ArgumentError('Enquiry requires a title.');
          }
          if (!hasText && safeAtts.isEmpty) {
            throw ArgumentError('Enquiry requires text or attachments.');
          }
        } else {
          // edit mode
          if (safeEditAtts.add &&
              safeEditAtts.remove &&
              (normTitle == null && normText == null)) {
            throw ArgumentError(
              'Edit payload must change something (title/text or attachments).',
            );
          }
        }
        if (safeParents.isNotEmpty) {
          throw ArgumentError('Enquiry must not include parentIds.');
        }
        break;

      case PostType.response:
        if (safeParents.length != 1) {
          throw ArgumentError(
            'Response requires exactly one parentId (enquiryId).',
          );
        }
        if (!isEdit && !hasText && safeAtts.isEmpty) {
          throw ArgumentError('Response requires text or attachments.');
        }
        break;

      case PostType.comment:
        if (safeParents.length != 2) {
          throw ArgumentError('Comment requires [enquiryId, responseId].');
        }
        if (!isEdit && !hasText) {
          throw ArgumentError('Comment requires text.');
        }
        break;
    }

    // ── 2️⃣ Return instance ─────────────────────────────────────────────────────
    return PostPayload._(
      postType: postType,
      title: normTitle,
      postText: normText,
      attachments: safeAtts,
      parentIds: safeParents,
      postId: normPostId,
      isPublished: isPublished,
      editAttachments: safeEditAtts,
      closeEnquiryOnPublish: closeEnquiryOnPublish,
      enquiryConclusion: enquiryConclusion,
    );
  }

  Map<String, Object?> toJson() {
    final isEdit = postId != null;

    final json = <String, Object?>{
      'postType': postType.singular,

      if (title != null) 'title': title,
      if (postText != null) 'postText': postText,

      // Only include parentIds when relevant (validated in factory)
      if ((postType == PostType.response || postType == PostType.comment) &&
          parentIds.isNotEmpty)
        'parentIds': parentIds,

      if (isEdit) 'postId': postId,
      if (isPublished != null) 'isPublished': isPublished,

      // Only include closeEnquiryOnPublish for response posts
      if (postType == PostType.response && closeEnquiryOnPublish)
        'closeEnquiryOnPublish': closeEnquiryOnPublish,

      // Only include enquiryConclusion for response posts when closing
      if (postType == PostType.response &&
          closeEnquiryOnPublish &&
          enquiryConclusion != null)
        'enquiryConclusion': enquiryConclusion,
    };

    // Attachments:
    // - Create: include if non-empty
    // - Edit: include only if we're explicitly adding attachments
    if (!isEdit) {
      if (attachments.isNotEmpty) {
        json['attachments'] = attachments
            .map((a) => a.toMap())
            .toList(growable: false);
      }
    } else {
      json['editAttachments'] = editAttachments.toJson();

      if (editAttachments.add && attachments.isNotEmpty) {
        json['attachments'] = attachments
            .map((a) => a.toMap())
            .toList(growable: false);
      }
    }
    return json;
  }
}
