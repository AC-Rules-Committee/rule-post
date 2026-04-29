// flutter_app/lib/riverpod/read_receipts.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rule_post/riverpod/user_detail.dart';
import 'package:rule_post/riverpod/unread_post_provider.dart';


// Mark an enquiry as read when you go to its page
final markEnquiryReadProvider =
    Provider<Future<void> Function(String enquiryId)?>((ref) {
  ref.watch(firebaseUserProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  final firestore = FirebaseFirestore.instance;

  return (String enquiryId) async {
    try {
      final unreadData = ref.read(unreadByIdProvider(enquiryId));
      if (unreadData == null) return;
      final bool isUnread = unreadData['isUnread'] == true;
      final bool hasUnreadChild = unreadData['hasUnreadChild'] == true;

      final docRef = firestore
        .collection('user_data')
        .doc(uid)
        .collection('unreadPosts')
        .doc(enquiryId);

      // 1) Only delete if isUnread == true AND (hasUnreadChild == null || false)
      if (isUnread && !hasUnreadChild) {
        await docRef.delete();
        return;
      }

      // 2) If isUnread == true AND hasUnreadChild == true, set isUnread to false
      if (isUnread && hasUnreadChild) {
        // use merge so we don't fail if the doc somehow doesn't exist
        await docRef.set({'isUnread': false}, SetOptions(merge: true));
        return;
      }

      // 3) If only hasUnreadChild (no isUnread), verify descendants actually exist
      if (!isUnread && hasUnreadChild) {
        final col = firestore
          .collection('user_data')
          .doc(uid)
          .collection('unreadPosts');
        final c1 = await col
          .where('isUnread', isEqualTo: true)
          .where('parentId', isEqualTo: enquiryId)
          .count()
          .get();
        final c2 = await col
          .where('isUnread', isEqualTo: true)
          .where('grandparentId', isEqualTo: enquiryId)
          .count()
          .get();
        final unreadDescendants = (c1.count ?? 0) + (c2.count ?? 0);
        if (unreadDescendants == 0) {
          await docRef.delete();
        }
      }
    } catch (e, st) {
      debugPrint('[markEnquiryRead] Failed to mark enquiry as read: $e\n$st');
      // Don't rethrow: we're called in initState() and can't recover anyway
    }
  };
});


// Mark an response as read when you go to its page, along with all current child comments
final markResponsesAndCommentsReadProvider =
    Provider<Future<void> Function(String enquiryId, String responseId)?>((ref) {
  ref.watch(firebaseUserProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;

  final fs = FirebaseFirestore.instance;
  final col = fs.collection('user_data').doc(uid).collection('unreadPosts');

  return (String enquiryId, String responseId) async {
    try {
      // 1) Batch delete: response + all its comment children
      final batch = fs.batch();
      // Always delete the response entry itself (if present)
      batch.delete(col.doc(responseId));
      // Paginate comment children (orderBy required for startAfterDocument)
      Query<Map<String, dynamic>> q = col
        .where('postType', isEqualTo: 'comment')
        .where('parentId', isEqualTo: responseId)
        .limit(200);

      while (true) {
        final snap = await q.get();
        for (final d in snap.docs) {
          batch.delete(d.reference);
        }
        if (snap.docs.length < 450) break;
        q = q.startAfterDocument(snap.docs.last);
      }

      await batch.commit();

      // 2) Parent clean-up
      // If no unread descendants remain under this enquiry AND the enquiry doc
      // only exists as "hasUnreadChild" (i.e. not "isUnread"), delete it.
      final c1 = await col
        .where('isUnread', isEqualTo: true)
        .where('parentId', isEqualTo: enquiryId)
        .count()
        .get();
      final c2 = await col
          .where('isUnread', isEqualTo: true)
          .where('grandparentId', isEqualTo: enquiryId)
          .count()
          .get();
      final unreadDescendants = (c1.count ?? 0) + (c2.count ?? 0);

      if (unreadDescendants == 0) {
        final enquiryDoc = await col.doc(enquiryId).get();
        final e = enquiryDoc.data();
        // Only remove if it's merely a "hasUnreadChild" marker
        if (enquiryDoc.exists && (e?['isUnread'] != true)) {
          await enquiryDoc.reference.delete();
        }
      }
    } catch (e, st) {
      debugPrint('[markResponsesAndCommentsRead] Failed to mark response as read: $e\n$st');
      // Don't rethrow: we're called in initState() and can't recover anyway
    }
  };
});