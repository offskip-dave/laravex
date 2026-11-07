// Vite config placeholder for Laravex frontend assets (Laravel-faithful).
export default {
  build: {
    outDir: "public/build",
    rollupOptions: {
      input: ["resources/css/app.css", "resources/js/app.js"],
    },
  },
};
