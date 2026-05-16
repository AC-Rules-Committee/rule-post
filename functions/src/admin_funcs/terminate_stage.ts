// ──────────────────────────────────────────────────────────────────────────────
// File: src/admin_funcs/terminate_stage.ts
// Purpose: Immediately terminate the competitor response stage for an enquiry
// ──────────────────────────────────────────────────────────────────────────────
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onCall, HttpsError } from "firebase-functions/v2/https";

import { REGION, MEMORY, TIMEOUT_SECONDS } from "../common/config";
import { terminateStagePayload } from "../common/types";
import { computeStageEnds } from "../utils/compute_stage_ends";
import { stageUpdatePayload } from "../utils/publish_helpers";
import { publishResponses } from "../utils/publish_responses";

const db = getFirestore();

export const terminateStage = onCall(
  {
    region: REGION,
    cors: true,
    memory: MEMORY,
    timeoutSeconds: TIMEOUT_SECONDS,
    enforceAppCheck: true,
  },
  async (req) => {
    // 1) Auth
    if (!req.auth?.uid)
      throw new HttpsError("unauthenticated", "Sign in required.");
    const isAdmin = req.auth?.token.role === "admin";
    const isRC = req.auth?.token.team === "RC";
    if (!isAdmin && !isRC) {
      throw new HttpsError("permission-denied", "Admin/RC function only.");
    }

    // 2) Fetch enquiry
    const { enquiryId, publishPendingResponses } =
      req.data as terminateStagePayload;
    const enquiryDoc = await db.collection("enquiries").doc(enquiryId).get();
    if (!enquiryDoc.exists) {
      throw new HttpsError("not-found", `Enquiry ${enquiryId} does not exist.`);
    }

    // 3) Validate stage: must be in the competitor response stage
    const data = enquiryDoc.data();
    if (!data?.isOpen) {
      throw new HttpsError("failed-precondition", "Enquiry is not open.");
    }
    if (!data?.teamsCanRespond) {
      throw new HttpsError(
        "failed-precondition",
        "Enquiry is not in the competitor response stage.",
      );
    }

    // 4) Terminate the competitor response stage
    if (publishPendingResponses) {
      // Publish pending responses and advance stage
      const writer = db.bulkWriter();
      const publishResult = await publishResponses(
        writer,
        "terminateStage",
        enquiryDoc,
        false, // competitor responses, not RC
      );
      await writer.close();

      if (publishResult.success === false) {
        logger.info(
          `[terminateStage] Enquiry ${enquiryDoc.id} failed with reason: ${publishResult.failReason}.`,
        );
      } else {
        logger.info(
          `[terminateStage] Terminated stage for ${enquiryDoc.id}. Published ${publishResult.publishedNumber} responses.`,
        );
      }

      return {
        ok: publishResult.success,
        num_published: publishResult.publishedNumber,
        reason: publishResult.failReason,
      };
    } else {
      // Advance stage without publishing pending responses
      const stageLength = data?.stageLength ?? 4;
      const newStageEnds = computeStageEnds(stageLength + 1, {
        hour: 11,
        minute: 59,
      });

      await enquiryDoc.ref.update({
        teamsCanRespond: false,
        teamsCanComment: true,
        ...stageUpdatePayload(newStageEnds),
      });

      logger.info(
        `[terminateStage] Terminated stage for ${enquiryDoc.id} without publishing responses.`,
      );

      return { ok: true, num_published: 0 };
    }
  },
);
