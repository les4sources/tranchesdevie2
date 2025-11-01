# Tranches de Vie

ID: SG-14
Statut: En cours

<context>

# Overview

Tranches de Vie is a single-tenant web application for one artisan bakery that bakes on fixed days (Tuesday and Friday). It lets customers place pre-orders, pay online, and receive SMS updates, while the bakery team manages catalog, orders, and production sheets. It reduces admin overhead, enforces cut-offs, and prioritizes standing orders so bakers produce the right quantities.

# Core Features (MVP)

1. Public Catalog
- **What:** Browse products and variants without login; show seasonal/bonus availability per selected bake day.
- **Why:** Frictionless discovery improves conversion.
- **How:** Server-side filtering by bake day and product availability ranges.
1. Cart & Checkout (Stripe)
- **What:** Select target bake day (Tue/Fri), pay via Card, Bancontact, Apple Pay, Google Pay.
- **Why:** Secure, fast payments with strong local methods.
- **How:** Stripe Payment Element with immediate capture; order created on `payment_intent.succeeded`.
1. SMS Notifications
- **What:** Confirmation on payment success and "ready for pickup" messages.
- **Why:** Clear, timely communication.
- **How:** Outbound API and inbound webhook for keyword parsing (no D-4 loop in MVP).
1. Admin Console (minimal)
- **What:** Orders list, status changes (ready / picked_up / no_show).
- **Why:** Operate daily flow with minimal surface.
- **How:** Rails admin with app-scoped data.

</context>

<PRD>

# 0. Environments and Deployment

- Environments: local development and production only. No staging.
- Deployment: Hatchbox. No special preparation required here.
- Versions: latest stable Ruby, Rails, Node (for asset build), PostgreSQL 17, recent Redis.
- Environment variables: all keys and secrets supplied via ENV.
- Migrations: no zero‑downtime requirement.
- Jobs/queues: ActiveJob + Sidekiq (Redis).
- Seeds: create a few demo products/variants with images.
- Seed (detailed list):
    - Category: Breads
        - Spelt bread
            - 1 kg — 550 cents — price per unit
            - 600 g — 350 cents — price per unit
        - Wheat bread
            - 1 kg — 450 cents — price per unit
            - 600 g — 300 cents — price per unit
        - Ancient grains bread
            - 600 g — 550 cents — price per unit
        - Walnut bread
            - 1 kg — 550 cents — price per unit
            - 600 g — 400 cents — price per unit
        - Seeded bread
            - 1 kg — 550 cents — price per unit
            - 600 g — 400 cents — price per unit
        - Walnut/fig bread
            - 600 g — 400 cents — price per unit
        - Choco/sugar bread
            - 600 g — 400 cents — price per unit
    - Category: Dough balls
        - Take‑away pizza dough ball — 200 cents — price per unit
        - Private Pizza Party dough ball — 500 cents — price per unit

# 1. Information Architecture Summary (MVP)

- Primary objects: Product, ProductVariant, Availability, BakeDay, Customer, Order, OrderItem, Payment, SMSMessage, AdminPage.
- Roles: Customer, Admin (single session protected by password, no multi‑user system).
- Journeys: Browse → Choose bake day → Cart → Pay → Confirmation SMS → Ready SMS → Pickup.
- Naming: snake_case tables/columns. Phone E.164. Dates in Europe/Brussels. Prices in EUR cents.
- Public URLs: `/`, `/catalog?bake_day=YYYY-MM-DD`, `/cart`, `/checkout`, `/orders/:token` (non‑expiring link).
- Admin URLs: `/admin/orders`, `/admin/products`.

# 2. Goals and Non‑Goals

- Goals (MVP):
    1. Order for Tue/Fri with cut‑offs.
    2. Stripe payments with immediate capture (Card, Bancontact, Apple Pay, Google Pay).
    3. Confirmation and “ready” SMS.
    4. Admin updates order statuses.
- Phase 2 (out of MVP):
    - Standing orders (cadence, D‑4, PAUSE/STOP)
    - Production sheets and BOM
    - Dashboards/KPIs
    - CMS for T&Cs/refund
    - NL/EN languages
    - Brand profiles, advanced access, waitlists, low‑stock alerts

# 3. Domain Model (conceptual)

- Product 1—n ProductVariant
- Order 1—n OrderItem; Order belongs to a BakeDay
- Payment 1—1 Order (Stripe)
- Customer 1—n Orders

# 4. Data Model (schema)

- products(id, name, description, active)
    - Categories and sorting: `category` enum[breads, dough_balls], `position` int for order within category (lower first). Default ordering: category (breads first) → position → name.
- product_variants(id, product_id FK, name, price_cents, active, image_url)
    - MVP convention: each weight is a separate fixed‑price variant (e.g., “Country 600 g”, “Country 1 kg”). No per‑kg dynamic pricing.
- product_availabilities(id, product_variant_id FK, start_on date, end_on date nullable)
- bake_days(id, baked_on date unique, cut_off_at timestamptz)
- customers(id, phone_e164 unique, first_name, last_name nullable, email nullable)
- phone_verifications(id, phone_e164, code, expires_at)
- orders(id, customer_id FK, bake_day_id FK, status enum[pending,paid,ready,picked_up,no_show,cancelled], total_cents, public_token unique)
- order_items(id, order_id FK, product_variant_id FK, qty int, unit_price_cents)
- payments(id, order_id FK unique, stripe_payment_intent_id unique, status enum[succeeded,failed,refunded])
- sms_messages(id, direction enum[outbound,inbound], to_e164, from_e164, baked_on nullable, body, kind enum[confirmation,ready,refund,other], external_id)
- admin_pages(id, slug unique, title, body)

# 5. Functional Rules (MVP)

## 5.1 Identifiers and Conventions

- Human order number: `TV-YYYYMMDD-XXXX` where `XXXX` is a zero‑padded daily counter. Example: `TV-20251101-0007`.
- Public order token (`orders.public_token`): 24‑char Base58 url‑safe, cryptographically secure, non‑guessable, non‑expiring. Example shape: `6YqZQhP1r9aBd8KfX2NuSeDw`.
- Idempotency: use `payment_[intent.id](http://intent.id)` as the app idempotency key for Order creation.
- OTP: 6‑digit code, TTL 5 minutes, max 5 attempts, 60 s cooldown between attempts.
- Currency: EUR, prices in integer cents (2 decimals), VAT 0%.
- Cut‑offs: Tue ← Sun 18:00, Fri ← Wed 18:00 (Europe/Brussels). UI disables, server validates.
- Public order link: `orders.public_token` non‑expiring.
- Payment flow: Stripe Payment Element; create Order on `payment_intent.succeeded`.
- Receipts: no app‑side customer receipts (Stripe receipts disabled from app perspective).
- SMS: Confirmation after payment. “Ready” when moving to `ready`.
    - “Ready” message: "Bonjour, votre commande est cuite, elle est disponible aux 4 Sources ! Les artisans de Tranche de Vie".
    - Global STOP: implemented. If STOP received, mark customer opt‑out and do not send further SMS until manual admin re‑opt‑in.
- Client auth: minimal SMS OTP (short TTL, attempt limits, simple error messages).
- Admin: access protected by a session password (no user management).
- Language: French only (phase 1).

# 6. Status Transitions (allowed)

- `pending` → `paid` (successful Stripe webhook)
- `paid` → `ready` (admin action) → sends “ready” SMS
- `ready` → `picked_up` (admin action)
- `ready` → `no_show` (admin action)
- `paid` → `cancelled` (full refund before cut‑off) → sends “refund” SMS
- Forbidden: reverse transitions except manual admin correction via console (out of UI flow)

# 7. Refund (before cut‑off)

- Trigger: by admin from the order view.
- Effects:
    - Immediate full Stripe refund.
    - Update Payment.status=refunded, Order.status=cancelled.
    - Send refund SMS: "Votre commande a été remboursée intégralement car annulée avant l'heure limite."

# 8. Interfaces and APIs (MVP)

- Stripe webhooks: `payment_intent.succeeded`, `payment_intent.payment_failed`, `charge.refunded`.
- Telerivet: Android app with Belgian number. Outbound via API. Inbound `/webhooks/telerivet` for global STOP.
- Public read: `GET /orders/:token`.

# 9. UI Library (MVP)

- Framework: Tailwind CSS + Hotwire/Turbo.
- UI library: Tailwind UI (Starter).
- Components: simple navbar, footer, product grid, product cards, Cart page (no drawer), checkout form, alerts, toasts, spinners, admin table + badges + confirmation modal.
- Branding: default palette (to define), no enforced brand guide.
- A11y: Tailwind UI focus/ARIA patterns.

# 10. Journeys and Acceptance Criteria (MVP)

## 10.1 One‑off order

- Filter by bake day. Add to cart. Stripe payment.
- AC:
    - Successful payment → Order.status=paid, confirmation SMS < 30s.
    - `payment_failed` → clear UI error, retry possible.

## 10.2 Admin

- Orders list, allowed status changes.
- AC:
    - `paid`→`ready` sends the ready SMS with the defined text.
    - Refund before cut‑off sets Order.status=cancelled and sends refund SMS.

# 11. Non‑Functional

- Timezone: centralized Europe/Brussels with boundary tests.
- Security: signed webhooks, CSRF on non‑GET, rate‑limit OTP and checkout init.
- Observability: Sentry, structured logs (mask phone PII).
- Performance: catalog TTFB < 300 ms for ~100 variants.

# 12. Tests

- Cut‑off edges 17:59 vs 18:01.
- `payment_failed` then success.
- STOP inbound prevents future sends.
- Refund before cut‑off updates states + SMS.

# 13. Glossary

- Bake day: target baking date. Cut‑off: last order time. Public token: non‑expiring public read identifier.

# 14. Configuration

- Required ENV: `STRIPE_PUBLIC_KEY, STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, TELERIVET_API_KEY, TELERIVET_PROJECT_ID, TELERIVET_PHONE_ID, SENTRY_DSN, ACTIVE_STORAGE_SERVICE, TIME_ZONE=Europe/Brussels, ADMIN_PASSWORD`.

</PRD>