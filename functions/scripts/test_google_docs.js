const { google } = require("googleapis");

const SERVICE_ACCOUNT_KEY = require("../rulepost-docs-sync-service-account.json");
const IMPERSONATE_EMAIL = "rulescommittee@acofficials.org";
const DRIVE_FOLDER_ID = "1D0XpyLYq-2cNJo9y9taqtfxg2-iwjy6u";

async function test() {
  // 1. Authenticate with domain-wide delegation
  console.log("1. Authenticating as service account...");
  const auth = new google.auth.JWT({
    email: SERVICE_ACCOUNT_KEY.client_email,
    key: SERVICE_ACCOUNT_KEY.private_key,
    scopes: [
      "https://www.googleapis.com/auth/documents",
      "https://www.googleapis.com/auth/drive",
    ],
    subject: IMPERSONATE_EMAIL,
  });

  const docs = google.docs({ version: "v1", auth });
  const drive = google.drive({ version: "v3", auth });
  console.log("   OK\n");

  // 2. Create a test document
  console.log("2. Creating test Google Doc...");
  const createRes = await docs.documents.create({
    requestBody: { title: "RulePost Test - Delete Me" },
  });
  const docId = createRes.data.documentId;
  console.log(`   Doc created: https://docs.google.com/document/d/${docId}`);
  console.log("   OK\n");

  // 3. Move to the shared folder
  console.log("3. Moving doc to shared folder...");
  const file = await drive.files.get({ fileId: docId, fields: "parents" });
  const previousParents = (file.data.parents || []).join(",");
  await drive.files.update({
    fileId: docId,
    addParents: DRIVE_FOLDER_ID,
    removeParents: previousParents,
    requestBody: {},
  });
  console.log("   OK\n");

  // 4. Insert content into the doc
  console.log("4. Writing content to doc...");
  await docs.documents.batchUpdate({
    documentId: docId,
    requestBody: {
      requests: [
        {
          insertText: {
            location: { index: 1 },
            text:
              "This is a test post from RulePost.\n\n" +
              "If you can see this document in your shared folder, " +
              "the integration is working correctly!\n\n" +
              "You can safely delete this document.",
          },
        },
      ],
    },
  });
  console.log("   OK\n");

  // 5. Read back the doc to verify
  console.log("5. Verifying doc content...");
  const getRes = await docs.documents.get({ documentId: docId });
  console.log(`   Title: "${getRes.data.title}"`);
  console.log("   OK\n");

  console.log("=".repeat(50));
  console.log("ALL CHECKS PASSED!");
  console.log("=".repeat(50));
  console.log(`\nTest doc: https://docs.google.com/document/d/${docId}`);
  console.log(
    "Check your shared folder to confirm it appeared, then delete it."
  );
}

test().catch((err) => {
  console.error("\nVERIFICATION FAILED:\n");
  if (err.code === 403) {
    console.error("Permission denied. Check:");
    console.error(
      "  - Domain-wide delegation is configured in Google Workspace Admin"
    );
    console.error("  - Client ID matches: " + SERVICE_ACCOUNT_KEY.client_id);
    console.error("  - OAuth scopes are exactly:");
    console.error(
      "    https://www.googleapis.com/auth/documents,https://www.googleapis.com/auth/drive"
    );
    console.error(
      "  - The impersonated user (" +
        IMPERSONATE_EMAIL +
        ") exists in the Workspace"
    );
  } else if (err.code === 404) {
    console.error(
      "API not found. Ensure Google Docs API and Google Drive API are enabled"
    );
    console.error(
      "  at: https://console.cloud.google.com/apis/library?project=rulepost-c52d6"
    );
  } else if (err.message?.includes("invalid_grant")) {
    console.error("Domain-wide delegation is not set up correctly.");
    console.error("  - Go to admin.google.com -> Security -> API controls");
    console.error("  - Check Domain-wide delegation has the correct Client ID");
  } else {
    console.error(err.message || err);
  }
  process.exit(1);
});
