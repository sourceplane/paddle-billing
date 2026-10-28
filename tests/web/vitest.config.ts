import { defineConfig } from "vitest/config";
import * as path from "node:path";

// `@/…` is the app's own alias (apps/web/tsconfig.json: `./src/*`), so a test
// imports the app's modules by the paths the app uses. next.config.mjs is the
// one module outside src/.
export default defineConfig({
  resolve: {
    alias: [
      { find: "@/next.config.mjs", replacement: path.resolve(__dirname, "../../apps/web/next.config.mjs") },
      { find: /^@\//, replacement: path.resolve(__dirname, "../../apps/web/src") + "/" },
    ],
  },
  test: {
    include: ["src/**/*.test.ts", "src/**/*.test.tsx"],
    environment: "node",
  },
});
