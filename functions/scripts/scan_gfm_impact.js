/**
 * Read-only Firestore scan to assess GFM-enablement impact on existing posts.
 *
 * It reads `postText` from every published/unpublished doc across:
 *   - enquiries/{id}
 *   - enquiries/{id}/responses/{id}        (collectionGroup "responses")
 *   - enquiries/{id}/responses/{id}/comments/{id}  (collectionGroup "comments")
 *
 * For each post it determines:
 *   - rendersToday : does it currently pass the app's _containsMarkdown gate?
 *   - hasGfmOnly   : does it contain a GFM-specific pattern (strikethrough/table)?
 *
 * The posts that would CHANGE appearance if we widen the gate are those where
 *   hasGfmOnly === true && rendersToday === false
 * (plain text today -> would become GFM-rendered).
 *
 * Posts where hasGfmOnly === true && rendersToday === true already render under
 * GFM today (flutter_markdown defaults to gitHubFlavored), so they are unchanged.
 *
 * NOTHING IS WRITTEN. This is strictly a read-only report.
 *
 * Auth: relies on Application Default Credentials or GOOGLE_APPLICATION_CREDENTIALS.
 *   GOOGLE_APPLICATION_CREDENTIALS=/path/to/serviceAccount.json \
 *     node functions/scripts/scan_gfm_impact.js
 */

const admin = require("firebase-admin");

admin.initializeApp({ projectId: "rulepost-c52d6" });
const db = admin.firestore();

// Mirror of the app's _containsMarkdown gate (standard markdown the UI already renders).
const CURRENT_GATE = [
  /\*\*\*.+?\*\*\*/, // ***bold+italic***
  /\*\*.+?\*\*/, // **bold**
  /__.+?__/, // __bold__
  /\*.+?\*/, // *italic*
  /_.+?_/, // _italic_
  /`[^`]+`/, // `code`
  /^#+\s/m, // # Headers
  /^\s*[-*+]\s/m, // - lists
  /^\s*\d+\.\s/m, // 1. numbered lists
  />.+/, // > blockquotes
  /https?:\/\/\S+/, // bare URLs
];

const rendersToday = (t) => CURRENT_GATE.some((re) => re.test(t));

// GFM-specific constructs that are NOT in the current gate.
const STRIKETHROUGH = /~~.+?~~/;
// A table needs a header row with a pipe AND a delimiter row of ---/:--: separated by pipes.
const TABLE_DELIM = /^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$/m;
const hasTable = (t) => /\|/.test(t) && TABLE_DELIM.test(t);
const hasStrikethrough = (t) => STRIKETHROUGH.test(t);

function classify(text) {
  const t = String(text ?? "");
  if (!t.trim()) return null;
  const gfmStrike = hasStrikethrough(t);
  const gfmTable = hasTable(t);
  if (!gfmStrike && !gfmTable) return null; // no GFM-specific content, irrelevant
  return {
    rendersToday: rendersToday(t),
    gfmStrike,
    gfmTable,
    snippet: t.replace(/\s+/g, " ").slice(0, 120),
  };
}

async function scan() {
  const findings = { willChange: [], alreadyGfm: [] };
  let total = 0;

  const groups = [
    { label: "enquiry", q: db.collection("enquiries") },
    { label: "response", q: db.collectionGroup("responses") },
    { label: "comment", q: db.collectionGroup("comments") },
  ];

  for (const { label, q } of groups) {
    const snap = await q.get();
    for (const doc of snap.docs) {
      total++;
      const res = classify(doc.data().postText);
      if (!res) continue;
      const entry = {
        type: label,
        path: doc.ref.path,
        gfm: [res.gfmStrike && "strikethrough", res.gfmTable && "table"]
          .filter(Boolean)
          .join("+"),
        snippet: res.snippet,
      };
      (res.rendersToday ? findings.alreadyGfm : findings.willChange).push(entry);
    }
  }

  console.log(`\nScanned ${total} posts (enquiries + responses + comments).\n`);

  console.log(
    `=== Posts that WOULD CHANGE appearance (plain text today -> GFM): ${findings.willChange.length} ===`,
  );
  for (const e of findings.willChange) {
    console.log(`  [${e.gfm}] ${e.path}`);
    console.log(`        "${e.snippet}"`);
  }

  console.log(
    `\n=== Posts ALREADY rendered under GFM today (no change): ${findings.alreadyGfm.length} ===`,
  );
  for (const e of findings.alreadyGfm) {
    console.log(`  [${e.gfm}] ${e.path}`);
    console.log(`        "${e.snippet}"`);
  }

  console.log("\nDone (read-only, nothing written).");
}

scan()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Scan failed:", err.message);
    process.exit(1);
  });
