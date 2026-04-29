// ──────────────────────────────────────────────────────────────────────────────
// File: src/utils/unread_post_generator.ts
// Purpose: Create unread post records in user data collection
// ──────────────────────────────────────────────────────────────────────────────
import {
  getFirestore,
  FieldValue,
  FieldPath,
  BulkWriter,
} from "firebase-admin/firestore";
import { logger } from "firebase-functions";

import { PostType } from "../common/types";

const db = getFirestore();

/** Common unread record fields */
type BaseUnread = {
  postType: PostType;
  postAlias: string;
  createdAt: FirebaseFirestore.FieldValue;
  isUnread?: boolean;
};

/** IDs relevant to each post type */
type EnquiryFields = {
  hasUnreadChild?: boolean;
};
type ResponseFields = {
  hasUnreadChild?: boolean;
  parentId: string;
};
type CommentFields = {
  parentId: string;
  grandparentId: string;
};

type FieldBundle<T extends PostType> = T extends "enquiry"
  ? EnquiryFields
  : T extends "response"
    ? ResponseFields
    : T extends "comment"
      ? CommentFields
      : never;

/** Per-type payloads */
type UnreadEnquiry = BaseUnread & EnquiryFields;
type UnreadResponse = BaseUnread & ResponseFields;
type UnreadComment = BaseUnread & CommentFields;

type UnreadRecord = UnreadEnquiry | UnreadResponse | UnreadComment;

/** Build the record payload, branching on postType. */
function buildUnreadRecord<T extends PostType>(
  postType: T,
  postAlias: string,
  isUnread: boolean,
  postFields: FieldBundle<T>,
): UnreadRecord {
  const base: BaseUnread = {
    postType,
    postAlias,
    createdAt: FieldValue.serverTimestamp(),
  };
  const unreadPayload: Record<string, boolean> = isUnread
    ? {
        isUnread: true,
      }
    : {
        hasUnreadChild: true,
      };

  return { ...base, ...unreadPayload, ...postFields };
}

/**
 * Create unread records under every user:
 *   user_data/{uid}/unreadPosts/{docId}
 *
 * @param writer
 * @param postType     "enquiry" | "response" | "comment"
 * @param postAlias
 * @param docId        the post Id
 * @param isUnread     boolean whether the post itself is unread, or it's being marked due to a child post
 * @param postFields   extra fields which vary by post type
 * @param userTeam
 * @returns number of user docs written
 */
export async function createUnreadForAllUsers<T extends PostType>(
  writer: BulkWriter,
  postType: T,
  postAlias: string,
  docId: string,
  isUnread: boolean,
  postFields: FieldBundle<T>,
  filters?: { userTeam?: string; userId?: string },
): Promise<{ attempted: number; updated: number }> {
  let attempted = 0;
  let updated = 0;

  // Count successful writes (BulkWriter calls this per success)
  writer.onWriteResult((_ref, _res) => {
    updated++;
  });

  // Optional: log & suppress individual write errors but keep bulk going
  writer.onWriteError((err) => {
    // Firestore BulkWriter will auto-retry based on backoff; return true to retry if allowed
    // You can add custom logic here. For now, don't retry beyond internal behavior.
    logger.error(`[createUnreadForAllUsers] write error: ${err.message}`);
    return false;
  });

  const payload = buildUnreadRecord(postType, postAlias, isUnread, postFields);
  logger.info("[createUnreadForAllUsers] Unread payload:", { payload });

  // Collect target user docs (normalize to an array so the loop works the same)
  let userDocs: FirebaseFirestore.QueryDocumentSnapshot[] = [];

  const trimmedUserId = filters?.userId?.trim();
  const trimmedTeam = filters?.userTeam?.trim();

  if (trimmedUserId) {
    // Fast path: userId is the document ID
    const docSnap = await db.collection("user_data").doc(trimmedUserId).get();
    if (docSnap.exists) {
      userDocs = [docSnap as FirebaseFirestore.QueryDocumentSnapshot];
    } else {
      logger.warn(
        `[createUnreadForAllUsers] userId not found: ${trimmedUserId}`,
      );
    }
  } else {
    // If neither filter is provided, this targets ALL users.
    if (!trimmedTeam) {
      logger.warn(
        "[createUnreadForAllUsers] No userId or userTeam specified — all-user write.",
      );
      // return { attempted, updated };
    }

    let q: FirebaseFirestore.Query = db.collection("user_data");
    if (trimmedTeam) q = q.where("team", "==", trimmedTeam);

    // We only need the ref/id, so project only the doc ID to save RU/s
    const snap = await q.select(FieldPath.documentId()).get();
    userDocs = snap.docs;
  }

  logger.info(`[createUnreadForAllUsers] userCount=${userDocs.length}`);

  // Enqueue writes; optional periodic flush to apply backpressure for very large sets
  // const FLUSH_EVERY = 500; // tune as needed; set to 0 to disable mid-stream flushes
  for (const userDoc of userDocs) {
    const ref = userDoc.ref.collection("unreadPosts").doc(docId);
    attempted++;
    writer.set(ref, payload, { merge: true });

    // if (FLUSH_EVERY && attempted % FLUSH_EVERY === 0) {
    //   await writer.flush();
    // }
  }

  // Final flush to ensure everything is sent
  await writer.flush();

  logger.info("[createUnreadForAllUsers] Users all finished.");
  return { attempted, updated };
}

/**
 * Delete an unread record instance from under every user:
 *   user_data/{uid}/unreadPosts/{docId}
 *
 * @param docId        the post Id
 * @returns
 */
export async function deleteUnreadForAllUsers(
  docId: string,
  postType: PostType,
): Promise<void> {
  const q: FirebaseFirestore.Query = db.collection("user_data");

  const usersSnap = await q.select().get();
  logger.info(`[deleteUnreadForAllUsers] userCount=${usersSnap.size}`);

  // Loop through users and delete the unreadPost doc
  for (const userDoc of usersSnap.docs) {
    const ref = userDoc.ref.collection("unreadPosts").doc(docId);
    const docSnap = await ref.get();
    if (!docSnap.exists) continue;
    const parentId = docSnap.get("parentId");

    // Delete the child doc first so sibling counts are accurate
    await ref.delete();

    if (postType == "comment") {
      // check if parentDoc is unread
      const responseRef = userDoc.ref.collection("unreadPosts").doc(parentId);
      const responseSnap = await responseRef.get();
      const responseIsUnread = responseSnap.get("isUnread") === true;

      // check if there are remaining comment siblings under the parent response
      const siblingCount = await userDoc.ref
        .collection("unreadPosts")
        .where("postType", "==", "comment")
        .where("parentId", "==", parentId)
        .get()
        .then((snap) => snap.size);

      // check if grandparentDoc is unread
      const grandparentId = responseSnap.get("parentId");
      const enquiryRef = userDoc.ref
        .collection("unreadPosts")
        .doc(grandparentId);
      const enquirySnap = await enquiryRef.get();
      const enquiryIsUnread = enquirySnap.get("isUnread") === true;

      // If no remaining siblings, and the response wasn't unread itself, delete the parent
      if (siblingCount == 0 && parentId && !responseIsUnread) {
        await responseRef.delete();
        // Re-check piblings after deleting the response for an accurate count
        const piblingCount = await userDoc.ref
          .collection("unreadPosts")
          .where("postType", "==", "response")
          .where("parentId", "==", grandparentId)
          .get()
          .then((snap) => snap.size);
        // If no remaining piblings, and the enquiry wasn't unread itself, delete the grandparent
        if (piblingCount == 0 && grandparentId && !enquiryIsUnread) {
          await enquiryRef.delete();
        }
      }
    }
    if (postType == "response") {
      // check if parentDoc is unread
      const enquiryRef = userDoc.ref.collection("unreadPosts").doc(parentId);
      const enquirySnap = await enquiryRef.get();
      const enquiryIsUnread = enquirySnap.get("isUnread") === true;

      // check if there are remaining response siblings under the parent enquiry
      const siblingCount = await userDoc.ref
        .collection("unreadPosts")
        .where("postType", "==", "response")
        .where("parentId", "==", parentId)
        .get()
        .then((snap) => snap.size);

      // If no remaining siblings, and the enquiry wasn't unread itself, delete the parent
      if (siblingCount == 0 && parentId && !enquiryIsUnread) {
        await enquiryRef.delete();
      }
    }
  }
  return;
}
