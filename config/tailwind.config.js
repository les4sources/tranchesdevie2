module.exports = {
  content: [
    "./app/views/**/*.{erb,html}",
    "./app/helpers/**/*.rb",
    "./app/javascript/**/*.js",
    "./app/assets/javascripts/**/*.js",
    "./app/assets/stylesheets/**/*.css",
    "./app/components/**/*.{erb,rb,js}"
  ],
  theme: {
    extend: {
      colors: {
        primary: "#ACC037",
        "background-light": "#f7f8f6",
        "background-dark": "#1d1f13",
        charcoal: "#36454F",
        ochre: "#CC7722",
        terracotta: "#E2725B",
        "soft-cream": "#F5F5DC"
      },
      fontFamily: {
        display: ["Inter", "sans-serif"]
      },
      borderRadius: {
        DEFAULT: "0.25rem",
        lg: "0.5rem",
        xl: "0.75rem",
        full: "9999px"
      }
    }
  },
  plugins: []
};

