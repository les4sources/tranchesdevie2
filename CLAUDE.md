# Tranches de Vie

Artisan bakery e-commerce app (single-tenant) for a Belgian bread bakery. Customers browse a catalog, pre-order for specific bake days (Tuesday/Friday), and pay online. Includes admin panel for production planning, order management, and customer management. All UI is in French.

## Tech Stack

- **Backend**: Ruby 3.3.5, Rails 8.0.3, PostgreSQL
- **Frontend**: Slim templates, Tailwind CSS (`tailwindcss-rails`), Hotwire (Turbo + Stimulus), Importmap
- **Payments**: Stripe (PaymentIntents — Card, Bancontact, Apple Pay, Google Pay)
- **SMS**: Smstools API (OTP auth, order notifications)
- **Background Jobs**: Solid Queue (DB-backed, runs inside Puma via `SOLID_QUEUE_IN_PUMA`)
- **Caching/Cable**: Solid Cache, Solid Cable (all DB-backed, no Redis)
- **Decorators**: Draper
- **Soft Deletion**: `soft_deletion` gem
- **Web Server**: Puma + Thruster (HTTP compression/caching proxy)
- **Deployment**: Hatchbox (auto-deploy on push to `main`)
- **Observability**: Sentry
- **Testing**: RSpec, FactoryBot, Faker, VCR/WebMock, Capybara/Selenium

## Commands

```bash
# Development
bin/dev                          # Start dev server (Rails + Tailwind watcher)
bin/rails server                 # Web server only
bin/rails tailwindcss:watch      # CSS watcher only

# Database
bin/rails db:create db:migrate db:seed
bin/rails db:schema:load         # Load schema from scratch

# Tests
bundle exec rspec                # All specs
bundle exec rspec spec/models/   # Model specs only
bundle exec rspec spec/services/ # Service specs only

# Linting & Security
bin/rubocop                      # Style linting (Rails Omakase)
bin/brakeman --no-pager          # Security scanning
bin/importmap audit              # JS dependency audit

# Deployment
# Deploys happen automatically via Hatchbox when `main` is updated.
# Server access (console, logs, SSH) is managed through the Hatchbox dashboard.
```

## Project Structure

```
app/
├── controllers/
│   ├── admin/              # Admin panel (password-protected)
│   ├── customers/          # Customer account, sessions, wallet, calendar
│   ├── cart_controller.rb
│   ├── catalog_controller.rb
│   ├── checkout_controller.rb
│   ├── orders_controller.rb
│   └── webhooks_controller.rb   # Stripe webhooks
├── decorators/             # Draper decorators
├── javascript/controllers/ # Stimulus controllers
├── jobs/                   # Solid Queue background jobs
├── models/                 # ActiveRecord models
├── presenters/
├── services/               # Service objects (business logic)
└── views/                  # Slim templates (.html.slim)
config/
├── routes.rb
└── recurring.yml           # Cron-style scheduled jobs (Solid Queue)
spec/                       # RSpec tests
├── models/, requests/, services/, integration/
├── factories/              # FactoryBot factories
└── cassettes/              # VCR cassettes
```

## Architecture & Patterns

- **Service Objects** (`app/services/`) — all business logic lives here, not in controllers or models
- **Decorators** (`app/decorators/`) — Draper decorators for view presentation logic
- **Session-based Cart** — cart stored in `session[:cart]` as array of hashes, no database cart model
- **Concerns** — controller concerns for `CustomerAuthentication`, `AdminAuthentication`
- **Stimulus Controllers** (`app/javascript/controllers/`) — 23 controllers for interactivity (cart, checkout, calendar, wallet, etc.)
- **Advisory Locks** — PostgreSQL `pg_advisory_xact_lock` used in `OrderCreationService` to prevent race conditions on capacity checks

## Domain Model

### Core Entities

- **Product** → has many **ProductVariant**s (sizes/formats with `price_cents`, `flour_quantity`)
- **BakeDay** — scheduled bake date (`baked_on`) with `cut_off_at` deadline. Tuesday/Friday bakes, Sunday/Wednesday cut-offs at 18:00 Brussels time
- **Customer** — identified by `phone_e164` (Belgian E.164). Has **Wallet** with `balance_cents`
- **Order** → has many **OrderItem**s, belongs to Customer and BakeDay
  - Statuses: `pending → paid → ready → picked_up / no_show`; also `unpaid`, `cancelled`, `planned`
  - Sources: `checkout` (online) or `calendar` (pre-planned)
  - Order number format: `TV-YYYYMMDD-NNNN`
- **Payment** — tracks Stripe PaymentIntent (`stripe_payment_intent_id`, status)
- **Wallet** / **WalletTransaction** — prepaid balance with top_up, order_debit, order_refund transactions
- **Group** — customer discount tiers (`discount_percent`), highest discount applies

### Production Planning

- **Flour** — flour types with `kneader_limit_grams`
- **MoldType** — mold types with unit `limit` per bake day
- **ProductionSetting** — singleton: `oven_capacity_grams` (110kg normal, 165kg market day)
- **ProductFlour** — percentage breakdown of flours per product
- **Artisan** / **BakeDayArtisan** — baker assignments

## Key Business Logic

### Checkout Flow (Online)
1. Customer builds cart, selects bake day
2. Phone verified via SMS OTP → `session[:otp_verified]`
3. `CheckoutController#create_payment_intent` → Stripe PaymentIntent with cart metadata
4. Client-side Stripe JS confirms payment
5. Redirect to `/checkout/success` — tries to find order, falls back to creating from PI metadata
6. Stripe webhook independently creates/confirms order via `OrderCreationService`
7. Idempotency: `StripeEvent` deduplication + order lookup by `payment_intent_id`

### Planned Orders (Calendar)
1. Customer sets recurring orders on `/calendrier` via `PlannedOrderService#upsert`
2. Orders created with `status: planned, source: calendar`
3. `available_balance_cents` = wallet balance minus all committed planned orders
4. After cut-off → `ProcessPlannedOrdersJob` → debits wallet, transitions `planned → paid`
5. Insufficient balance → order cancelled, SMS sent

### Capacity Management (`BakeCapacityService`)
Three resources tracked per bake day:
1. **Molds** — by MoldType, hard unit limit
2. **Kneader** — dough weight per flour type, each flour has `kneader_limit_grams`
3. **Oven** — total flour grams vs. oven capacity

### Key Services

| Service | Responsibility |
|---|---|
| `OrderCreationService` | Order creation with capacity check + advisory lock |
| `BakeCapacityService` | Mold/kneader/oven usage calculation |
| `PlannedOrderService` | Calendar order upsert/cancel with wallet check |
| `ProcessPlannedOrdersService` | Post-cut-off wallet debit + order confirmation |
| `WalletService` | Wallet credit/debit with typed transactions |
| `RefundService` | Stripe refund + order cancellation + SMS |
| `OtpService` | OTP generation, sending, verification |
| `SmsService` | All outbound SMS (confirmation, ready, refund, alerts) |

## Authentication

- **Customers**: Phone-based OTP via Smstools. Session expires after 1 year. Rate limited (5 OTP/phone/60s via Rack::Attack).
- **Admin**: Single password from `ENV['ADMIN_PASSWORD']`. Session expires after 24 hours. No roles/permissions.

## Background Jobs (Solid Queue)

| Schedule | Job | Purpose |
|---|---|---|
| Daily 18:15 | `MarkOrdersReadyJob` | Transition paid → ready, send SMS |
| Sun/Wed 18:05 Brussels | `ProcessPlannedOrdersJob` | Debit wallets, confirm planned orders |
| Sun/Wed 12:00 Brussels | `CheckInsufficientBalanceJob` | Warn customers with low balance |
| Hourly :12 | — | Clear finished Solid Queue jobs |

Config: `config/recurring.yml` (production only)

## Environment Variables

Key env vars (set in `.env` for dev, managed via Hatchbox for production):
- `STRIPE_SECRET_KEY`, `STRIPE_PUBLIC_KEY`, `STRIPE_WEBHOOK_SECRET`
- `ADMIN_PASSWORD`, `ADMIN_USER`
- `RAILS_MASTER_KEY`
- `DATABASE_URL` (production)
- `SMSTOOLS_*` (SMS API credentials)
- `SENTRY_DSN`
- `SLACK_WEBHOOK_URL` (recurring job notifications)

## Conventions

- **Rubocop**: Rails Omakase style (`.rubocop.yml`)
- **Templates**: Slim (`.html.slim`), some legacy `.html.erb`
- **Commits**: free-form, mixed French/English, no conventional commit prefixes
- **CI** (GitHub Actions): brakeman + importmap audit + rubocop on push to `main` and PRs (no test suite in CI yet)
- **Locale**: UI is entirely in French (`config/locales/fr.yml`)
- **Currency**: EUR, stored as cents (`_cents` suffix columns)
- **Phone numbers**: Belgian E.164 format (`+32...`)
- **Timezone**: `Europe/Brussels` for all bake day scheduling
