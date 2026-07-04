// ──────────────────────────────────────────────────────────────────────────────
// File: src/utils/email_batch.ts
// Purpose: Send BCC emails in chunks to stay under Gmail's per-message
//          recipient limit (~100 for consumer accounts).
// ──────────────────────────────────────────────────────────────────────────────
import type { Transporter } from "nodemailer";

const DEFAULT_CHUNK_SIZE = 90;

/**
 * Send one email per chunk of BCC recipients.
 * Throws on the first failed chunk (earlier chunks will already have been sent).
 */
export async function sendBccInChunks(
  transporter: Transporter,
  message: {
    from: string;
    to: string;
    bcc: string[];
    subject: string;
    html: string;
  },
  chunkSize: number = DEFAULT_CHUNK_SIZE,
): Promise<void> {
  const { bcc, ...rest } = message;
  for (let i = 0; i < bcc.length; i += chunkSize) {
    const chunk = bcc.slice(i, i + chunkSize);
    await transporter.sendMail({ ...rest, bcc: chunk.join(", ") });
  }
}
