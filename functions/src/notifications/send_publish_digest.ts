// ──────────────────────────────────────────────────────────────────────────────
// File: src/notifications/send_email_on_publish.ts
// Purpose: Record new posts and publish daily digest to users
// ──────────────────────────────────────────────────────────────────────────────
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";
// import { onSchedule } from "firebase-functions/v2/scheduler";
import { createTransport } from "nodemailer";

import {
  BasePublishable,
  EnquiryDoc,
  ResponseDoc,
  CommentDoc,
  PublishEventData,
  EnquiryParams,
  ResponseParams,
  CommentParams,
  UserData,
} from "../common/types";
import { sendBccInChunks } from "../utils/email_batch";

const db = getFirestore();

/* ─────────────────────────── helpers ─────────────────────────── */

function becamePublished(
  before: Pick<BasePublishable, "isPublished"> | undefined,
  after: Pick<BasePublishable, "isPublished"> | undefined,
): boolean {
  if (!before || !after) return false;
  return Boolean(after.isPublished) && before.isPublished !== after.isPublished;
}

// Note: recipient partitioning is handled inside sendDigestFor below.

interface ExpiringDeadline {
  enquiryId: string;
  enquiryNumber: string;
  enquiryTitle: string;
  deadlineTime: string; // "20:00"
  hoursRemaining: number;
}

/** Check for response deadlines expiring in the next 24 hours */
async function getExpiringResponseDeadlines(
  userTeam: string,
): Promise<ExpiringDeadline[]> {
  const deadlines: ExpiringDeadline[] = [];

  // Get all enquiries where teams can still respond
  const enquiriesSnap = await db
    .collection("enquiries")
    .where("teamsCanRespond", "==", true)
    .get();

  for (const enquirySnap of enquiriesSnap.docs) {
    const enquiry = enquirySnap.data() as Record<string, unknown>;
    const enquiryId = enquirySnap.id;
    const enquiryNumber = enquiry.enquiryNumber as string;
    const enquiryTitle = enquiry.title as string;

    // Check if this team already submitted a response
    const responsesSnap = await enquirySnap.ref.collection("responses").get();

    let teamAlreadyResponded = false;
    for (const respSnap of responsesSnap.docs) {
      try {
        const metaSnap = await respSnap.ref
          .collection("meta")
          .doc("data")
          .get();
        if (metaSnap.exists) {
          const authorTeam = metaSnap.get("authorTeam") as string | undefined;
          if (authorTeam === userTeam) {
            teamAlreadyResponded = true;
            break;
          }
        }
      } catch (error) {
        logger.warn("Failed to fetch response meta", { enquiryId, error });
      }
    }

    // Skip if team already responded
    if (teamAlreadyResponded) continue;

    // Check if deadline expires in next 24 hours (estimate: deadline is 20:00 Rome)
    const stageEnds = enquiry.stageEnds as Record<string, unknown> | undefined;
    if (stageEnds && typeof stageEnds === "object" && "response" in stageEnds) {
      // stageEnds.response is a Timestamp; check if it's within next 24 hours
      const responseDeadline = stageEnds.response;
      if (
        responseDeadline &&
        typeof responseDeadline === "object" &&
        "seconds" in responseDeadline
      ) {
        const deadlineSeconds =
          (responseDeadline as { seconds: number }).seconds * 1000;
        const nowMs = Date.now();
        const hoursRemaining = (deadlineSeconds - nowMs) / 1000 / 3600;

        if (hoursRemaining > 0 && hoursRemaining <= 24) {
          deadlines.push({
            enquiryId,
            enquiryNumber,
            enquiryTitle,
            deadlineTime: "20:00 Rome",
            hoursRemaining: Math.ceil(hoursRemaining),
          });
        }
      }
    }
  }

  return deadlines;
}

/** simple digest email HTML */
function renderDigestHTML(
  groups: {
    enquiries: Array<
      Pick<PublishEventData, "enquiryId" | "enquiryTitle" | "enquiryNumber">
    >;
    responses: Array<
      Pick<
        PublishEventData,
        | "enquiryId"
        | "enquiryTitle"
        | "enquiryNumber"
        | "responseId"
        | "roundNumber"
        | "responseNumber"
      >
    >;
    comments: Array<
      Pick<
        PublishEventData,
        | "enquiryId"
        | "enquiryNumber"
        | "enquiryTitle"
        | "responseId"
        | "roundNumber"
        | "responseNumber"
      >
    >;
  },
  expiringDeadlines?: ExpiringDeadline[],
): string {
  const plural = (n: number, one: string, many: string) =>
    n === 1 ? one : many;

  // --- Group comments by (enquiryId, responseId) ---
  type CommentSummary = {
    enquiryId: string;
    enquiryNumber: string;
    enquiryTitle: string;
    responseId: string;
    roundNumber: string;
    responseNumber: string;
    count: number;
  };

  const groupedComments = Array.from(
    groups.comments
      .reduce((m, c) => {
        const key = `${c.enquiryId}::${c.responseId}`;
        const found = m.get(key);
        if (found) {
          found.count += 1;
        } else {
          m.set(key, {
            enquiryId: c.enquiryId,
            enquiryNumber: c.enquiryNumber,
            enquiryTitle: c.enquiryTitle,
            responseId: c.responseId,
            roundNumber: c.roundNumber,
            responseNumber: c.responseNumber,
            count: 1,
          } as CommentSummary);
        }
        return m;
      }, new Map<string, CommentSummary>())
      .values(),
  );

  // tiny helper to prevent broken markup / injection from titles
  const esc = (s: string | undefined) =>
    (s ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");

  // shared inline styles for links and small/muted text
  const linkStyle = "color:#007bff;text-decoration:underline;";
  const muted = "color:#666;";
  const formatEnquiryNumber = (raw: string | number | undefined): string => {
    const n = String(raw ?? "").trim();
    return /^\d+$/.test(n) ? n.padStart(3, "0") : n;
  };

  // table row builder (avoids <ul> quirks in Outlook)
  const sectionTable = <T>(
    title: string,
    items: T[],
    fmt: (x: T) => string,
  ): string =>
    items.length
      ? `
        <tr>
          <td style="padding:16px 0 8px 0;font-weight:600;font-size:16px">${title}</td>
        </tr>
        ${items
          .map(
            (x) => `
            <tr>
              <td style="padding:8px 0;font-size:14px;line-height:1.4">
                ${fmt(x)}
              </td>
            </tr>`,
          )
          .join("")}
      `
      : "";

  // Precompute the comments list items as strings (kept from your logic)
  const commentItems = groupedComments.map(
    (g) =>
      `${g.count} ${plural(g.count, "comment", "comments")} on 
      <a href="https://rulepost.acofficials.org/#/enquiries/${g.enquiryId}/responses/${g.responseId}" style="${linkStyle}">
      Response ${g.roundNumber}.${g.responseNumber}</a> of Rule Enquiry ${formatEnquiryNumber(g.enquiryNumber)} — ${esc(g.enquiryTitle)}`,
  );

  // Render urgent deadline section if present
  const deadlineSection =
    expiringDeadlines && expiringDeadlines.length > 0
      ? `
        <tr style="background:#fee;border-top:4px solid #d32f2f;border-bottom:1px solid #ffcccc;">
          <td style="padding:16px 24px;font-family:system-ui,Segoe UI,Roboto,Arial,sans-serif;">
            <h2 style="margin:0 0 12px 0;font-size:18px;line-height:1.3;font-weight:700;color:#d32f2f;">
              ⏰ Action Required: Response Deadline Approaching
            </h2>
            <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%">
              ${expiringDeadlines
                .map(
                  (d) =>
                    `<tr>
                      <td style="padding:8px 0;font-size:14px;line-height:1.4;color:#333;">
                        <strong>Rule Enquiry ${esc(formatEnquiryNumber(d.enquiryNumber))}</strong>: <a href="https://rulepost.acofficials.org/#/enquiries/${d.enquiryId}" style="${linkStyle}">${esc(d.enquiryTitle)}</a>
                        <br />
                        <span style="color:#d32f2f;font-weight:600;">Deadline: ${d.deadlineTime} (${d.hoursRemaining} hour${d.hoursRemaining === 1 ? "" : "s"} remaining)</span>
                      </td>
                    </tr>`,
                )
                .join("")}
            </table>
          </td>
        </tr>
        <tr style="height:4px;background:#f6f7f9;" />
      `
      : "";

  return `<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin:0;padding:0;">
  <!-- Preheader (hidden) -->
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;font-size:1px;line-height:1px;">
    ${expiringDeadlines && expiringDeadlines.length > 0 ? "Action required: response deadline approaching. " : ""}New Rule Post publications: enquiries, responses, and comments.
  </div>

  <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#f6f7f9;padding:24px 0;">
    <tr>
      <td align="center">
        <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="600" style="width:100%;max-width:600px;background:#ffffff;border-radius:6px;overflow:hidden;">
          ${deadlineSection}
          <tr>
            <td style="padding:20px 24px;font-family:system-ui,Segoe UI,Roboto,Arial,sans-serif;">
              <h2 style="margin:0 0 12px 0;font-size:20px;line-height:1.3;font-weight:700;">
                Newly published on Rule Post:
              </h2>

              <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%">
                ${sectionTable(
                  "Enquiries",
                  groups.enquiries,
                  (e) =>
                    `Rule Enquiry ${formatEnquiryNumber(e.enquiryNumber)} — 
                    <a href="https://rulepost.acofficials.org/#/enquiries/${e.enquiryId}" style="${linkStyle}">
                      ${esc(e.enquiryTitle)}
                    </a>`,
                )}

                ${sectionTable(
                  "Responses",
                  groups.responses,
                  (r) =>
                    `<a href="https://rulepost.acofficials.org/#/enquiries/${r.enquiryId}/responses/${r.responseId}" style="${linkStyle}" aria-label="Response ${r.roundNumber}.${r.responseNumber}">
                          Response ${r.roundNumber}.${r.responseNumber}</a> to Rule Enquiry ${formatEnquiryNumber(r.enquiryNumber)} — ${esc(r.enquiryTitle)}`,
                )}

                ${sectionTable("Comments", commentItems, (html) => html)}
              </table>

              <hr style="border:none;border-top:1px solid #e6e7eb;margin:16px 0;" />

              <p style="${muted};font-size:12px;margin:0;">
                You receive this because you opted into updates.
                <a href="https://rulepost.acofficials.org/#/user-details" style="${linkStyle};margin-left:4px;">
                  Manage email settings
                </a>
              </p>
            </td>
          </tr>
        </table>

        <!-- optional footer spacing for mobile tap comfort -->
        <div style="height:24px;line-height:24px;">&#8202;</div>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

/** send one digest to all recipients, then mark events processed */
async function sendDigestFor(
  events: FirebaseFirestore.QueryDocumentSnapshot<PublishEventData>[],
): Promise<void> {
  if (events.length === 0) return;

  // Fetch recipients and partition by scope.
  const snap = await db
    .collection("user_data")
    .where("emailNotificationsOn", "==", true)
    .get();

  // Group users by team for deadline checking
  type UserByTeam = {
    emails: string[];
    scope: "all" | "enquiries";
  };
  const usersByTeam = new Map<string, UserByTeam>();

  snap.docs.forEach((d) => {
    const ud = d.data() as UserData;
    const email = ud.email;
    if (!email) return;
    const team = ud.team || "unknown";
    const scope = (ud.emailNotificationsScope as "all" | "enquiries") ?? "all";

    if (!usersByTeam.has(team)) {
      usersByTeam.set(team, { emails: [], scope });
    }
    const teamData = usersByTeam.get(team)!;
    teamData.emails.push(email);
    // Use the broadest scope if team has mixed preferences
    if (scope === "all") teamData.scope = "all";
  });

  if (usersByTeam.size === 0) {
    logger.info("No recipients; marking events processed without sending.");
    const batch = db.batch();
    events.forEach((d) =>
      batch.update(d.ref, {
        processed: true,
        processedAt: FieldValue.serverTimestamp(),
      }),
    );
    await batch.commit();
    return;
  }

  type Groups = {
    enquiries: PublishEventData[];
    responses: PublishEventData[];
    comments: PublishEventData[];
  };

  const groups: Groups = { enquiries: [], responses: [], comments: [] };

  for (const d of events) {
    const e = d.data();
    if (e.kind === "enquiry") groups.enquiries.push(e);
    else if (e.kind === "response") groups.responses.push(e);
    else if (e.kind === "comment") groups.comments.push(e);
  }

  const subject = "New publications on Rule Post";
  const transporter = createTransport({
    service: "gmail",
    auth: {
      user: process.env.GMAIL_USER as string,
      pass: process.env.GMAIL_APP_PASSWORD as string,
    },
  });
  const fromAddress = `"Rule Post" <${process.env.GMAIL_USER}>`;

  // Verify SMTP credentials before attempting to send
  try {
    await transporter.verify();
  } catch (verifyErr) {
    logger.error(
      "[sendDigestFor] SMTP verification failed — aborting digest. Events will NOT be marked processed.",
      { error: verifyErr },
    );
    return;
  }

  let anyTeamSucceeded = false;

  // Send personalized digest to each team
  for (const [team, teamData] of usersByTeam.entries()) {
    // Check for expiring response deadlines for this team
    const expiringDeadlines = await getExpiringResponseDeadlines(team);

    // Only send if there are publications OR expiring deadlines for this team
    const hasActivity =
      groups.enquiries.length > 0 ||
      groups.responses.length > 0 ||
      groups.comments.length > 0;
    const hasDeadlines = expiringDeadlines.length > 0;

    if (!hasActivity && !hasDeadlines) {
      logger.debug(
        "[sendDigestFor] Skipping team with no activity or deadlines",
        {
          team,
        },
      );
      continue;
    }

    // Determine what content to send based on scope
    let emailGroups: Groups;
    if (teamData.scope === "enquiries") {
      emailGroups = {
        enquiries: groups.enquiries,
        responses: [],
        comments: [],
      };
      // Only send enquiries-only if there are enquiries
      if (emailGroups.enquiries.length === 0 && !hasDeadlines) continue;
    } else {
      emailGroups = groups;
    }

    const html = renderDigestHTML(emailGroups, expiringDeadlines);

    try {
      await sendBccInChunks(transporter, {
        from: fromAddress,
        to: fromAddress,
        bcc: teamData.emails,
        subject,
        html,
      });
      anyTeamSucceeded = true;
      logger.info("[sendDigestFor] Email sent to team", {
        team,
        recipientCount: teamData.emails.length,
        hasDeadlines,
      });
    } catch (error) {
      logger.error("[sendDigestFor] Failed to send email to team", {
        team,
        error,
      });
    }
  }

  if (!anyTeamSucceeded) {
    logger.error(
      "[sendDigestFor] All email sends failed — events will NOT be marked processed for retry.",
    );
    return;
  }

  const batch = db.batch();
  events.forEach((d) =>
    batch.update(d.ref, {
      processed: true,
      processedAt: FieldValue.serverTimestamp(),
    }),
  );
  await batch.commit();
}

/* ───────────────────── triggers (write events) ───────────────────── */

// enquiries/{enquiryId}
export const onEnquiryIsPublishedUpdated = onDocumentUpdated(
  { document: "enquiries/{enquiryId}" },
  async (event): Promise<void> => {
    const before = event.data?.before?.data() as EnquiryDoc | undefined;
    const after = event.data?.after?.data() as EnquiryDoc | undefined;
    if (!becamePublished(before, after) || !after) return;

    const { enquiryId } = event.params as EnquiryParams;

    const now = Timestamp.now();
    const doc: PublishEventData = {
      kind: "enquiry",
      enquiryId,
      enquiryTitle: after.title,
      enquiryNumber: after.enquiryNumber,
      publishedAt: after.publishedAt ?? now,
      createdAt: now,
      processed: false,
    };
    await db.collection("publishEvents").add(doc);
  },
);

// enquiries/{enquiryId}/responses/{responseId}
export const onResponseIsPublishedUpdated = onDocumentUpdated(
  { document: "enquiries/{enquiryId}/responses/{responseId}" },
  async (event): Promise<void> => {
    const before = event.data?.before?.data() as ResponseDoc | undefined;
    const after = event.data?.after?.data() as ResponseDoc | undefined;
    if (!becamePublished(before, after) || !after) return;

    const { enquiryId, responseId } = event.params as ResponseParams;

    // 🔍 Fetch the parent enquiry document
    const enquirySnap = await db.collection("enquiries").doc(enquiryId).get();
    const enquiryData = enquirySnap.data() as EnquiryDoc | undefined;
    const enquiryTitle = enquiryData?.title ?? "(Untitled enquiry)";
    const enquiryNumber = enquiryData?.enquiryNumber ?? "(Unnumbered enquiry)";

    const now = Timestamp.now();
    const doc: PublishEventData = {
      kind: "response",
      enquiryId,
      responseId,
      enquiryTitle: enquiryTitle,
      enquiryNumber: enquiryNumber,
      roundNumber: after.roundNumber,
      responseNumber: after.responseNumber,
      publishedAt: after.publishedAt ?? now,
      createdAt: now,
      processed: false,
    };
    await db.collection("publishEvents").add(doc);
  },
);

// enquiries/{enquiryId}/responses/{responseId}/comments/{commentId}
export const onCommentIsPublishedUpdated = onDocumentUpdated(
  {
    document:
      "enquiries/{enquiryId}/responses/{responseId}/comments/{commentId}",
  },
  async (event): Promise<void> => {
    const before = event.data?.before?.data() as CommentDoc | undefined;
    const after = event.data?.after?.data() as CommentDoc | undefined;
    if (!becamePublished(before, after) || !after) return;

    const { enquiryId, responseId, commentId } = event.params as CommentParams;

    // 🔍 Fetch the parent enquiry document
    const enquirySnap = await db.collection("enquiries").doc(enquiryId).get();
    const enquiryData = enquirySnap.data() as EnquiryDoc | undefined;
    const enquiryTitle = enquiryData?.title ?? "(Untitled enquiry)";
    const enquiryNumber = enquiryData?.enquiryNumber ?? "(Unnumbered enquiry)";
    const responseSnap = await db
      .collection("enquiries")
      .doc(enquiryId)
      .collection("responses")
      .doc(responseId)
      .get();
    const responseData = responseSnap.data() as ResponseDoc | undefined;
    const responseRound = responseData?.roundNumber ?? "x";
    const responseNumber = responseData?.responseNumber ?? "x";

    const now = Timestamp.now();
    const doc: PublishEventData = {
      kind: "comment",
      enquiryId,
      responseId,
      commentId,
      enquiryTitle: enquiryTitle,
      enquiryNumber: enquiryNumber,
      roundNumber: responseRound,
      responseNumber: responseNumber,
      publishedAt: after.publishedAt ?? now,
      createdAt: now,
      processed: false,
    };
    await db.collection("publishEvents").add(doc);
  },
);

/* ───────────────────── scheduler (send digest) ───────────────────── */

// Lease-based lock so overlapping digest runs (scheduled + 2-minute catch-up)
// cannot read the same unprocessed events and send duplicate emails.
const digestLockRef = db.collection("app_data").doc("digest_lock");
// Must exceed the function timeout (120s) so a crashed run's lease expires.
const DIGEST_LOCK_LEASE_MS = 5 * 60 * 1000;

async function acquireDigestLock(): Promise<boolean> {
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(digestLockRef);
    const lockedAt = snap.exists
      ? (snap.get("lockedAt") as Timestamp | null | undefined)
      : undefined;
    if (lockedAt && Date.now() - lockedAt.toMillis() < DIGEST_LOCK_LEASE_MS) {
      return false; // another run holds a live lease
    }
    tx.set(digestLockRef, { lockedAt: Timestamp.now() });
    return true;
  });
}

async function releaseDigestLock(): Promise<void> {
  try {
    await digestLockRef.set({ lockedAt: null });
  } catch (e) {
    // Non-fatal: the lease will expire on its own.
    logger.warn("[doSendPublishDigest] Failed to release digest lock", {
      error: e,
    });
  }
}

/** Helper function extracted for use by orchestrator */
export async function doSendPublishDigest(): Promise<void> {
  if (!(await acquireDigestLock())) {
    logger.info(
      "[doSendPublishDigest] Another digest run holds the lock; skipping.",
    );
    return;
  }
  try {
    const now = Timestamp.now();
    const snap = await db
      .collection("publishEvents")
      .where("processed", "==", false)
      .where("publishedAt", "<=", now)
      .orderBy("publishedAt", "asc")
      .limit(500)
      .get();

    // type-annotate here so .data() is strongly typed above
    const docs =
      snap.docs as FirebaseFirestore.QueryDocumentSnapshot<PublishEventData>[];
    await sendDigestFor(docs);
    logger.info("Digest processed", { count: snap.size });
  } finally {
    await releaseDigestLock();
  }
}

// ✅ Note: sendPublishDigest is no longer exported directly.
// It is called by the orchestrator (orchestrate0000, orchestrate1200, orchestrate2000).
// Legacy export commented out:
/*
export const sendPublishDigest = onSchedule(
  {
    // 00:05, 12:05, and 20:05 every day
    schedule: "5 0,12,20 * * *",
    timeZone: "Europe/Rome",
    secrets: ["GMAIL_USER", "GMAIL_APP_PASSWORD"],
    region: "europe-west6",
  },
  async (): Promise<void> => {
    await doSendPublishDigest();
  },
);
*/
