// ──────────────────────────────────────────────────────────────────────────────
// File: src/utils/public_markdown.ts
// Purpose: Read-only HTTP endpoint serving PUBLISHED content as markdown, so
//          AI tools / crawlers can read the site (Flutter web renders to canvas
//          and is invisible to them).
//
// SECURITY MODEL (must mirror firestore.rules for anonymous users):
//   • Only documents with isPublished == true are ever returned.
//   • Output is built from an explicit field whitelist — whole docs are never
//     serialised. Drafts and meta/ subcollections (authorUid/authorTeam) are
//     never read.
// ──────────────────────────────────────────────────────────────────────────────
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onRequest } from "firebase-functions/v2/https";

import { REGION } from "../common/config";

import type { DocumentSnapshot } from "firebase-admin/firestore";

/** Only these fields are ever emitted. Everything else is dropped. */
type PublicAttachment = { name: string; url: string };

const MAX_INDEX_DOCS = 500;
const ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

/** Canonical public origin (Hosting rewrites /api/public/** to this function). */
const SITE_ORIGIN = "https://rulepost-c52d6.web.app";

// Browser cache 5 min; Hosting CDN cache 1 h (absorbs crawler traffic).
const CACHE_CONTROL = "public, max-age=300, s-maxage=3600";

function fmtDate(v: unknown): string | null {
  if (v instanceof Timestamp) return v.toDate().toISOString().slice(0, 10);
  return null;
}

function publicAttachments(v: unknown): PublicAttachment[] {
  if (!Array.isArray(v)) return [];
  const out: PublicAttachment[] = [];
  for (const a of v) {
    const name = typeof a?.name === "string" ? a.name : null;
    const url = typeof a?.url === "string" ? a.url : null;
    // Only published attachments carry a tokened public URL.
    if (name && url) out.push({ name, url });
  }
  return out;
}

function attachmentsBlock(v: unknown): string {
  const atts = publicAttachments(v);
  if (!atts.length) return "";
  const lines = atts.map((a) => `- [${a.name}](${a.url})`);
  return `\n**Attachments:**\n${lines.join("\n")}\n`;
}

function str(v: unknown): string {
  return typeof v === "string" ? v : "";
}

/** True only when the doc exists and is strictly published. */
function isPublishedDoc(snap: DocumentSnapshot): boolean {
  return snap.exists && snap.get("isPublished") === true;
}

// ── Markdown builders (whitelisted fields only) ──────────────────────────────

function enquiryHeaderMd(snap: DocumentSnapshot): string {
  const n = snap.get("enquiryNumber");
  const title = str(snap.get("title"));
  const isOpen = snap.get("isOpen") === true;
  const published = fmtDate(snap.get("publishedAt"));
  const conclusion = str(snap.get("enquiryConclusion"));

  let md = `# Rule Enquiry ${typeof n === "number" ? `#${n}` : ""}: ${title}\n\n`;
  md += `- Status: ${isOpen ? "open" : "closed"}\n`;
  if (published) md += `- Published: ${published}\n`;
  md += "\n";
  const body = str(snap.get("postText"));
  if (body) md += `${body}\n`;
  md += attachmentsBlock(snap.get("attachments"));
  if (conclusion) md += `\n## Conclusion\n\n${conclusion}\n`;
  return md;
}

function responseMd(snap: DocumentSnapshot): string {
  const fromRC = snap.get("fromRC") === true;
  const round = snap.get("roundNumber");
  const published = fmtDate(snap.get("publishedAt"));
  const title = str(snap.get("title"));

  const author = fromRC ? "Rules Committee" : "Competitor";
  let md = `## Response (${author}`;
  if (typeof round === "number") md += `, round ${round}`;
  if (published) md += `, ${published}`;
  md += ")";
  if (title) md += `: ${title}`;
  md += "\n\n";
  const body = str(snap.get("postText"));
  if (body) md += `${body}\n`;
  md += attachmentsBlock(snap.get("attachments"));
  return md;
}

function commentMd(snap: DocumentSnapshot): string {
  const fromRC = snap.get("fromRC") === true;
  const published = fmtDate(snap.get("publishedAt"));
  const title = str(snap.get("title"));

  const author = fromRC ? "Rules Committee" : "Competitor";
  let md = `### Comment (${author}`;
  if (published) md += `, ${published}`;
  md += ")";
  if (title) md += `: ${title}`;
  md += "\n\n";
  const body = str(snap.get("postText"));
  if (body) md += `${body}\n`;
  md += attachmentsBlock(snap.get("attachments"));
  return md;
}

// ── Route handlers ────────────────────────────────────────────────────────────

async function enquiriesIndexMd(): Promise<string> {
  const db = getFirestore();
  const snap = await db
    .collection("enquiries")
    .where("isPublished", "==", true)
    .orderBy("enquiryNumber", "desc")
    .limit(MAX_INDEX_DOCS)
    .get();

  let md = "# Rule Post — Published Rule Enquiries\n\n";
  md +=
    "Each entry links to a markdown document containing the full enquiry, " +
    "responses and comments.\n\n";
  for (const doc of snap.docs) {
    const n = doc.get("enquiryNumber");
    const title = str(doc.get("title"));
    const isOpen = doc.get("isOpen") === true;
    const published = fmtDate(doc.get("publishedAt"));
    md += `- [Enquiry ${typeof n === "number" ? `#${n}` : ""}: ${title}](${SITE_ORIGIN}/api/public/enquiries/${doc.id}.md)`;
    md += ` — ${isOpen ? "open" : "closed"}`;
    if (published) md += `, published ${published}`;
    md += "\n";
  }
  return md;
}

async function enquiryThreadMd(enquiryId: string): Promise<string | null> {
  const db = getFirestore();
  const enquiryRef = db.collection("enquiries").doc(enquiryId);
  const enquirySnap = await enquiryRef.get();
  // Drafts and unknown ids are indistinguishable to the outside: 404.
  if (!isPublishedDoc(enquirySnap)) return null;

  let md = enquiryHeaderMd(enquirySnap);

  const responses = await enquiryRef
    .collection("responses")
    .where("isPublished", "==", true)
    .orderBy("publishedAt", "asc")
    .get();

  for (const resp of responses.docs) {
    md += `\n---\n\n${responseMd(resp)}`;

    const comments = await resp.ref
      .collection("comments")
      .where("isPublished", "==", true)
      .orderBy("publishedAt", "asc")
      .get();
    for (const c of comments.docs) {
      md += `\n${commentMd(c)}`;
    }
  }
  return md;
}

// ── HTTP entry point ─────────────────────────────────────────────────────────

export const publicMarkdown = onRequest(
  {
    region: REGION,
    memory: "256MiB",
    timeoutSeconds: 30,
    maxInstances: 2,
    // Public, unauthenticated, read-only endpoint by design.
    invoker: "public",
  },
  async (req, res) => {
    if (req.method !== "GET") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    res.setHeader("Content-Type", "text/markdown; charset=utf-8");
    res.setHeader("X-Content-Type-Options", "nosniff");
    res.setHeader("Cache-Control", CACHE_CONTROL);

    // Path arrives as /api/public/... via the Hosting rewrite.
    const path = req.path.replace(/^\/api\/public/, "");

    try {
      if (path === "/enquiries.md" || path === "/enquiries" || path === "/") {
        res.status(200).send(await enquiriesIndexMd());
        return;
      }

      const m = path.match(/^\/enquiries\/([^/]+?)(?:\.md)?$/);
      if (m && ID_PATTERN.test(m[1])) {
        const md = await enquiryThreadMd(m[1]);
        if (md === null) {
          res.status(404).send("Not found.");
          return;
        }
        res.status(200).send(md);
        return;
      }

      res.status(404).send("Not found.");
    } catch (e) {
      res.setHeader("Cache-Control", "no-store");
      res.status(500).send("Internal error.");
      // Log without echoing details to the client.
      logger.error("publicMarkdown error", e);
    }
  },
);
