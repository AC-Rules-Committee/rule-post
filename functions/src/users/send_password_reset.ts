import { getAuth } from "firebase-admin/auth";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { createTransport } from "nodemailer";

const auth = getAuth();

type ResetPayload = { email: string };

/**
 * Allows a team admin to send a password-reset email to one of their
 * team members, or a site admin to reset any user's password.
 */
export const sendPasswordReset = onCall(
  {
    cors: true,
    enforceAppCheck: true,
    secrets: ["GMAIL_USER", "GMAIL_APP_PASSWORD"],
  },
  async (req) => {
    // ── 1. Auth & role check
    const callerUid = req.auth?.uid;
    if (!callerUid) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }

    const isSiteAdmin = req.auth?.token.role === "admin";
    const isTeamAdmin = req.auth?.token.teamAdmin;
    if (!isSiteAdmin && !isTeamAdmin) {
      throw new HttpsError(
        "permission-denied",
        "Team admin or site admin only.",
      );
    }

    const { email } = req.data as ResetPayload;
    if (!email) {
      throw new HttpsError("invalid-argument", "Missing email.");
    }

    const targetEmail = email.trim().toLowerCase();

    // ── 2. Verify the target user exists and belongs to caller's team
    let targetUser;
    try {
      targetUser = await auth.getUserByEmail(targetEmail);
    } catch {
      throw new HttpsError("not-found", "No user found with that email.");
    }

    // Site admins may reset any user; team admins only their own team
    if (!isSiteAdmin) {
      const callerTeam = req.auth?.token.team as string | undefined;
      const targetClaims = targetUser.customClaims ?? {};
      // Fail closed: a caller without a team claim must not bypass the check.
      if (!callerTeam || targetClaims.team !== callerTeam) {
        throw new HttpsError(
          "permission-denied",
          "You can only reset passwords for members of your own team.",
        );
      }
    }

    // ── 3. Generate the password-reset link
    const link = await auth.generatePasswordResetLink(targetEmail, {
      url: "https://rulepost.acofficials.org",
      handleCodeInApp: false,
    });
    console.log("✅ Password reset link created for", targetEmail);

    // ── 4. Send email via Gmail SMTP
    const transporter = createTransport({
      service: "gmail",
      auth: {
        user: process.env.GMAIL_USER as string,
        pass: process.env.GMAIL_APP_PASSWORD as string,
      },
    });

    const recipientName = getNameFromEmail(targetEmail);
    try {
      await transporter.sendMail({
        from: `"Rule Post" <${process.env.GMAIL_USER}>`,
        to: targetEmail,
        subject: "Reset your Rule Post password",
        html: `<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>
<body style="margin:0;padding:0;">
  <p>Hi ${recipientName},</p>
  <p>Your team admin has requested a password reset for your Rule Post account. Click the button below to set a new password.</p>
  <p><a href="${link}" style="display:inline-block;padding:10px 16px;border-radius:6px;background:#1a73e8;color:#fff;text-decoration:none;">Reset your password</a></p>
  <p>If you didn't expect this, you can ignore this email.</p>
</body>
</html>`,
      });
    } catch (emailErr) {
      console.error("❌ Failed to send password reset email:", emailErr);
      throw new HttpsError(
        "internal",
        "Password reset link was generated but the email could not be sent. Please try again.",
      );
    }
    console.log("✅ Password reset email sent to", targetEmail);

    return { email: targetEmail };
  },
);

function getNameFromEmail(email: string): string {
  const localPart = email.split("@")[0];
  const dotParts = localPart.split(".");
  if (dotParts.length > 1) {
    return dotParts
      .map((p) => p.charAt(0).toUpperCase() + p.slice(1).toLowerCase())
      .join(" ");
  }
  return localPart.charAt(0).toUpperCase() + localPart.slice(1).toLowerCase();
}
