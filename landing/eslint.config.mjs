import { FlatCompat } from "@eslint/eslintrc";

const compat = new FlatCompat({ baseDirectory: import.meta.dirname });

const config = [
  { ignores: [".next/**", "out/**", "build/**", "next-env.d.ts", "playwright-report/**", "test-results/**"] },
  ...compat.extends("next/core-web-vitals"),
];

export default config;
