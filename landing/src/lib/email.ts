import { WAITLIST_CONFIRMATION_TEMPLATE } from "./email-templates.ts";

type RenderInput = {
  position: number;
  price: number;
  referralUrl: string;
};

type SendInput = RenderInput & {
  to: string;
};

export type SendWaitlistConfirmationResult =
  | { status: "skipped"; reason: string }
  | { status: "sent"; id?: string }
  | { status: "error"; error: string };

const template = WAITLIST_CONFIRMATION_TEMPLATE;

function substitute(value: string, input: RenderInput): string {
  return value
    .replaceAll("{{position}}", String(input.position))
    .replaceAll("{{price}}", String(input.price))
    .replaceAll("{{referralUrl}}", input.referralUrl);
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function renderParagraph(paragraph: string, referralUrl: string): string {
  const escapedUrl = escapeHtml(referralUrl);
  const escaped = escapeHtml(paragraph)
    .replaceAll("\n", "<br>")
    .replaceAll(
      escapedUrl,
      `<a href="${escapedUrl}" style="color:#c9862b;text-decoration:underline;text-decoration-thickness:1px;text-underline-offset:3px;">${escapedUrl}</a>`,
    );
  return `<p style="margin:0 0 18px;">${escaped}</p>`;
}

function renderHtml(text: string, referralUrl: string): string {
  const paragraphs = text
    .trimEnd()
    .split(/\n{2,}/)
    .map((paragraph) => renderParagraph(paragraph, referralUrl))
    .join("");

  return `<!doctype html>
<html>
  <body style="margin:0;background:#F7F2E9;color:#2b2724;font-family:system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;line-height:1.6;">
    <main style="max-width:480px;margin:0 auto;padding:40px 24px;">
      ${paragraphs}
    </main>
  </body>
</html>`;
}

export function renderWaitlistConfirmation(input: RenderInput): {
  subject: string;
  text: string;
  html: string;
} {
  const subject = substitute(template.subject, input);
  const text = substitute(template.body, input);

  return {
    subject,
    text,
    html: renderHtml(text, input.referralUrl),
  };
}

export async function sendWaitlistConfirmation(
  input: SendInput,
): Promise<SendWaitlistConfirmationResult> {
  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey) {
    console.debug("waitlist confirmation email skipped: RESEND_API_KEY is not set");
    return { status: "skipped", reason: "RESEND_API_KEY is not set" };
  }

  try {
    const rendered = renderWaitlistConfirmation(input);
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: template.from,
        reply_to: template.replyTo,
        to: input.to,
        subject: rendered.subject,
        text: rendered.text,
        html: rendered.html,
      }),
    });

    const payload = (await response.json().catch(() => null)) as { id?: string; message?: string } | null;
    if (!response.ok) {
      const message = payload?.message ?? `Resend returned ${response.status}`;
      console.error("waitlist confirmation email failed", message);
      return { status: "error", error: message };
    }

    return { status: "sent", id: payload?.id };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("waitlist confirmation email failed", err);
    return { status: "error", error: message };
  }
}
