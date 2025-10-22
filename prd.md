<context>

# Overview

Tranches de Vie is a multi‑tenant web application for artisan bakeries that bake on fixed days (Tuesday and Friday). It lets customers place pre‑orders, pay online, and receive SMS updates, while bakery teams manage catalog, capacities, orders, and production sheets. It reduces admin overhead, enforces cut‑offs, and prioritizes standing orders so bakers produce the right quantities.

# Core Features

1. Public Catalog

* **What:** Browse products and variants without login; show seasonal/bonus availability per selected bake day.
* **Why:** Frictionless discovery improves conversion.
* **How:** Server‑side filtering by bake day, product availability ranges, and capacity flags.

2. Cart & Checkout (Stripe)

* **What:** Select target bake day (Tue/Fri), pay via Card, Bancontact, Apple Pay, Google Pay.
* **Why:** Secure, fast payments with strong local methods.
* **How:** Stripe Payment Element with immediate capture; order created on `payment_intent.succeeded`.

3. Standing Orders with D‑4 Confirmation

* **What:** Recurring orders on Tue/Fri/Both; J‑4 SMS at 10:30 to confirm; keywords **PAUSE** (skip date) and **STOP** (suspend).
* **Why:** Drives retention and predictable production.
* **How:** Scheduler sends SMS via Telerivet; inbound webhook records pauses/suspensions; standing orders get priority allocation.

4. Admin Console (per tenant)

* **What:** Orders, capacities, production sheets (by variant and ingredient), dashboards, CGV/refund CMS.
* **Why:** Centralizes operations; reduces manual spreadsheets.
* **How:** Rails admin with tenant‑scoped data; BOM aggregation for production.

5. Multi‑Tenant Bakery Support

* **What:** Isolated bakery spaces under one platform.
* **Why:** Scale to multiple teams without data leakage.
* **How:** Per‑tenant Postgres schemas using `ros-apartment`; subdomain routing.

6. SMS Notifications (Telerivet)

* **What:** Confirmation, D‑4 recap, and “ready for pickup” messages.
* **Why:** Clear, timely communication.
* **How:** Outbound API and inbound webhook for keyword parsing.

# User Experience

* **Personas:**

  * Customer: wants quick ordering, trusted payments, SMS status.
  * Baker/Admin: wants capacity controls, accurate production, refunds, and no‑show marking.
  * Platform Owner: provisions tenants, minimal global controls.
* **Key Flows:**

  1. One‑off order → select bake day → pay → confirmation SMS → ready SMS → pickup 24/7.
  2. Standing order setup → D‑4 reminder → PAUSE/STOP if needed.
  3. Admin planning → set caps → auto lock at cut‑off → production sheet → mark ready/picked_up/no_show → dashboards.
  4. Tenant onboarding → choose subdomain → configure catalog/payments/SMS branding.
* **UI/UX Considerations:**

  * Bake‑day selector upfront; disable past cut‑off.
  * Variant weights clear (e.g., 600 g / 1 kg).
  * Capacity reached → disable with explanation.
  * Admin in French; client FR/NL/EN via POEditor.
  * Phone input E.164 validation; SMS OTP login with accessible error states.

</context>

<PRD>

# Technical Architecture

* **System Components:**

  * Client web (Hotwire/Turbo + Tailwind)
  * Admin console (Rails views)
  * Background workers (ActiveJob) for J‑4 SMS, cut‑off locks, ready notifications
  * Stripe integration (Payment Element, webhooks)
  * Telerivet integration (outbound API, inbound webhook)
  * Multi‑tenant isolation (Postgres schemas via `ros-apartment`)
* **Data Models (tenant‑scoped):** customers, phone_verifications, products, product_variants, product_availabilities, ingredients, product_ingredients, bake_days, production_caps, orders, order_items, payments, standing_orders, standing_order_items, standing_order_skips, sms_messages, admin_pages. Global: tenants, platform_users (optional).
* **APIs & Integrations:**

  * Stripe: `payment_intent.succeeded`, `payment_intent.payment_failed`, `charge.refunded`.
  * Telerivet: outbound send; inbound `/webhooks/telerivet` with case‑insensitive `PAUSE`/`STOP`.
* **Infrastructure:** VPS via Hatchbox; Postgres 17; Rails 8.1; Hotwire/Turbo; Tailwind; ActiveStorage; ActiveJob; SSL via Cloudflare; backups via Linode Backup; Sentry for errors; Europe/Brussels TZ.

# Development Roadmap

* **MVP (Foundations + Ordering):**

  * Tenant provisioning (subdomain, schema seed)
  * Public catalog with bake‑day filter and seasonal availability
  * Cut‑offs (Sun 18:00 for Tue; Wed 18:00 for Fri) and bake‑day disabling
  * Checkout with Stripe (Card, Bancontact, Apple Pay, Google Pay), immediate capture
  * Confirmation SMS; ready SMS; admin orders list; mark ready/picked_up/no_show
  * CGV/refund CMS pages; client FR/NL/EN; admin FR
* **Production & Capacities:**

  * Per‑variant capacities per bake day; disable at capacity
  * Production sheets: by product/variant and aggregated ingredients (BOM)
* **Standing Orders:**

  * Create/manage Tue/Fri/Both; priority allocation
  * D‑4 10:30 SMS recap; inbound PAUSE/STOP; per‑date skips
* **Dashboards & Multi‑tenant polish:**

  * Sales by bake day/product; revenue by range; average order value; recurring revenue forecast; no‑show rate
  * Tenant self‑service signup (optional approval), branding prefix in SMS
* **Future Enhancements (Phase 2):**

  * Stripe Connect per tenant; per‑tenant Telerivet credentials
  * Advanced access control; richer reports; waitlists; low‑stock alerts

# Logical Dependency Chain

1. **Platform & Tenant Foundation:** tenancy, routing, auth, settings.
2. **Catalog & Bake Logic:** products, variants, availability, bake days, cut‑offs.
3. **Payments:** Stripe integration and webhooks; order lifecycle.
4. **Notifications:** SMS outbound/inbound; templates; ready events.
5. **Admin Ops:** orders board, capacities, production sheets, CMS pages.
6. **Standing Orders:** scheduling, priority allocation, D‑4 reminders.
7. **Dashboards:** KPIs and forecasting.
8. **Multi‑tenant Enhancements:** self‑service, branding, optional Connect.

# Risks and Mitigations

* **Capacity race conditions:** use DB row‑level locks on availability checks; re‑quote cart on conflict.
* **Shared Stripe/Telerivet in Phase 1:** reconciliation and branding risks → descriptor suffix and SMS prefix; plan migration to Connect/per‑tenant credentials.
* **No rate limiting requirement:** OTP abuse risk → enforce OTP attempt caps and short code expiry.
* **MVP creep:** lock scope per milestone; defer Connect and advanced reporting to Phase 2.
* **Time‑zone errors:** centralize TZ handling to Europe/Brussels and test cut‑off boundaries.

# Appendix

* **Business Rules:** Tue/Fri only; per‑date OFF; cut‑offs (Tue ← Sun 18:00, Fri ← Wed 18:00); pickup 24/7; full refund until cut‑off; no VAT/discounts/promos/fees; standing orders prioritized; SMS at 10:30.
* **Environment Variables:** `STRIPE_PUBLIC_KEY, STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, TELERIVET_API_KEY, TELERIVET_PROJECT_ID, TELERIVET_PHONE_ID, SENTRY_DSN, ACTIVE_STORAGE_SERVICE, TIME_ZONE=Europe/Brussels`.
* **SMS Templates (EN; FR/NL via POEditor):**

  * D‑4 reminder: "{tenant} — Reminder: your recurring order for {bake_date}: {items}. Reply PAUSE to skip. Reply STOP to suspend."
  * Order confirmation: "{tenant} — Thank you {first_name}. Order {order_number} received for {bake_date}. Pickup 24/7 at {pickup}. We'll text when ready."
  * Ready: "{tenant} — Order {order_number} is ready. Pickup 24/7 at {pickup}."
* **Indexing Notes:** unique(customers.phone_e164); FKs; composites on orders(bake_day_id,status) and production_caps(baked_on,product_variant_id).

</PRD>

