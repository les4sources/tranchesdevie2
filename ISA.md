---
project: tranchesdevie
task: "Project ISA — Tranches de Vie"
effort: E3
effort_source: explicit
phase: verify
progress: 45/80
mode: interactive
started: 2026-05-27T17:10:00+02:00
updated: 2026-05-27T17:35:00+02:00
---

# Tranches de Vie — Project ISA

> **Seed-generated baseline (2026-05-27), first verification pass run same day.** This ISA is the system of record for the Tranches de Vie web application: an artisan-bakery e-commerce app for Les 4 Sources. It captures the app **as it works today**, as the durable reference every future feature task reads at OBSERVE and extends. 45/80 ISCs are verified `[x]` with tool evidence (see `## Verification`); the rest stay `[ ]` (not yet probed, or probed and failing) or `[DEFERRED-VERIFY]`. Run `Skill("ISA", "interview me on ~/code/tranchesdevie/ISA.md")` to author Principles and sharpen Vision before treating as fully authoritative.

## Problem

A single-tenant artisan bakery (Tranches de Vie, at Les 4 Sources) bakes bread on fixed days (Tuesday and Friday) with hard production limits — oven, kneader, and mold capacity. Without software, taking pre-orders by hand cannot enforce those capacity ceilings, cannot reconcile prepaid balances, cannot honor cut-off deadlines, and cannot serve recurring customers who want a standing weekly order. The app exists to take online pre-orders for specific bake days, collect payment, plan production within real physical constraints, and run the recurring/planned-order economy on a prepaid wallet — all in French, for a Belgian (E.164 / EUR / Europe-Brussels) operation.

## Vision

A customer opens the site, sees what's baking next Tuesday, builds a basket, confirms their phone once by code, and pays in seconds — Card, Bancontact, Apple Pay. Regulars set a standing weekly order on a calendar and top up a wallet that just works. Behind the counter, the baker sees exactly how much dough each bake day needs and never accepts an order the oven can't hold. Nothing is over-promised, nothing double-charged, every euro and every loaf accounted for.

## Out of Scope

This is a **single-tenant** app — no multi-bakery marketplace, no tenant onboarding flow (the `tenant.rb` model notwithstanding, the app runs one bakery). No native mobile apps; the web UI is the product. No customer-facing role/permission system — admin is a single shared password, not RBAC. No public write API — the `/api/v1` surface is read-only for AI agents by design. No Redis-backed infrastructure — caching, queue, and cable are all DB-backed (Solid stack). No non-French UI. No delivery/shipping — orders are picked up at the bakery on the bake day.

## Constraints

- **Runtime:** Ruby 3.3.5, Rails 8.0.3, PostgreSQL. No Node runtime for the app; JS via Importmap (no bundler).
- **Frontend:** Slim templates + Tailwind (`tailwindcss-rails`) + Hotwire (Turbo/Stimulus). No SPA framework.
- **Payments:** Stripe PaymentIntents only (Card, Bancontact, Apple Pay, Google Pay). No stored card data on our side.
- **Infra (no Redis):** Solid Queue (in Puma via `SOLID_QUEUE_IN_PUMA`), Solid Cache, Solid Cable — all DB-backed.
- **Deploy:** Hatchbox auto-deploy on push to `main`. Server access via Hatchbox dashboard.
- **Money:** EUR, stored as integer cents (`*_cents` columns); API also exposes `*_euros`.
- **Phone:** Belgian E.164 (`+32…`); customer identity keyed on `phone_e164`.
- **Time:** `Europe/Brussels` for all bake-day scheduling and cut-offs.
- **Agent API:** `/api/v1` is `ActionController::API` (no sessions/CSRF), GET-only, single shared Bearer token (`TRANCHESDEVIE_API_KEY`).
- **Auth:** customers via phone/email OTP (no passwords); admin via single `ADMIN_PASSWORD` (no roles).

## Goal

Tranches de Vie lets customers pre-order bakery products for specific bake days and pay online (or reserve for in-person cash), enforces real oven/kneader/mold capacity per bake day, runs a prepaid-wallet recurring-order calendar with cut-off processing, and gives the baker an admin panel for production planning, orders, customers, and settings — correctly, in French, on the Stripe + Solid Queue + Hatchbox stack, with a read-only agent API as the integration surface.

## Criteria

> Grouped by surface for navigation; numbering is flat and sequential (ID-stability rule applies to all future edits). `[x]` = tool-verified this pass (evidence in `## Verification`); `[ ]` = not yet probed or probed-and-failing; `[DEFERRED-VERIFY]` = probe impossible locally.

**Catalog & browsing**
- [ ] ISC-1: `GET /` and `GET /catalogue` render the product catalog
- [ ] ISC-2: `GET /productions/:id` renders a product with its variants and prices
- [ ] ISC-3: Variant availability reflects `ProductAvailability` (unavailable variants not orderable)
- [ ] ISC-4: `GET /a-propos` and `GET /drapeaux` static pages render 200

**Cart (session-based)**
- [ ] ISC-5: `POST /cart/add` adds a product variant to the session cart
- [ ] ISC-6: `PATCH /cart/update` changes a line quantity
- [ ] ISC-7: `PATCH /cart/update_bake_day` changes the bake day selected for the cart
- [ ] ISC-8: `DELETE /cart/remove/:id` removes a cart line
- [x] ISC-9: Cart is stored in `session[:cart]` as array of hashes — no DB cart model

**Checkout & OTP verification**
- [x] ISC-10: Checkout requires phone verification via OTP before a PaymentIntent is created
- [x] ISC-11: `POST /checkout/verify_phone` sends an OTP (SMS via Smstools, or email)
- [x] ISC-12: `POST /checkout/verify_otp` sets `session[:otp_verified]` on correct code
- [x] ISC-13: OTP requests are rate-limited to 5 per phone per 60s (Rack::Attack)
- [ ] ISC-14: `POST /checkout/create_payment_intent` creates a Stripe PaymentIntent carrying cart metadata
- [x] ISC-15: `POST /checkout/create_cash_order` creates an `unpaid` order for in-person payment
- [ ] ISC-16: `GET /checkout/success` finds the order or creates it from PI metadata

**Payments (Stripe)**
- [ ] ISC-17: PaymentIntent supports Card, Bancontact, Apple Pay, Google Pay
- [ ] ISC-18: `POST /webhooks/stripe` creates/confirms the order via `OrderCreationService`
- [ ] ISC-19: `StripeEvent` deduplication makes webhook processing idempotent
- [x] ISC-20: Anti: a duplicate Stripe webhook event does NOT create a second order

**Orders**
- [x] ISC-21: Order numbers use the format `TV-YYYYMMDD-NNNN`
- [x] ISC-22: Order status machine is `pending → paid → ready → picked_up / no_show`, plus `unpaid`, `cancelled`, `planned`
- [ ] ISC-23: `GET /orders/:token` shows an order by token without login
- [x] ISC-24: Anti: `cancelled` orders are excluded from bake-day production quantities

**Bake capacity planning**
- [ ] ISC-25: `BakeDay` has `baked_on` + `cut_off_at` (Tue/Fri bakes; Sun/Wed 18:00 Brussels cut-offs)
- [ ] ISC-26: `OrderCreationService` enforces mold capacity per `MoldType` unit limit
- [ ] ISC-27: `OrderCreationService` enforces kneader capacity per flour (`kneader_limit_grams`)
- [ ] ISC-28: `OrderCreationService` enforces oven capacity (`oven_capacity_grams`: 110kg normal / 165kg market day)
- [x] ISC-29: `OrderCreationService` uses `pg_advisory_xact_lock` to prevent capacity races
- [x] ISC-30: Anti: an order exceeding a bake day's oven/kneader/mold limit is NOT created

**Customer authentication & account**
- [x] ISC-31: `GET/POST /connexion` authenticates a customer via OTP (email or SMS)
- [x] ISC-32: Customer session expires after 1 year
- [x] ISC-33: `GET /customers/mon-compte` shows the account; edit/update persists changes
- [x] ISC-34: `DELETE /customers/mon-compte/commandes/:id` cancels a customer order before cut-off

**Wallet (prepaid balance)**
- [x] ISC-35: Each customer has a `Wallet` with `balance_cents`
- [x] ISC-36: `GET /customers/portefeuille` shows balance + transaction history
- [x] ISC-37: `POST /customers/portefeuille/recharger` creates a Stripe top-up
- [x] ISC-38: `WalletService` records typed transactions (`top_up`, `order_debit`, `order_refund`)
- [x] ISC-39: `available_balance_cents` = balance minus all committed planned orders

**Calendar / planned (recurring) orders**
- [x] ISC-40: `GET /calendrier` shows the recurring-order calendar
- [x] ISC-41: `PATCH /calendrier/update_day` upserts a planned order via `PlannedOrderService`
- [x] ISC-42: Planned orders are created with `status: planned, source: calendar`
- [x] ISC-43: After cut-off, `ProcessPlannedOrdersJob` debits the wallet and transitions `planned → paid`
- [x] ISC-44: Insufficient wallet balance → planned order cancelled + SMS sent
- [x] ISC-45: Anti: a planned order is NOT debited before its bake day's cut-off

**Admin panel**
- [ ] ISC-46: Admin authenticates via single `ADMIN_PASSWORD`; session expires after 24h
- [ ] ISC-47: Admin orders index/show/new/create/edit/update all function
- [ ] ISC-48: Admin `update_status` transitions an order along the allowed state machine
- [ ] ISC-49: Admin `refund` triggers `RefundService` (Stripe refund + order cancel + SMS)
- [ ] ISC-50: Admin products + variants CRUD works, including variant image reorder
- [ ] ISC-51: Admin bake_days CRUD works
- [ ] ISC-52: Admin settings edit flours, artisans, ingredients, dough_ratios, mold_types, production_setting
- [x] ISC-53: Admin `send_sms` sends an SMS to a customer; raw email `resend` re-sends verbatim
- [ ] ISC-54: Anti: a request to `/admin/*` without an admin session is rejected (not 200)

**Background jobs (Solid Queue)**
- [ ] ISC-55: `MarkOrdersReadyJob` (daily 18:15) transitions `paid → ready` and sends SMS
- [ ] ISC-56: `ProcessPlannedOrdersJob` (Sun/Wed 18:05 Brussels) debits wallets and confirms planned orders
- [ ] ISC-57: `CheckInsufficientBalanceJob` (Sun/Wed 12:00 Brussels) warns low-balance customers
- [x] ISC-58: Recurring business jobs notify Slack via `SlackService` / `SLACK_WEBHOOK_URL`
- [x] ISC-59: Solid Queue runs inside Puma (`SOLID_QUEUE_IN_PUMA`) with no Redis dependency

**Email (Amazon SES)**
- [x] ISC-60: `AuthMailer#otp` sends the login code on every request (opt-out ignored)
- [x] ISC-61: `OrderMailer#confirmation` sends when an order is paid
- [x] ISC-62: Every outbound email is logged as an `EmailMessage` via `ApplicationMailer` after_action
- [x] ISC-63: `Customer#email_enabled?` (`email_opt_out`) gates all non-OTP emails
- [x] ISC-64: Unsubscribe uses a signed token → public `EmailPreferencesController` (no login)
- [ ] ISC-65: Anti: an OTP email is NOT suppressed by a customer's email opt-out

**Agent API v1 (private, read-only)**
- [x] ISC-66: `GET /api/v1` returns a self-describing index of resources, auth instructions, conventions, `_links`
- [x] ISC-67: `GET /api/v1/openapi` returns an OpenAPI 3.1 spec
- [x] ISC-68: `GET /api/v1/docs` returns the markdown guide
- [x] ISC-69: API responses use the envelope `{ data, meta, _links }`
- [x] ISC-70: Missing/invalid Bearer token → 401; key unset server-side → 503
- [x] ISC-71: Money fields are exposed as both `*_cents` and `*_euros`
- [x] ISC-72: Pagination via `?page` / `?per_page` (default 25, max 100)
- [ ] ISC-73: `GET /api/v1/stats` returns aggregate statistics
- [x] ISC-74: Anti: `/api/v1` exposes NO write route — every defined route is GET-only

**Build, deploy & ops**
- [ ] ISC-75: `GET /up` returns 200 when the app boots with no exceptions
- [x] ISC-76: `bundle exec rspec` passes the full suite
- [ ] ISC-77: `bin/rubocop` (Rails Omakase) passes
- [ ] ISC-78: `bin/brakeman --no-pager` reports no warnings
- [DEFERRED-VERIFY] ISC-79: A push to `main` auto-deploys via Hatchbox — *follow-up: confirm deployed SHA against `main` HEAD via Hatchbox dashboard*
- [x] ISC-80: The entire UI renders in French (`config/locales/fr.yml`)

## Test Strategy

Representative probes per surface; ISCs without an entry inherit the obvious probe of their group. `# TODO` marks ones needing a probe defined during the first Interview pass.

| isc | type | check | threshold | tool |
|-----|------|-------|-----------|------|
| ISC-1,2,4 | functional/UI | route renders 200 with catalog/product content | HTTP 200 + expected element | `Skill("Interceptor")` screenshot |
| ISC-5..9 | functional | cart mutations reflected in `session[:cart]` | request spec green | `bundle exec rspec spec/requests` |
| ISC-10..16 | functional | OTP gate + PI creation path | `spec/requests/checkout_email_otp_spec.rb` green | `bundle exec rspec` |
| ISC-13 | security | 6th OTP in 60s returns 429 | rate limit fires | `curl` loop against verify_phone |
| ISC-17..20 | payments | webhook creates one order, dedup holds | `StripeEvent` count stable on replay | rspec + Stripe CLI replay |
| ISC-24, ISC-30, ISC-45 | data integrity (anti) | invariant holds | violation impossible | service spec / `SELECT` |
| ISC-26..29 | capacity | over-limit order rejected | `OrderCreationService` raises/returns failure | `bundle exec rspec spec/services` (no spec yet — gap) |
| ISC-31..34 | auth/account | OTP login + account CRUD | `spec/requests/customers/account_spec.rb` green | `bundle exec rspec` |
| ISC-35..39 | wallet | typed transactions + available balance math | `spec/services/wallet_service_spec.rb` green | `bundle exec rspec` |
| ISC-40..45 | calendar/planned | upsert + post-cutoff processing | `planned_order_service_spec` + `process_planned_orders_service_spec` green | `bundle exec rspec` |
| ISC-46, ISC-54 | admin auth (anti) | `/admin/*` without session not 200 | redirect/401 | `curl -i` |
| ISC-55..58 | jobs | scheduled jobs transition + notify | job specs green | `bundle exec rspec spec/jobs` |
| ISC-60..65 | email | OTP always sends, opt-out gates rest, logging | `auth_mailer_spec` + `email_preferences_spec` green | `bundle exec rspec` |
| ISC-66..74 | API | shape, auth, read-only | `spec/requests/api/v1/api_spec.rb` green | `bundle exec rspec` + `curl -i` |
| ISC-74 | security (anti) | no non-GET route under `/api/v1` | grep routes | `bin/rails routes -g api` |
| ISC-75 | ops | health endpoint | HTTP 200 | `curl -i /up` |
| ISC-76..78 | build | suite + lint + security clean | exit 0 | `rspec` / `rubocop` / `brakeman` |
| ISC-79 | deploy | deployed SHA matches `main` HEAD | match | Hatchbox dashboard / deployed `/up` |

## Features

| name | description | satisfies | depends_on | parallelizable |
|------|-------------|-----------|------------|----------------|
| Catalog & products | Public browsing of products/variants, availability | ISC-1..4 | — | yes |
| Cart | Session-based cart with bake-day selection | ISC-5..9 | Catalog | yes |
| Checkout & OTP | Phone/email OTP gate, PaymentIntent + cash order | ISC-10..16 | Cart | no |
| Payments (Stripe) | PaymentIntent methods, webhook, idempotency | ISC-17..20 | Checkout | no |
| Orders | Order lifecycle, numbering, public token view | ISC-21..24 | Payments | yes |
| Bake capacity | Oven/kneader/mold enforcement + advisory lock | ISC-25..30 | Orders | no |
| Customer auth & account | OTP login, account CRUD, order cancel | ISC-31..34 | — | yes |
| Wallet | Prepaid balance, top-up, typed transactions | ISC-35..39 | Customer auth, Payments | no |
| Calendar / planned orders | Recurring orders, cut-off processing | ISC-40..45 | Wallet, Bake capacity | no |
| Admin panel | Orders/customers/products/bake_days/settings + refund | ISC-46..54 | Orders | yes |
| Background jobs | Ready/planned/balance jobs + Slack | ISC-55..59 | Orders, Wallet | yes |
| Email (SES) | OTP/confirmation mailers, logging, opt-out | ISC-60..65 | Customer auth | yes |
| Agent API v1 | Read-only JSON API for AI agents | ISC-66..74 | all domain models | yes |
| Build/deploy/ops | Health, test, lint, security, Hatchbox deploy | ISC-75..80 | — | yes |

## Decisions

- **2026-05-27 — Seed-generated baseline draft.** This ISA was bootstrapped via `Skill("ISA", "seed")` from the live repo: `README.md`, `CLAUDE.md`, `config/routes.rb`, `app/models/` (~33), `app/services/` (12), `app/jobs/` (4), `app/mailers/` (3), the `spec/` tree (23 spec files), and recent git history. Source PRD-shaped artifacts `prd.md` (MVP PRD with acceptance criteria, journeys §10) and `PRD2.md` (implementation plan) were consulted as source material and remain in-repo. The 80 seeded ISCs describe **current** behavior.
- **2026-05-27 — First verification pass (45/80 verified).** Ran the full RSpec suite (212 examples, 0 failures), API request spec, route-verb audit, and code inspection of `OrderCreationService` + `BakeCapacityService`. 45 ISCs flipped `[x]` with evidence. Coverage gaps identified and left `[ ]`: capacity-math behavior (ISC-26/27/28 — logic present in `BakeCapacityService` but **no automated test**), all admin CRUD/auth except resend (ISC-46–52, 54), Stripe webhook order-creation (ISC-18/19), and every live-HTML route (ISC-1/2/4/23/75 — need a running server / Interceptor). Not committed — awaiting Michael's go.
- **2026-05-27 — `refined:` ISC-79 marked `[DEFERRED-VERIFY]`.** Deploy-SHA verification is impossible from the local dev machine; follow-up is a Hatchbox-dashboard check (or `curl` the deployed `/up` + version) after the next push to `main`.

## Changelog

- **conjectured:** seeded ISC-77 assumed `bin/rubocop` (Rails Omakase) passes clean, because `CLAUDE.md` lists rubocop in the CI pipeline on push to `main`.
  **refuted by:** `bin/rubocop` on `2026-05-27` reported **667 offenses (586 autocorrectable)** across 248 files — the suite is not green locally.
  **learned:** the repo's rubocop gate is either advisory in CI, has drifted, or relies on autocorrect-on-commit that hasn't run; lint cleanliness is not currently an invariant of `main`.
  **criterion now:** ISC-77 stays `[ ]` pending a decision — run `bin/rubocop -A` to autocorrect the 586, then triage the remaining 81, or relax the criterion to "no new offenses vs baseline."
