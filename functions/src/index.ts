// ──────────────────────────────────────────────────────────────────────────────
// File: src/index.ts
// ──────────────────────────────────────────────────────────────────────────────
import { getApps, initializeApp } from "firebase-admin/app";
import { setGlobalOptions } from "firebase-functions/v2";

/** Global options for all functions. */
setGlobalOptions({
  region: "europe-west6",
  maxInstances: 10,
});

if (!getApps().length) {
  initializeApp();
}

/** App functions (re-exports) */
/** ─────────────────────────────── Users ─────────────────────────────── */
export { blockAllSelfRegistration } from "./users/new_users";
export { createUserWithProfile } from "./users/create_user";
export { deleteUser } from "./users/delete_user";
export { sendPasswordReset } from "./users/send_password_reset";
export { toggleUserLock } from "./users/toggle_user_lock";
export { syncCustomClaims } from "./users/claims_sync";

/** ─────────────────────────────── Posts ─────────────────────────────── */
export { createPost } from "./posts/create_post";
export { editPost } from "./posts/edit_post";
export { deletePost } from "./posts/delete_post";
export {
  onEnquiryDeleted,
  onResponseDeleted,
  onCommentDeleted,
} from "./posts/deleted_post_actions";

/** ──────────────────────────── Notifications ────────────────────────── */
export {
  onEnquiryIsPublishedUpdated,
  onResponseIsPublishedUpdated,
  onCommentIsPublishedUpdated,
} from "./notifications/send_publish_digest";
export { toggleEmailNotifications } from "./notifications/toggle_notifications";

/** ───────────────────────────── Scheduled ───────────────────────────── */
export {
  orchestrate0000,
  orchestrate1200,
  orchestrate2000,
  orchestrateDigestCatchup,
} from "./scheduled_funcs/orchestrator";

/** ─────────────────────────────── Admin ─────────────────────────────── */
export { changeStageLength } from "./admin_funcs/change_stage_length";
export { closeEnquiry } from "./admin_funcs/close_enquiry";
export { terminateStage } from "./admin_funcs/terminate_stage";
export { getPostAuthorsForEnquiry } from "./admin_funcs/get_post_authors";
export { inviteTeamAdmin } from "./admin_funcs/invite_team_admin";
export {
  adminListAllTeams,
  adminDeleteUser,
  adminToggleUserLock,
  adminDeleteTeam,
} from "./admin_funcs/admin_manage_users";
// export { markPostUnread } from "./admin_funcs/mark_post_unread";
export { responseInstantPublisher } from "./admin_funcs/response_instant_publisher";
export { testSendDigest } from "./admin_funcs/test_send_digest";

/** ─────────────────────────────── Utils ─────────────────────────────── */
