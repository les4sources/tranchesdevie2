# Plan d'implémentation - PRD Tranches de Vie

## Phase 1: Configuration et dépendances

### 1.1 Ajouter les dépendances Gemfile

- Ajouter `stripe` pour les paiements
- Ajouter `telerivet` ou `httparty`/`faraday` pour l'API Telerivet
- Ajouter `base58` ou utiliser `SecureRandom` pour les tokens Base58
- Ajouter `sentry-ruby` pour l'observabilité
- Ajouter `bcrypt` pour l'authentification admin (déjà commenté)
- Note: Le PRD demande Sidekiq+Redis mais Solid Queue est déjà configuré. Garder Solid Queue sauf si requis spécifiquement.

### 1.2 Configuration timezone et locale

- Vérifier que `config.time_zone = "Europe/Brussels"` est présent (déjà fait)
- S'assurer que la locale FR est par défaut (déjà fait)

## Phase 2: Modèles de données et migrations

### 2.1 Créer les migrations pour les modèles principaux

Créer les migrations dans l'ordre logique:

**products** (category enum: breads, dough_balls; position int; active boolean)

- name, description, category, position, active

**product_variants** (belongs_to product)

- product_id, name, price_cents, active, image_url

**product_availabilities** (belongs_to product_variant)

- product_variant_id, start_on (date), end_on (date nullable)

**bake_days** (baked_on unique, cut_off_at timestamptz)

- baked_on (date unique), cut_off_at (timestamptz)

**customers** (phone_e164 unique)

- phone_e164 (unique), first_name, last_name (nullable), email (nullable), sms_opt_out (boolean default false)

**phone_verifications** (OTP)

- phone_e164, code (6 digits), expires_at, attempts_count

**orders** (belongs_to customer, bake_day)

- customer_id, bake_day_id, status enum, total_cents, public_token (unique), order_number, payment_intent_id (pour idempotency)

**order_items** (belongs_to order, product_variant)

- order_id, product_variant_id, qty, unit_price_cents

**payments** (belongs_to order, unique)

- order_id (unique), stripe_payment_intent_id (unique), status enum

**sms_messages** (historique SMS)

- direction enum, to_e164, from_e164, baked_on (nullable), body, kind enum, external_id

**admin_pages** (CMS simple)

- slug (unique), title, body

### 2.2 Créer les modèles ActiveRecord

Créer tous les modèles avec leurs associations, validations et méthodes métier:

- `Product`, `ProductVariant`, `Availability`, `BakeDay`, `Customer`, `PhoneVerification`, `Order`, `OrderItem`, `Payment`, `SmsMessage`, `AdminPage`

Points importants:

- Product: scope pour ordre (category → position → name)
- BakeDay: méthodes pour calculer cut-offs (Tue ← Sun 18:00, Fri ← Wed 18:00)
- Order: génération `order_number` (TV-YYYYMMDD-XXXX) et `public_token` (Base58 24 chars)
- Customer: validation phone E.164, méthode pour vérifier opt-out SMS
- Status enums avec transitions validées

## Phase 3: Logique métier et services

### 3.1 Services pour cut-offs

- Service `BakeDayService` pour calculer les prochains bake days et vérifier les cut-offs
- Méthode `can_order_for?(date)` avec validation timezone Europe/Brussels

### 3.2 Services pour commandes

- Service `OrderCreationService` pour créer une commande depuis le panier
- Génération automatique `order_number` avec compteur quotidien
- Génération `public_token` cryptographique (Base58)
- Idempotency via `payment_intent_id`

### 3.3 Services SMS

- Service `SmsService` pour envoyer via Telerivet API
- Messages: confirmation (après paiement), ready (changement status), refund (annulation)
- Stocker tous les SMS dans `sms_messages` pour traçabilité

### 3.4 Services de remboursement

- Service `RefundService` pour gérer les remboursements Stripe
- Vérification cut-off avant remboursement
- Mise à jour Payment et Order status
- Envoi SMS de remboursement

## Phase 4: Contrôleurs publics

### 4.1 CatalogController

- `GET /` (root) → redirige vers catalog avec prochain bake day
- `GET /catalog` avec param `bake_day=YYYY-MM-DD`
- Filtrer les produits/variants par disponibilité selon bake_day
- Afficher produits groupés par catégorie avec ordre spécifié

### 4.2 CartController

- Session-based cart (pas de DB)
- `POST /cart/add` ajouter au panier
- `GET /cart` afficher le panier
- `PATCH /cart/update` modifier quantités
- `DELETE /cart/remove` retirer items
- Valider cut-off avant affichage checkout

### 4.3 CheckoutController

- `GET /checkout` formulaire avec Stripe Payment Element
- `POST /checkout/create_payment_intent` créer PaymentIntent Stripe
- Authentification SMS OTP minimal (pas de compte utilisateur)
- Valider cut-off avant création commande
- Formulaire: phone, first_name, last_name, email (optionnel)

### 4.4 OrdersController (public)

- `GET /orders/:token` afficher commande via public_token
- Lecture seule, pas de modification

## Phase 5: Contrôleurs admin

### 5.1 Admin::SessionsController

- Authentification simple par mot de passe (ENV `ADMIN_PASSWORD`)
- Session-based, pas de modèle User
- `GET /admin/login`, `POST /admin/login`, `DELETE /admin/logout`

### 5.2 Admin::OrdersController

- Liste des commandes avec filtres (bake_day, status)
- Détail commande
- Actions: `paid` → `ready` (envoie SMS ready)
- Actions: `ready` → `picked_up` ou `no_show`
- Remboursement: `paid` → `cancelled` (avant cut-off uniquement)

### 5.3 Admin::ProductsController

- CRUD Products et ProductVariants
- Gestion des disponibilités (product_availabilities)
- Upload d'images pour variants

## Phase 6: Intégrations webhooks

### 6.1 Stripe Webhooks

- `POST /webhooks/stripe`
- Events: `payment_intent.succeeded`, `payment_intent.payment_failed`, `charge.refunded`
- Vérification signature avec `STRIPE_WEBHOOK_SECRET`
- Idempotency via `StripeEvent` model
- Créer/update Order et Payment selon event

### 6.2 Telerivet Webhooks

- `POST /webhooks/telerivet`
- Parser keyword STOP dans body
- Mettre à jour `customer.sms_opt_out = true` si STOP détecté
- Stocker message inbound dans `sms_messages`

## Phase 7: Vues et UI

### 7.1 Layout et composants partagés

- Navbar simple avec logo
- Footer
- Alerts/toasts pour messages flash
- Spinners pour loading states

### 7.2 Vues publiques

- `catalog/index` avec grille de produits (product cards)
- `cart/show` page panier (pas drawer)
- `checkout/new` formulaire avec Stripe Payment Element intégré
- `checkout/success` page de confirmation
- `orders/show` détails commande publique
- Utiliser Tailwind UI Starter pour composants

### 7.3 Vues admin

- Layout admin séparé avec sidebar/nav
- `admin/orders/index` table avec badges status
- `admin/orders/show` détail avec actions (modales de confirmation)
- `admin/products` CRUD interface

## Phase 8: JavaScript et Stimulus

### 8.1 Contrôleurs Stimulus

- `cart_controller.js` pour ajout/retrait items (Turbo frames)
- `checkout_controller.js` pour Stripe Payment Element
- `admin_controller.js` pour modales et confirmations

### 8.2 Configuration Stripe

- Intégrer Stripe.js via CDN ou importmap
- Initialiser Payment Element dans checkout form
- Gérer événements Stripe (success, error)

## Phase 9: Seeds et données initiales

### 9.1 Seeds selon PRD

Créer tous les produits et variants spécifiés:

- Category Breads: Spelt (1kg 550c, 600g 350c), Wheat (1kg 450c, 600g 300c), Ancient grains (600g 550c), Walnut (1kg 550c, 600g 400c), Seeded (1kg 550c, 600g 400c), Walnut/fig (600g 400c), Choco/sugar (600g 400c)
- Category Dough balls: Take-away (200c), Private Pizza Party (500c)

### 9.2 Créer quelques bake_days pour tests

- Créer quelques dates de cuisson (mardi et vendredis) avec cut-offs appropriés

## Phase 10: Tests

### 10.1 Tests modèles

- Validations et associations
- Génération order_number et public_token
- Calculs cut-offs avec timezone

### 10.2 Tests contrôleurs

- Catalog avec filtrage par bake_day
- Cart session management
- Checkout avec Stripe mock
- Admin authentication

### 10.3 Tests services

- Cut-off edges (17:59 vs 18:01)
- Order creation idempotency
- SMS sending et opt-out
- Refund flow

### 10.4 Tests webhooks

- Stripe webhook signature validation
- Telerivet STOP parsing
- Idempotency des events

## Phase 11: Configuration production

### 11.1 Variables d'environnement

Documenter toutes les ENV requises:

- `STRIPE_PUBLIC_KEY`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`
- `TELERIVET_API_KEY`, `TELERIVET_PROJECT_ID`, `TELERIVET_PHONE_ID`
- `SENTRY_DSN`
- `ACTIVE_STORAGE_SERVICE`
- `TIME_ZONE=Europe/Brussels`
- `ADMIN_PASSWORD`

### 11.2 Rate limiting

- Ajouter rate limiting pour OTP (60s cooldown, max 5 attempts)
- Rate limiting pour checkout init
- Utiliser `rack-attack` ou `rate_limiter` gem

### 11.3 Logging et observabilité

- Configurer Sentry
- Logger structuré avec masquage PII (phone numbers)
- Performance monitoring pour catalog TTFB < 300ms

## Phase 12: Ajustements finaux

### 12.1 Vérification PRD

- Parcourir tous les points du PRD et vérifier couverture complète
- Vérifier que tous les status transitions sont implémentés
- Vérifier messages SMS exacts selon PRD
- Vérifier format order_number et public_token

### 12.2 Documentation

- Commenter code complexe (cut-offs, idempotency)
- README avec instructions setup
- Documentation API webhooks si nécessaire

### 12.3 A11y et performance

- Vérifier accessibilité (ARIA, focus states)
- Optimiser requêtes N+1
- Cache si nécessaire pour catalog