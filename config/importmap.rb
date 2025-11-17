# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "chart.js", to: "https://cdn.jsdelivr.net/npm/chart.js@4.4.6/dist/chart.esm.js"
pin "libphonenumber-js", to: "https://cdn.jsdelivr.net/npm/libphonenumber-js@1.11.0/+esm"
pin "product_images", to: "product_images.js"
