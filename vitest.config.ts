import { defineConfig } from "vitest/config"
import { fileURLToPath } from "node:url"

export default defineConfig({
  test: {
    environment: "jsdom",
    include: ["app/frontend/**/*.test.{ts,tsx}"],
    globals: false,
  },
  resolve: {
    alias: {
      "~": fileURLToPath(new URL("./app/frontend", import.meta.url)),
    },
  },
})
