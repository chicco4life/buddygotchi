"use client";

import { useEffect } from "react";
import { captureAttribution } from "@/lib/attribution";

/** Mounted once in the root layout: captures first-touch attribution. */
export function Attribution() {
  useEffect(() => {
    captureAttribution();
  }, []);
  return null;
}
