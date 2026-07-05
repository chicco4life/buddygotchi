import { WAITLIST_CONFIRMATION_TEMPLATE } from "./email-templates.ts";

type RenderInput = {
  position: number;
  price: number;
};

type SendInput = RenderInput & {
  to: string;
};

export type SendWaitlistConfirmationResult =
  | { status: "skipped"; reason: string }
  | { status: "sent"; id?: string }
  | { status: "error"; error: string };

const template = WAITLIST_CONFIRMATION_TEMPLATE;

/*
  The HTML version mirrors the landing page's design tokens (globals.css):
  cream #f7f2e9, charcoal #2b2724, charcoal-soft #6e675d, amber #e8a33d /
  amber-deep #c9862b. Zero images and no tracking pixel — deliverability and
  the privacy promise both depend on that staying true.
*/
const SITE_URL = "https://adoptaboop.com";

function substitute(value: string, input: RenderInput): string {
  return value
    .replaceAll("{{position}}", String(input.position))
    .replaceAll("{{price}}", String(input.price));
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function linkifySite(escaped: string): string {
  return escaped.replaceAll(
    "adoptaboop.com",
    `<a href="${SITE_URL}" style="color:#c9862b;text-decoration:underline;text-decoration-thickness:1px;text-underline-offset:3px;">adoptaboop.com</a>`,
  );
}

function renderBodyParagraph(paragraph: string): string {
  const escaped = linkifySite(escapeHtml(paragraph).replaceAll("\n", "<br>"));
  // The sign-off paragraph (starts with "—") becomes the quiet footer.
  if (paragraph.startsWith("—")) {
    return `<p style="margin:36px 0 0;font-size:14px;line-height:1.7;color:#6e675d;">${escaped}</p>`;
  }
  return `<p style="margin:0 0 20px;font-size:16px;line-height:1.7;color:#2b2724;">${escaped}</p>`;
}

function renderHtml(input: RenderInput): string {
  const heading = escapeHtml(substitute(template.heading, input));
  // The buddy number is the one amber moment in the email.
  const subline = escapeHtml(substitute(template.subline, input)).replace(
    `#${input.position}`,
    `<span style="color:#c9862b;font-weight:600;">#${input.position}</span>`,
  );
  const paragraphs = substitute(template.body, input)
    .trimEnd()
    .split(/\n{2,}/)
    .map(renderBodyParagraph)
    .join("");

  return `<!doctype html>
<html>
  <body style="margin:0;padding:0;background:#f7f2e9;">
    <div style="max-width:520px;margin:0 auto;padding:56px 28px 48px;font-family:system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#2b2724;">
      <p style="margin:0 0 32px;font-size:11px;font-weight:600;letter-spacing:0.14em;text-transform:uppercase;color:#6e675d;">Boop Computer &middot; Founding Litter</p>
      <h1 style="margin:0 0 14px;font-size:34px;line-height:1.1;letter-spacing:-0.02em;font-weight:600;color:#2b2724;">${heading}</h1>
      <p style="margin:0 0 28px;font-size:17px;line-height:1.6;color:#6e675d;">${subline}</p>
      <div style="height:3px;width:44px;border-radius:2px;background:#e8a33d;margin:0 0 28px;"></div>
      ${paragraphs}
    </div>
  </body>
</html>`;
}

export function renderWaitlistConfirmation(input: RenderInput): {
  subject: string;
  text: string;
  html: string;
} {
  const subject = substitute(template.subject, input);
  const text = [template.heading, template.subline, template.body.trimEnd()]
    .filter(Boolean)
    .map((part) => substitute(part, input))
    .join("\n\n");

  return {
    subject,
    text,
    html: renderHtml(input),
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
