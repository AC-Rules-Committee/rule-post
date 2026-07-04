// ──────────────────────────────────────────────────────────────────────────────
// File: src/users/toggle_user_lock.ts
// Purpose: Allows a team admin to lock (disable) or unlock (enable) a member
//          of their own team.  The caller must hold the `teamAdmin` custom
//          claim and the target must belong to the same team.
//          Also persists `disabled` to the Firestore user_data doc so the
//          client-side stream can show lock status.
// ──────────────────────────────────────────────────────────────────────────────
import { getAuth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onCall, HttpsError } from "firebase-functions/v2/https";

const auth = getAuth();
const db = getFirestore();

type ToggleLockPayload = { email: string; disabled: boolean };

export const toggleUserLock = onCall(
  { cors: true, enforceAppCheck: true },
  async (req) => {
    // ── 1. Auth & role check
    const callerUid = req.auth?.uid;
    if (!callerUid) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }

    const isTeamAdmin = req.auth?.token.teamAdmin;
    if (!isTeamAdmin) {
      throw new HttpsError("permission-denied", "Team admin only.");
    }

    const { email, disabled } = req.data as ToggleLockPayload;
    if (!email || typeof email !== "string" || !email.includes("@")) {
      throw new HttpsError("invalid-argument", "Missing or invalid email.");
    }
    if (typeof disabled !== "boolean") {
      throw new HttpsError("invalid-argument", "Missing disabled flag.");
    }

    const targetEmail = email.trim().toLowerCase();

    // ── 2. Verify the target user exists and belongs to caller's team
    let targetUser;
    try {
      targetUser = await auth.getUserByEmail(targetEmail);
    } catch {
      throw new HttpsError("not-found", "No user found with that email.");
    }

    if (targetUser.uid === callerUid) {
      throw new HttpsError(
        "failed-precondition",
        "You cannot lock your own account.",
      );
    }

    const callerTeam = req.auth?.token.team as string | undefined;
    const targetClaims = targetUser.customClaims ?? {};
    // Fail closed: a caller without a team claim must not bypass the check.
    if (!callerTeam || targetClaims.team !== callerTeam) {
      throw new HttpsError(
        "permission-denied",
        "You can only lock/unlock members of your own team.",
      );
    }

    // ── 3. Toggle disabled on Auth
    await auth.updateUser(targetUser.uid, { disabled });
    const action = disabled ? "locked" : "unlocked";
    logger.info(`✅ User ${action}`, {
      uid: targetUser.uid,
      email: targetEmail,
    });

    // ── 4. Persist to Firestore so client-side streams reflect the change
    try {
      await db.collection("user_data").doc(targetUser.uid).update({ disabled });
    } catch (e: unknown) {
      const msg =
        typeof e === "object" && e !== null && "message" in e
          ? String((e as { message?: unknown }).message)
          : String(e);
      logger.warn("Firestore disabled-flag update failed", {
        uid: targetUser.uid,
        error: msg,
      });
      // Non-fatal — Auth change succeeded
    }

    return { ok: true, email: targetEmail, disabled };
  },
);
