// ──────────────────────────────────────────────────────────────────────────────
// File: src/admin_funcs/change_stage_length.ts
// Purpose: Change how long each submission stage stays open for (in days)
// ──────────────────────────────────────────────────────────────────────────────
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { DateTime } from "luxon";
import { createTransport } from "nodemailer";

import { REGION, MEMORY, TIMEOUT_SECONDS, ROME_TZ } from "../common/config";
import { changeStageLengthPayload, UserData } from "../common/types";
import { sendBccInChunks } from "../utils/email_batch";
import { offsetByWorkingDays } from "../utils/offset_by_working_days";

const db = getFirestore();

export const changeStageLength = onCall(
  {
    region: REGION,
    cors: true,
    memory: MEMORY,
    timeoutSeconds: TIMEOUT_SECONDS,
    enforceAppCheck: true,
    secrets: ["GMAIL_USER", "GMAIL_APP_PASSWORD"],
  },
  async (req) => {
    // 1) AuthZ
    const callerUid = req.auth?.uid;
    if (!callerUid) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }
    const isAdmin = req.auth?.token.role === "admin";
    const isRC = req.auth?.token.team === "RC";
    if (!isAdmin && !isRC) {
      throw new HttpsError("permission-denied", "Admin/RC function only.");
    }

    // 2) Input validation
    const { enquiryId, newStageLength } = req.data as changeStageLengthPayload;
    const ref = db.collection("enquiries").doc(enquiryId);
    // (Optional) ensure it exists first, for clearer errors:
    const snap = await ref.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", `Enquiry ${enquiryId} does not exist.`);
    }
    const oldStageLength = snap.get("stageLength");
    if (oldStageLength == newStageLength) {
      throw new HttpsError(
        "already-exists",
        `Enquiry already has stage length ${newStageLength}.`,
      );
    }

    // 3) Calculate new stage end
    const oldStageEnds = snap.get("stageEnds");
    const stageLengthDiff = newStageLength - oldStageLength;
    const stageEnds = offsetByWorkingDays(oldStageEnds, stageLengthDiff);

    // 4) Update
    await ref.update({
      stageLength: newStageLength,
      stageEnds: stageEnds,
    });

    // 5) Notify all users that the stage length changed.
    //    Email failures must not fail the stage-length change itself.
    try {
      await notifyStageLengthChanged({
        enquiryNumber: snap.get("enquiryNumber") as number | undefined,
        enquiryTitle: snap.get("title") as string | undefined,
        oldStageLength: oldStageLength as number,
        newStageLength,
        newStageEnds: stageEnds,
      });
    } catch (emailErr) {
      logger.error(
        "[changeStageLength] Stage length updated but notification email failed.",
        { enquiryId, error: emailErr },
      );
    }

    return { ok: true };
  },
);

/** Send a broadcast email to all opted-in users about a stage-length change. */
async function notifyStageLengthChanged(params: {
  enquiryNumber: number | undefined;
  enquiryTitle: string | undefined;
  oldStageLength: number;
  newStageLength: number;
  newStageEnds: Date;
}): Promise<void> {
  const { enquiryNumber, enquiryTitle, oldStageLength, newStageLength } =
    params;

  // Escape user-supplied text before embedding in HTML email.
  const esc = (s: string | undefined) =>
    (s ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");

  // Gather recipients (all users with email notifications enabled).
  const snap = await db
    .collection("user_data")
    .where("emailNotificationsOn", "==", true)
    .get();

  const recipients = snap.docs
    .map((d) => (d.data() as UserData).email)
    .filter((email): email is string => Boolean(email));

  if (recipients.length === 0) {
    logger.info("[changeStageLength] No recipients; skipping notification.");
    return;
  }

  const enquiryLabel =
    enquiryNumber != null
      ? `Rule Enquiry ${enquiryNumber.toString().padStart(3, "0")}`
      : "an enquiry";
  const titleSuffix = enquiryTitle ? ` — ${esc(enquiryTitle)}` : "";
  const newDeadline = DateTime.fromJSDate(params.newStageEnds)
    .setZone(ROME_TZ)
    .toFormat("cccc dd LLL yyyy, HH:mm '(Rome)'");

  const subject = `Stage length changed for ${enquiryLabel}`;
  const html = `<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
<body style="margin:0;padding:0;">
  <p>Hello,</p>
  <p>The stage length for <strong>${enquiryLabel}</strong>${titleSuffix} has been changed.</p>
  <table style="border-collapse:collapse;margin:12px 0;">
    <tr>
      <td style="padding:4px 12px 4px 0;color:#555;">Previous stage length</td>
      <td style="padding:4px 0;"><strong>${oldStageLength}</strong> working day${oldStageLength === 1 ? "" : "s"}</td>
    </tr>
    <tr>
      <td style="padding:4px 12px 4px 0;color:#555;">New stage length</td>
      <td style="padding:4px 0;"><strong>${newStageLength}</strong> working day${newStageLength === 1 ? "" : "s"}</td>
    </tr>
    <tr>
      <td style="padding:4px 12px 4px 0;color:#555;">New stage deadline</td>
      <td style="padding:4px 0;"><strong>${newDeadline}</strong></td>
    </tr>
  </table>
  <p>The current stage's deadline has been adjusted accordingly.</p>
</body>
</html>`;

  const transporter = createTransport({
    service: "gmail",
    auth: {
      user: process.env.GMAIL_USER as string,
      pass: process.env.GMAIL_APP_PASSWORD as string,
    },
  });
  const fromAddress = `"Rule Post" <${process.env.GMAIL_USER}>`;

  // Chunked BCC to stay under Gmail's per-message recipient limit.
  await sendBccInChunks(transporter, {
    from: fromAddress,
    to: fromAddress,
    bcc: recipients,
    subject,
    html,
  });

  logger.info("[changeStageLength] Stage length change notification sent.", {
    recipientCount: recipients.length,
  });
}
