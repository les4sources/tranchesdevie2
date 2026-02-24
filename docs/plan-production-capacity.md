# Gestion des capacites de production (v2 - multi-tenant)

## Contexte

L'atelier de boulangerie a des limites techniques (moules, petrin, four) non refletees dans l'application. Les clients commandent sans limites, risquant de surcharger la production. L'application est destinee a devenir multi-tenants : les types de moules, farines et limites varient d'une boulangerie a l'autre.

**Objectif** : systeme de capacite configurable, pas hardcode.

**Regles metier** :
- Seuls les produits `breads` comptent (les `dough_balls` sont vendus crus, pas de moule ni four)
- `flour_quantity` sur les variantes = poids de pate en grammes (deja renseigne)
- La composition en farine d'un produit est definie via `ProductFlour` (product has_many flours avec pourcentages)
- La limite petrin est par type de farine (ex: froment 90kg), pas globale

---

## Architecture multi-tenant

### Changement cle vs plan v1 : `MoldType` modele au lieu d'enum hardcode

| Plan v1 (abandonne) | Plan v2 (multi-tenant) |
|---|---|
| Enum hardcode `grand: 0, classique: 1...` | Table `mold_types` avec CRUD dans Settings |
| `production_capacities` singleton avec colonnes specifiques par moule | Chaque `MoldType` porte sa propre `limit` |
| Limite petrin globale "froment = 90kg" | `Flour.kneader_limit_grams` par type de farine |

---

## Phase 1 : Migrations

### 1a. Creer table `mold_types`
```
name          string   NOT NULL, unique (where deleted_at IS NULL)
limit         integer  NOT NULL  (nb max par jour de cuisson)
position      integer  default 0
deleted_at    datetime (soft deletion)
timestamps
```
Gere dans Settings (comme Flour, Ingredient). Chaque boulangerie definit ses propres types.

### 1b. Ajouter `mold_type_id` a `product_variants`
FK nullable vers `mold_types`. NULL = pas de moule (patons, ou non assigne).
Index sur `mold_type_id`.

### 1c. Ajouter `kneader_limit_grams` a `flours`
Colonne `integer`, nullable. NULL = pas de limite petrin pour cette farine.
Ex: Froment = 90000 (90 kg), Epeautre = NULL (pas de limite specifique).

### 1d. Creer table `production_settings` (singleton)
```
oven_capacity_grams           integer  NOT NULL, default 110000
market_day_oven_capacity_grams integer  NOT NULL, default 165000
timestamps
```
Uniquement les limites four (globales, toutes farines confondues).

### 1e. Ajouter `market_day` boolean a `bake_days` (default false)

### 1f. Migration de donnees
- Creer les 5 MoldType initiaux : Grand (95), Classique (100), Petit (50), Grand rond (10), Classique rond (10)
- Creer la ligne singleton `ProductionSetting`
- Mettre `kneader_limit_grams = 90000` sur la farine Froment existante
- Backfill `mold_type_id` sur les variantes `breads` existantes via pattern matching SQL (meme logique que `BakeDayDashboard#detect_mold_size`)

---

## Phase 2 : Modeles

### Nouveau : `MoldType` (`app/models/mold_type.rb`)
```ruby
has_soft_deletion
has_many :product_variants, dependent: :restrict_with_error
validates :name, presence: true, uniqueness: { conditions: -> { where(deleted_at: nil) } }
validates :limit, presence: true, numericality: { greater_than: 0, only_integer: true }
scope :ordered, -> { order(position: :asc, name: :asc) }
scope :not_deleted, -> { where(deleted_at: nil) }
```

### `ProductVariant` (`app/models/product_variant.rb`)
```ruby
belongs_to :mold_type, optional: true
```

### `Flour` (`app/models/flour.rb`)
Pas de changement au modele, la colonne `kneader_limit_grams` est auto-detectee.

### Nouveau : `ProductionSetting` (`app/models/production_setting.rb`)
```ruby
validates :oven_capacity_grams, :market_day_oven_capacity_grams,
          presence: true, numericality: { greater_than: 0, only_integer: true }
def self.current
  first || create!
end
before_create :ensure_singleton
```

### `BakeDay` (`app/models/bake_day.rb`)
```ruby
def oven_capacity_grams
  setting = ProductionSetting.current
  market_day? ? setting.market_day_oven_capacity_grams : setting.oven_capacity_grams
end
```

---

## Phase 3 : `BakeCapacityService` (nouveau)

**Fichier** : `app/services/bake_capacity_service.rb`

**Interface** :
- `usage` → hash avec utilisation courante par ressource
- `fill_percentage` → % de la ressource la plus contrainte (0..100+)
- `fully_booked?` → true si une ressource >= 100%
- `cart_fits?(cart_items)` → `{ fits: bool, errors: [...] }`

**Logique moules** :
- Requete sur `OrderItem` → `ProductVariant` → `mold_type_id`, filtre `breads`, exclut `cancelled`
- Grouper par `mold_type_id`, comparer au `mold_type.limit`

**Logique pate/petrin** (par farine) :
- Pour chaque order_item de type `breads` :
  - `dough_grams = qty * variant.flour_quantity`
  - Distribuer par farine via `product.product_flours` (pourcentages)
  - `contribution_farine_X = dough_grams * pf.percentage / 100`
- Comparer le total par farine au `flour.kneader_limit_grams` (si defini)

**Logique four** (total) :
- Somme de tous les `dough_grams` des order_items breads
- Comparer a `bake_day.oven_capacity_grams`

**Variantes sans `mold_type_id`** : comptent dans la pate mais pas dans les moules.

---

## Phase 4 : Admin - Settings (moules + four)

### Routes (`config/routes.rb`)
Dans le scope `settings` existant, ajouter :
```ruby
resources :mold_types, path: "types-de-moules"
resource :production_setting, path: "capacites-de-production", only: [:edit, :update]
```

### Controlleur moules (`app/controllers/admin/settings/mold_types_controller.rb`)
CRUD standard, meme pattern que `FloursController`. Soft delete avec check de dependances (variantes liees).

### Vue moules (`app/views/admin/settings/mold_types/`)
- `index` : liste avec nom + limite
- `new` / `edit` / `_form` : champs name, limit, position

### Controlleur production (`app/controllers/admin/settings/production_settings_controller.rb`)
- `edit` : charge `ProductionSetting.current`
- `update` : met a jour `oven_capacity_grams` et `market_day_oven_capacity_grams`

### Vue production (`app/views/admin/settings/production_settings/edit.html.slim`)
Formulaire avec 2 champs (four normal en g, four marche en g) + affichage en kg

### Limite petrin par farine
Ajouter le champ `kneader_limit_grams` dans le formulaire existant d'edition des farines (`app/views/admin/settings/flours/_form.html.slim`).
Mettre a jour `flour_params` dans `FloursController` pour autoriser `:kneader_limit_grams`.

### Navigation Settings (`app/views/admin/settings/index.html.slim`)
Ajouter 2 liens : "Types de moules" et "Capacites de production"

---

## Phase 5 : Admin - Jour de marche + type de moule sur variante

### Formulaires bake_day (`edit.html.slim` et `new.html.slim`)
Ajouter checkbox "Jour de marche (capacite four etendue)" apres `internal_note`

### Strong params bake_day (`app/controllers/admin/bake_days_controller.rb`)
Ajouter `:market_day`

### Table bake_days (`app/views/admin/bake_days/_table.html.slim`)
Badge "Marche" si `bake_day.market_day?`

### Formulaire variante (`edit_variant.html.slim` et `new_variant.html.slim`)
Ajouter select "Type de moule" : collection_select depuis `MoldType.not_deleted.ordered`, avec option vide "Aucun"

### Strong params variante (`app/controllers/admin/products_controller.rb`)
Ajouter `:mold_type_id`

---

## Phase 6 : Admin - Dashboard bake_day

### Presenter (`app/presenters/admin/bake_day_dashboard.rb`)
- Supprimer `XXL_MOLD_PATTERNS`, `LARGE_MOLD_PATTERNS`, etc. et `detect_mold_size`
- `breads_mold_requirements` : grouper par `variant.mold_type` (objet), sommer les qty
- Ajouter `capacity_service` qui retourne `BakeCapacityService.new(bake_day)`
- Mettre a jour `variant_stats` : remplacer `mold_size` par `mold_type` (l'objet ou nil)

### Vue dashboard (`app/views/admin/bake_days/show.html.slim`)
Section "Capacite de production" :
- Pour chaque `MoldType` actif : carte avec `used / limit` + barre de progression
- Pour chaque `Flour` avec `kneader_limit_grams` : carte petrin avec `used / limit`
- Carte four total : `used / oven_capacity` en kg
- Couleurs : vert < 80%, orange >= 80%, rouge >= 100%
- Badge "Jour de marche" si applicable
- Fill % global en titre

Colonne "Notes" du tableau variantes : afficher `variant.mold_type&.name || "A assigner"`

---

## Phase 7 : Client - Jauge et blocage

### CartController (`app/controllers/cart_controller.rb`)
- `show` : calculer `@bake_day_capacities` = `{ bd.id => { fill_percentage:, fully_booked: } }`
- `show` : vider selection si bake_day fully_booked
- `update_bake_day` : check `fully_booked?` apres `can_order?`

### Vue panier (`app/views/cart/show.html.erb`)
Pour chaque jour de cuisson :
- Barre de progression (h-2 w-16) + pourcentage
- Si complet : badge "Complet", radio `disabled`, style grise
- Couleur barre : emerald < 80%, amber >= 80%

---

## Phase 8 : Validation a la creation de commande

### `OrderCreationService` (`app/services/order_creation_service.rb`)
- Ajouter param `skip_capacity_check: false`
- Dans `valid?` : `BakeCapacityService.new(@bake_day).cart_fits?(@cart_items)` sauf si skip
- Race conditions : `pg_advisory_xact_lock(bake_day.id)` dans transaction, re-verifier dans le lock

### `CheckoutController` (`app/controllers/checkout_controller.rb`)
- `create_payment_intent` : pre-check capacite AVANT PaymentIntent Stripe

### `WebhooksController` (`app/controllers/webhooks_controller.rb`)
- Passer `skip_capacity_check: true` (client a deja paye, on accepte)

### Commandes admin : pas de blocage capacite

---

## Fichiers a creer

| Fichier | Description |
|---------|-------------|
| `db/migrate/*_create_mold_types.rb` | Table mold_types |
| `db/migrate/*_add_mold_type_id_to_product_variants.rb` | FK mold_type_id |
| `db/migrate/*_add_kneader_limit_to_flours.rb` | Colonne kneader_limit_grams |
| `db/migrate/*_create_production_settings.rb` | Table singleton four |
| `db/migrate/*_add_market_day_to_bake_days.rb` | Colonne market_day |
| `db/migrate/*_seed_mold_types_and_production_settings.rb` | Donnees initiales + backfill |
| `app/models/mold_type.rb` | Modele MoldType |
| `app/models/production_setting.rb` | Modele singleton |
| `app/services/bake_capacity_service.rb` | Service calcul capacite |
| `app/controllers/admin/settings/mold_types_controller.rb` | CRUD moules |
| `app/controllers/admin/settings/production_settings_controller.rb` | Edit capacites four |
| `app/views/admin/settings/mold_types/` | index, new, edit, _form |
| `app/views/admin/settings/production_settings/edit.html.slim` | Form capacites four |

## Fichiers a modifier

| Fichier | Modification |
|---------|-------------|
| `app/models/product_variant.rb` | `belongs_to :mold_type, optional: true` |
| `app/models/bake_day.rb` | `oven_capacity_grams` helper |
| `app/presenters/admin/bake_day_dashboard.rb` | Supprimer pattern matching, utiliser mold_type FK, ajouter capacity |
| `app/services/order_creation_service.rb` | Validation capacite + advisory lock |
| `app/controllers/cart_controller.rb` | Capacite dans show + update_bake_day |
| `app/controllers/checkout_controller.rb` | Pre-check avant payment intent |
| `app/controllers/webhooks_controller.rb` | skip_capacity_check: true |
| `app/controllers/admin/bake_days_controller.rb` | Permit :market_day |
| `app/controllers/admin/products_controller.rb` | Permit :mold_type_id |
| `app/controllers/admin/settings/flours_controller.rb` | Permit :kneader_limit_grams |
| `app/views/admin/settings/flours/_form.html.slim` | Champ kneader_limit_grams |
| `app/views/admin/settings/index.html.slim` | Liens moules + capacites |
| `app/views/cart/show.html.erb` | Jauge + blocage dates completes |
| `app/views/admin/bake_days/show.html.slim` | Dashboard capacite dynamique |
| `app/views/admin/bake_days/edit.html.slim` | Checkbox market_day |
| `app/views/admin/bake_days/new.html.slim` | Checkbox market_day |
| `app/views/admin/bake_days/_table.html.slim` | Badge marche |
| `app/views/admin/products/edit_variant.html.slim` | Select mold_type_id |
| `app/views/admin/products/new_variant.html.slim` | Select mold_type_id |
| `config/routes.rb` | Routes settings mold_types + production_setting |

---

## Verification

1. `bin/rails db:migrate` - les 6 migrations passent
2. Console : `MoldType.not_deleted.count` == 5, `ProductionSetting.current` retourne la config
3. Console : `Flour.find_by(name: "Froment").kneader_limit_grams` == 90000
4. Admin Settings : CRUD sur les types de moules (creer, editer, supprimer)
5. Admin Settings : editer les capacites four
6. Admin Settings : editer une farine, renseigner la limite petrin
7. Admin : editer une variante de pain, selectionner un type de moule
8. Admin : creer/editer un bake_day avec "Jour de marche"
9. Admin : dashboard bake_day avec jauges dynamiques (moules + petrin + four)
10. Client : panier avec jauges par jour de cuisson
11. Client : date complete non selectionnable
12. Checkout : commande depassant capacite → erreur
