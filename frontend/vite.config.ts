import { defineConfig } from "vite";

export default defineConfig({
  root: ".",
  build: {
    outDir: "dist",
    emptyOutDir: true,
  },
  server: {
    port: 5173,
    proxy: {
      "/api": "http://localhost:3334",
      "/ws": {
        target: "ws://localhost:3334",
        ws: true,
      },
    },
  },
});
