// ────────────────────────────────────────────────────────────────────────────
// File: src/common/types.ts
// Purpose: Shared TS types
// ────────────────────────────────────────────────────────────────────────────
import { Timestamp } from "firebase-admin/firestore";

export type TempAttachmentIn = {
  name: string;
  storagePath: string;
  size?: number;
  contentType?: string;
};

export type FinalisedAttachment = {
  name: string; // final name used in GCS
  path: string; // full storage path (folder + name)
  url?: string; // will be overwritten with tokened URL on publish
  token?: string; // optional, for debugging/visibility
  size?: number;
  contentType?: string;
};

export type CreatePostData = {
  postType: PostType;
  title?: string;
  postText?: string;
  attachments?: TempAttachmentIn[];
  parentIds?: string[]; // response: [enquiryId], comment: [enquiryId, responseId]
  closeEnquiryOnPublish?: boolean; // only for responses
  enquiryConclusion?: EnquiryConclusion; // only for responses when closeEnquiryOnPublish is true
};

type EditAttachmentMap = {
  add: boolean;
  remove: boolean;
  removeList: string[];
};

export type EditPostData = CreatePostData & {
  postId: string;
  isPublished: boolean;
  editAttachments: EditAttachmentMap;
};

export type DeletePostData = {
  postType: PostType;
  postId: string;
  parentIds?: string[];
};

export type AuthorInfo = {
  uid: string;
  team: string; // validated non-empty
};

export type TxResult = {
  postId: string;
  postPath: string;
  postType: CreatePostData["postType"];
  enquiryNumber?: number; // for new enquiries
};

export type TargetTime = {
  hour: number;
  minute: number;
  second?: number;
  millisecond?: number;
};

export type idPayload = {
  enquiryId: string;
};

export type instantPublishPayload = {
  enquiryId: string;
  rcResponse: boolean;
};

export type changeStageLengthPayload = {
  enquiryId: string;
  newStageLength: number;
};

export type UnreadPostPayload = {
  enquiryId: string;
  responseId?: string;
  commentId?: string;
};

/* ─────────────────────────────── Notifications ─────────────────────────────── */

export type ISODate = Timestamp;

export interface BasePublishable {
  isPublished?: boolean;
  title?: string;
  publishedAt?: ISODate;
}

export interface EnquiryDoc extends BasePublishable {
  enquiryNumber?: string;
}
export interface ResponseDoc extends BasePublishable {
  roundNumber?: string;
  responseNumber?: string;
}
export interface CommentDoc extends BasePublishable {
  commentNumber?: string;
}

export type PublishKind = "enquiry" | "response" | "comment";
export type PostType = PublishKind;

export interface PublishEventData {
  kind: PublishKind;
  enquiryId: string;
  responseId?: string;
  commentId?: string;
  enquiryTitle?: string;
  createdAt: ISODate;
  publishedAt: ISODate;
  processed: boolean;
  processedAt?: ISODate;
  enquiryNumber?: string;
  roundNumber?: string;
  responseNumber?: string;
  commentNumber?: string;
}

export interface EnquiryParams {
  enquiryId: string;
}
export interface ResponseParams extends EnquiryParams {
  responseId: string;
}
export interface CommentParams extends ResponseParams {
  commentId: string;
}

export interface UserData {
  emailNotificationsOn?: boolean;
  /** 'all' = all activity; 'enquiries' = only enquiries */
  emailNotificationsScope?: "all" | "enquiries";
  email?: string;
  team?: string;
}

export interface PublishResult {
  success: boolean;
  failReason?: string;
  publishedNumber: number;
}

export type terminateStagePayload = {
  enquiryId: string;
  publishPendingResponses: boolean;
};

export type CloseEnquiryPayload = {
  enquiryId: string;
  enquiryConclusion: EnquiryConclusion;
};

export type EnquiryConclusion = "amendment" | "interpretation" | "noResult";
