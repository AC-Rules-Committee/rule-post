// ──────────────────────────────────────────────────────────────────────────────
// Purpose: Publishes comments and updates counts; 00:00 & 12:00 Rome working days
// ──────────────────────────────────────────────────────────────────────────────
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { DateTime } from "luxon";

import { ROME_TZ } from "../common/config";
import { computeStageEnds } from "../utils/compute_stage_ends";
import {
  readAuthorTeam,
  queueDraftDelete,
  stageUpdatePayload,
} from "../utils/publish_helpers";
import { createUnreadForAllUsers } from "../utils/unread_post_generator";
import { isWorkingDay } from "../working_day";

const db3 = getFirestore();

/** Helper function extracted for use by orchestrator */
export async function doCommentPublish(): Promise<void> {
  const nowRome = DateTime.now().setZone(ROME_TZ);
  const publishedAt = FieldValue.serverTimestamp();

  if (!isWorkingDay(nowRome)) {
    logger.info(
      `[doCommentPublish] ${nowRome.toISO()} not a working day; skipping.`,
    );
    return;
  }

  const enquiriesSnap = await db3
    .collection("enquiries")
    .where("isOpen", "==", true)
    .where("isPublished", "==", true)
    .where("teamsCanComment", "==", true)
    .get();

  if (enquiriesSnap.empty) {
    logger.info("[doCommentPublish] No qualifying enquiries.");
    return;
  }

  const writer = db3.bulkWriter();
  let processedEnquiries = 0;
  let totalCommentsPublished = 0;

  for (const enquiryDoc of enquiriesSnap.docs) {
    const enquiryRef = enquiryDoc.ref;
    const roundNumber = enquiryDoc.get("roundNumber") as number | undefined;
    if (typeof roundNumber !== "number") {
      logger.warn(
        `[doCommentPublish] Enquiry ${enquiryRef.id} missing roundNumber; skipping.`,
      );
      processedEnquiries += 1;
      continue;
    }

    let commentsPublishedForEnquiry = 0;

    const responsesSnap = await enquiryRef
      .collection("responses")
      .where("roundNumber", "==", roundNumber)
      .get();

    for (const respDoc of responsesSnap.docs) {
      const commentsCol = respDoc.ref.collection("comments");
      const unpublishedCommentsSnap = await commentsCol
        .where("isPublished", "==", false)
        .get();
      if (unpublishedCommentsSnap.empty) continue;

      const publishedCountSnap = await commentsCol
        .where("isPublished", "==", true)
        .count()
        .get();

      const alreadyPublished = publishedCountSnap.data().count;

      for (const [i, c] of unpublishedCommentsSnap.docs.entries()) {
        // publish comment
        const commentNumber = alreadyPublished + 1 + i;
        writer.update(c.ref, {
          isPublished: true,
          publishedAt,
          commentNumber,
        });
        totalCommentsPublished += 1;
        commentsPublishedForEnquiry += 1;

        // delete draft
        const team = await readAuthorTeam(c.ref);
        if (!team) {
          logger.warn(
            `[doCommentPublish] No team found for ${c.id}, skipping draft delete.`,
          );
        } else {
          queueDraftDelete(writer, team, c.id);
        }

        // add unreadPost entries for users
        await createUnreadForAllUsers(
          writer,
          "comment",
          `Comment #${commentNumber}`,
          c.ref.id,
          true,
          {
            parentId: respDoc.id,
            grandparentId: enquiryDoc.id,
          },
        );
      }
      // update commentCount deterministically after flush
      await writer.flush();
      const published = await commentsCol
        .where("isPublished", "==", true)
        .get();
      writer.update(respDoc.ref, { commentCount: published.size });

      // mark parent response as having unread child data
      await createUnreadForAllUsers(
        writer,
        "response",
        `Response ${respDoc.data()?.roundNumber}.${respDoc.data()?.responseNumber}`,
        respDoc.id,
        false,
        {
          parentId: enquiryDoc.id,
        },
      );
    }

    const stageEnds = enquiryDoc.get("stageEnds") as
      | FirebaseFirestore.Timestamp
      | undefined;
    const nowTs = Timestamp.now();
    if (stageEnds && stageEnds.toMillis() < nowTs.toMillis()) {
      const newStageEndsDate = computeStageEnds(1, { hour: 23, minute: 59 });
      writer.update(enquiryRef, {
        teamsCanRespond: false,
        teamsCanComment: false,
        ...stageUpdatePayload(newStageEndsDate),
      });
    }

    // mark parent enquiry as having unread child data (only if comments were published)
    if (commentsPublishedForEnquiry > 0) {
      await createUnreadForAllUsers(
        writer,
        "enquiry",
        `RE #${enquiryDoc.data().enquiryNumber} - ${enquiryDoc.data().title}`,
        enquiryDoc.id,
        false,
        {},
      );
    }

    processedEnquiries += 1;
  }

  await writer.close();
  logger.info(
    `[doCommentPublish] Processed ${processedEnquiries} enquiries; published ${totalCommentsPublished} comments.`,
  );
}

// ✅ Note: commentPublisher is no longer exported directly.
// It is called by the orchestrator (orchestrate0000, orchestrate1200).
// Legacy export commented out:
/*
export const commentPublisher = onSchedule(
  {
    region: SCHED_REGION_ROME,
    schedule: "0 0,12 * * *", // if changed, requires change to calculateNextCommentPublicationTime
    timeZone: ROME_TZ,
    timeoutSeconds: TIMEOUT_SECONDS,
  },
  async (): Promise<void> => {
    await doCommentPublish();
  },
);
*/
