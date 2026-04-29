// ──────────────────────────────────────────────────────────────────────────────
// File: src/utils/publish_responses.ts
// Purpose: Response publishing helper for scheduled and triggered functions
// ──────────────────────────────────────────────────────────────────────────────
import { FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions";

import { PublishResult } from "../common/types";
import { computeStageEnds } from "../utils/compute_stage_ends";
import {
  tokeniseAttachmentsIfAny,
  readAuthorTeam,
  queueDraftDelete,
  stageUpdatePayload,
} from "../utils/publish_helpers";
import { createUnreadForAllUsers } from "../utils/unread_post_generator";

export async function publishResponses(
  writer: FirebaseFirestore.BulkWriter,
  debugPrefix: string,
  enquiryDoc: FirebaseFirestore.DocumentSnapshot<
    FirebaseFirestore.DocumentData,
    FirebaseFirestore.DocumentData
  >,
  isRcResponse: boolean,
): Promise<PublishResult> {
  // declare variables
  let totalResponsesPublished = 0;
  let shouldCloseEnquiry = false;
  let enquiryConclusion: string | undefined;
  const publishedAt = FieldValue.serverTimestamp();
  const enquiryData = enquiryDoc.data();
  const enquiryRef = enquiryDoc.ref;
  const roundNumber = (enquiryData?.roundNumber ?? 99) + (isRcResponse ? 1 : 0);

  // 1) Get responses
  const unpublishedSnap = await enquiryRef
    .collection("responses")
    .where("isPublished", "==", false)
    .where("fromRC", "==", isRcResponse)
    .where("roundNumber", "==", roundNumber)
    .get();
  // Copy docs into a mutable array
  const shuffled = [...unpublishedSnap.docs];
  // Guards
  if (shuffled.length == 0 && isRcResponse) {
    return { success: false, publishedNumber: 0, failReason: "no-response" };
  } else if (isRcResponse && shuffled.length > 1) {
    return {
      success: false,
      publishedNumber: 0,
      failReason: "multiple-rc-responses",
    };
  }
  // Shuffle only if there’s more than one document
  if (shuffled.length > 1) {
    for (let i = shuffled.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
    }
  }
  // 2) Edit response documents to publish them
  let responseNumber = 0;
  for (let i = 0; i < shuffled.length; i++) {
    // 2a) publish response document
    responseNumber = isRcResponse ? 0 : i + 1;
    writer.update(shuffled[i].ref, {
      isPublished: true,
      responseNumber,
      publishedAt,
    });
    // 2b) make attachments readble to all
    await tokeniseAttachmentsIfAny(
      writer,
      shuffled[i].ref,
      shuffled[i].get("attachments"),
    );

    // 2c) Check if this response should close the enquiry
    if (isRcResponse && shuffled[i].get("closeEnquiryOnPublish") === true) {
      shouldCloseEnquiry = true;
      enquiryConclusion = shuffled[i].get("enquiryConclusion");
      logger.info(
        `[${debugPrefix}] RC response ${shuffled[i].id} has closeEnquiryOnPublish flag with conclusion "${enquiryConclusion}", enquiry will be closed.`,
      );
    }

    // 2d) delete draft document
    const team = await readAuthorTeam(shuffled[i].ref);
    if (!team) {
      logger.warn(
        `[${debugPrefix}] No team found for ${shuffled[i].id}, skipping draft delete.`,
      );
    } else {
      queueDraftDelete(writer, team, shuffled[i].id);
    }

    // 2e) generate unreadPost record for all users
    await createUnreadForAllUsers(
      writer,
      "response",
      `Response ${roundNumber}.${responseNumber}`,
      shuffled[i].ref.id,
      true,
      {
        parentId: enquiryDoc.ref.id,
      },
    );

    totalResponsesPublished += 1;
  }

  // 3) advance stage for enquiry (or close it)
  const stageLength = enquiryData?.stageLength ?? 4;
  const newStageEnds = isRcResponse
    ? computeStageEnds(stageLength, { hour: 19, minute: 59 })
    : computeStageEnds(stageLength + 1, { hour: 11, minute: 59 });

  if (shouldCloseEnquiry && isRcResponse) {
    // Close the enquiry when RC response is published with closeEnquiryOnPublish flag
    writer.update(enquiryRef, {
      isOpen: false,
      teamsCanRespond: false,
      teamsCanComment: false,
      ...(enquiryConclusion && { enquiryConclusion }),
      ...stageUpdatePayload(newStageEnds),
    });
  } else {
    // Normal stage advancement
    writer.update(enquiryRef, {
      teamsCanRespond: isRcResponse,
      teamsCanComment: !isRcResponse,
      ...(isRcResponse && { roundNumber: FieldValue.increment(1) }),
      ...stageUpdatePayload(newStageEnds),
    });
  }

  // 4) mark parent enquiry as having unread child data (only if responses were published)
  if (totalResponsesPublished > 0) {
    await createUnreadForAllUsers(
      writer,
      "enquiry",
      `RE #${enquiryDoc.data()?.enquiryNumber} - ${enquiryDoc.data()?.title}`,
      enquiryDoc.ref.id,
      false,
      {},
    );
  }

  return { success: true, publishedNumber: totalResponsesPublished };
}
