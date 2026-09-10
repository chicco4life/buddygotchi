import type { Metadata } from "next";
import Link from "next/link";
import { copy } from "@/lib/copy";

export const metadata: Metadata = {
  title: "Help — Boop",
  robots: { index: true, follow: true },
};

export default function HelpPage() {
  const help = copy.help;
  return (
    <main className="mx-auto max-w-2xl px-6 py-24 md:py-32">
      <h1 className="text-3xl font-semibold tracking-[-0.02em]">{help.heading}</h1>
      <p className="mt-8 text-lg leading-relaxed text-charcoal-soft">{help.intro}</p>

      <h2 className="mt-14 text-xl font-semibold tracking-[-0.01em]">{help.hooks.heading}</h2>
      <ul className="mt-4 flex list-disc flex-col gap-3 pl-5 text-lg leading-relaxed text-charcoal-soft">
        {help.hooks.items.map((item, i) => (
          <li key={i}>{item}</li>
        ))}
      </ul>

      <h2 className="mt-14 text-xl font-semibold tracking-[-0.01em]">
        {help.troubleshooting.heading}
      </h2>
      <dl className="mt-4 flex flex-col gap-6">
        {help.troubleshooting.rows.map((row) => (
          <div key={row.symptom}>
            <dt className="font-medium">{row.symptom}</dt>
            <dd className="mt-1 leading-relaxed text-charcoal-soft">{row.check}</dd>
          </div>
        ))}
      </dl>

      <h2 className="mt-14 text-xl font-semibold tracking-[-0.01em]">{help.updates.heading}</h2>
      <p className="mt-4 text-lg leading-relaxed text-charcoal-soft">{help.updates.body}</p>

      <h2 className="mt-14 text-xl font-semibold tracking-[-0.01em]">{help.uninstall.heading}</h2>
      <p className="mt-4 text-lg leading-relaxed text-charcoal-soft">{help.uninstall.intro}</p>
      <pre className="mt-3 overflow-x-auto rounded-lg bg-cream-deep px-4 py-3 text-sm">
        <code>{help.uninstall.command}</code>
      </pre>
      <p className="mt-4 text-lg leading-relaxed text-charcoal-soft">{help.uninstall.outro}</p>
      <ul className="mt-3 flex list-disc flex-col gap-2 pl-5 leading-relaxed text-charcoal-soft">
        {help.uninstall.files.map((file) => (
          <li key={file}>
            <code className="text-sm">{file}</code>
          </li>
        ))}
      </ul>

      <p className="mt-14 text-lg leading-relaxed text-charcoal-soft">
        {help.contact}{" "}
        <a
          href={`mailto:${copy.footer.contactEmail}`}
          className="underline underline-offset-4 hover:text-charcoal"
        >
          {copy.footer.contactEmail}
        </a>
        .
      </p>

      <Link
        href="/"
        className="mt-14 inline-block text-sm text-charcoal-soft underline-offset-4 hover:text-charcoal hover:underline"
      >
        {help.backHome}
      </Link>
    </main>
  );
}
