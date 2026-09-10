"use client";

import Script from "next/script";

/*
  esp-web-tools ships a <esp-web-install-button> custom element that drives the
  whole Web Serial flash flow (connect, erase, write, progress). It renders its
  own "browser not supported" message outside Chrome/Edge. Injected as raw HTML
  so we don't need a JSX intrinsic-element declaration for the custom tag.
*/
export function FlashButton() {
  return (
    <>
      <Script
        type="module"
        src="https://unpkg.com/esp-web-tools@10/dist/web/install-button.js?module"
      />
      <div
        dangerouslySetInnerHTML={{
          __html:
            '<esp-web-install-button manifest="/firmware/esp-web-tools-manifest.json"></esp-web-install-button>',
        }}
      />
    </>
  );
}
