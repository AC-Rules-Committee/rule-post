// flutter_app/lib/riverpod/admin_providers.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rule_post/api/admin_apis.dart' show getPostAuthorsForEnquiry;
import 'package:rule_post/riverpod/user_detail.dart'
    show roleProvider, teamProvider;

/// Checks if current user is admin or Rules Committee (RC).
/// Used for conditionally rendering admin-only UI and fetching restricted data.
final isAdminOrRCProvider = Provider<bool>((ref) {
  final role = ref.watch(roleProvider);
  final team = ref.watch(teamProvider);
  return role == 'admin' || team == 'RC';
});

/// Fetches and caches author team identities for all posts in an enquiry.
///
/// - Only fetches if user is admin/RC (respects isAdminOrRCProvider)
/// - Returns null for non-admin users
/// - Returns null on any error (silently fails to avoid breaking UI)
/// - Caches per enquiryId (refetch if enquiryId changes)
/// - Map structure: {postId: authorTeam} or {responseId: authorTeam} or {responseId_commentId: authorTeam}
/// - autoDispose ensures stale failures are cleaned up when the page is left
final postAuthorsProvider = FutureProvider.autoDispose
    .family<Map<String, String>?, String>((ref, enquiryId) async {
      final isAdminOrRC = ref.watch(isAdminOrRCProvider);

      // Non-admin users never fetch author data
      if (!isAdminOrRC) {
        return null;
      }

      try {
        return await getPostAuthorsForEnquiry(enquiryId);
      } catch (e) {
        // Log the error for debugging, but don't crash the UI
        // Errors are expected in some cases (permissions, transient failures, etc.)
        debugPrint(
          '[postAuthorsProvider] Error fetching authors for $enquiryId: $e',
        );
        // Return empty map instead of rethrowing; author tags simply won't appear
        return null;
      }
    });
