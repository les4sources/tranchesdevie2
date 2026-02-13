# Gestion des capacites de production

## Contexte

L'atelier de boulangerie a des limites techniques (moules, petrin, four) non refletees dans l'application. Les clients commandent sans limites, risquant de surcharger la production. On ajoute :
- Configuration des limites depuis l'admin
- Jauge de remplissage par jour de cuisson cote client
- Blocage des dates completes
- Validation serveur a la creation de commande

Regles metier cles :
- Seuls les produits `breads` comptent (les `dough_balls` sont vendus crus, pas de moule ni four)
- `flour_quantity` sur les variantes = poids de pate en grammes (deja renseigne)
- `product.flour == "wheat"` identifie le froment (pour la limite petrin)

---

## Phase 1 : Migrations

### 1a. Ajouter `mold_type` a `product_variants`
Colonne `integer`, nullable. Enum : `grand: 0, classique: 1, petit: 2, grand_rond: 3, classique_rond: 4`. NULL = pas de moule.

### 1b. Creer table `production_capacities` (singleton)
| Colonne | Type | Default |
|---------|------|---------|
| `grands_limit` | integer | 95 |
| `classiques_limit` | integer | 100 |
| `petits_limit` | integer | 50 |
| `grands_ronds_limit` | integer | 10 |
| `classiques_ronds_limit` | integer | 10 |
| `froment_dough_limit_grams` | integer | 90000 |
| `total_dough_limit_grams` | integer | 110000 |
| `market_day_dough_limit_grams` | integer | 165000 |

### 1c. Ajouter `market_day` boolean a `bake_days` (default false)

### 1d. Migration de donnees
- Creer la ligne singleton `ProductionCapacity` avec les valeurs par defaut
- Backfill `mold_type` sur les variantes `breads` existantes via pattern matching SQL (meme logique que `BakeDayDashboard#detect_mold_size`)

---

## Phase 2 : Modeles

### `ProductVariant` (`app/models/product_variant.rb`)
Ajouter l'enum :
```ruby
enum :mold_type, { grand: 0, classique: 1, petit: 2, grand_rond: 3, classique_rond: 4 }, prefix: true
```

### Nouveau : `ProductionCapacity` (`app/models/production_capacity.rb`)
- Validations de presence et numericite sur toutes les colonnes
- Pattern singleton : `self.current` retourne la seule ligne (cree avec defaults si absente)
- `before_create :ensure_singleton` pour empecher les doublons

### `BakeDay` (`app/models/bake_day.rb`)
Ajouter methode helper :
```ruby
def total_dough_limit_grams
  capacity = ProductionCapacity.current
  market_day? ? capacity.market_day_dough_limit_grams : capacity.total_dough_limit_grams
end
```

---

## Phase 3 : `BakeCapacityService` (nouveau)

**Fichier** : `app/services/bake_capacity_service.rb`

Responsabilites :
- `usage` : calcule l'utilisation courante (moules + pate froment + pate totale) pour un bake_day
- `fill_percentage` : retourne le % de la ressource la plus contrainte
- `fully_booked?` : true si une ressource >= 100%
- `cart_fits?(cart_items)` : verifie si un panier s'ajoute sans depasser les limites, retourne `{ fits: bool, errors: [...] }`

Logique :
- Requete `OrderItem.joins(order: [], product_variant: :product)` filtre `orders.bake_day_id`, exclut `status: :cancelled`, filtre `products.category: :breads`
- Froment = `product.flour == "wheat"`
- Variantes avec `mold_type = nil` comptent dans la pate mais pas dans les moules

---

## Phase 4 : Admin - Configuration des capacites

### Route (`config/routes.rb`)
Dans `namespace :admin` ajouter : `resource :production_capacity, only: [:edit, :update]`

### Controlleur (`app/controllers/admin/production_capacities_controller.rb`)
- `edit` : charge `ProductionCapacity.current`
- `update` : met a jour avec strong params

### Vue (`app/views/admin/production_capacities/edit.html.slim`)
Formulaire avec 2 sections :
1. **Limites de moules** : 5 champs number (grands, classiques, petits, grands ronds, classiques ronds)
2. **Capacites pate/four** : 3 champs number avec affichage en kg (petrin froment, four normal, four marche)

### Navigation admin (`app/views/layouts/admin.html.erb`)
Ajouter lien "Capacites" dans le desktop nav (l30-36) et mobile nav (l68-74) :
```erb
<%= link_to "Capacites", edit_admin_production_capacity_path, class: admin_nav_link_class("production_capacities") %>
```

---

## Phase 5 : Admin - Jour de marche + type de moule

### Formulaires bake_day (`app/views/admin/bake_days/edit.html.slim` et `new.html.slim`)
Ajouter checkbox "Jour de marche (3 fournees)" apres le champ `internal_note`

### Strong params (`app/controllers/admin/bake_days_controller.rb:99`)
Ajouter `:market_day` dans `bake_day_params`

### Table bake_days (`app/views/admin/bake_days/_table.html.slim`)
Ajouter badge "Marche" a cote de la date si `bake_day.market_day?`

### Formulaire variante (`app/views/admin/products/edit_variant.html.slim` et `new_variant.html.slim`)
Ajouter select "Type de moule" dans la grille (l16-25), apres `flour_quantity` :
Options : Aucun, Grand (1 kg / XXL), Classique (800 g), Petit (600 g), Grand rond, Classique rond

### Strong params variante (`app/controllers/admin/products_controller.rb:113`)
Ajouter `:mold_type` dans `variant_params`

---

## Phase 6 : Admin - Dashboard bake_day

### Presenter (`app/presenters/admin/bake_day_dashboard.rb`)
- Supprimer les constantes `XXL_MOLD_PATTERNS`, `LARGE_MOLD_PATTERNS`, `MIDDLE_MOLD_PATTERNS`, `SMALL_MOLD_PATTERNS` et la methode `detect_mold_size`
- Mettre a jour `breads_mold_requirements` pour utiliser `variant.mold_type` au lieu du pattern matching
- Ajouter categories `grand_rond` et `classique_rond`
- Ajouter methodes `capacity_usage` et `fill_percentage` (delegue a `BakeCapacityService`)
- Mettre a jour `variant_stats` pour exposer `mold_type` au lieu de `mold_size`

### Vue dashboard (`app/views/admin/bake_days/show.html.slim`)
- Remplacer la section moules (l85-113) par des cartes montrant usage/limite avec barres de progression colorees (vert < 80%, orange >= 80%, rouge >= 100%)
- Ajouter section pate (petrin froment + four total) avec meme visualisation
- Afficher "Jour de marche" si applicable
- Mettre a jour la colonne "Notes" du tableau variantes (l236-244) pour utiliser `mold_type`

### Helper (`app/helpers/admin/bake_days_helper.rb`)
Ajouter `mold_type_label(mold_type)` pour les labels francais

---

## Phase 7 : Client - Jauge et blocage

### CartController (`app/controllers/cart_controller.rb`)
- Dans `show` : calculer `@bake_day_capacities` hash {bd.id => {fill_percentage, fully_booked}} pour chaque bake day disponible
- Dans `show` : vider la selection si le bake_day est fully_booked (apres le check `can_order?` existant)
- Dans `update_bake_day` : ajouter check `fully_booked?` apres `can_order?`, retourner erreur si complet

### Vue panier (`app/views/cart/show.html.erb`)
Mettre a jour la section radio buttons (l8-33) :
- Ajouter barre de progression (h-2 w-16) a cote de chaque jour
- Afficher badge "Complet" + griser + `disabled` sur le radio si fully_booked
- Couleur : vert < 80%, orange >= 80%

---

## Phase 8 : Validation a la creation de commande

### `OrderCreationService` (`app/services/order_creation_service.rb`)
- Ajouter param `skip_capacity_check: false` au constructeur
- Dans `valid?` : appeler `BakeCapacityService.new(@bake_day).cart_fits?(@cart_items)` sauf si `skip_capacity_check`
- Proteger contre les race conditions avec `pg_advisory_xact_lock(bake_day.id)` dans une transaction, re-verifier la capacite dans le lock

### `CheckoutController` (`app/controllers/checkout_controller.rb`)
- Dans `create_payment_intent` : ajouter pre-check capacite AVANT de creer le PaymentIntent Stripe (pour ne pas encaisser si complet)

### `WebhooksController` (`app/controllers/webhooks_controller.rb:117-122`)
- Passer `skip_capacity_check: true` a `OrderCreationService` dans le webhook (le client a deja paye, on accepte)

### Commandes admin
Pas de changement - l'admin cree des commandes directement sans passer par `OrderCreationService`, donc pas de blocage capacite.

---

## Fichiers a creer

| Fichier | Description |
|---------|-------------|
| `db/migrate/*_add_mold_type_to_product_variants.rb` | Migration mold_type |
| `db/migrate/*_create_production_capacities.rb` | Table config capacites |
| `db/migrate/*_add_market_day_to_bake_days.rb` | Colonne market_day |
| `db/migrate/*_seed_capacity_and_backfill_mold_types.rb` | Donnees initiales |
| `app/models/production_capacity.rb` | Modele singleton |
| `app/services/bake_capacity_service.rb` | Service calcul capacite |
| `app/controllers/admin/production_capacities_controller.rb` | Controlleur admin config |
| `app/views/admin/production_capacities/edit.html.slim` | Vue admin config |

## Fichiers a modifier

| Fichier | Modification |
|---------|-------------|
| `app/models/product_variant.rb` | Enum mold_type |
| `app/models/bake_day.rb` | Helper total_dough_limit_grams |
| `app/presenters/admin/bake_day_dashboard.rb` | Remplacer pattern matching, ajouter capacity |
| `app/services/order_creation_service.rb` | Validation capacite + advisory lock |
| `app/controllers/cart_controller.rb` | Capacite dans show + update_bake_day |
| `app/controllers/checkout_controller.rb` | Pre-check avant payment intent |
| `app/controllers/webhooks_controller.rb` | skip_capacity_check: true |
| `app/controllers/admin/bake_days_controller.rb` | Permit :market_day |
| `app/controllers/admin/products_controller.rb` | Permit :mold_type |
| `app/views/cart/show.html.erb` | Jauge + blocage dates completes |
| `app/views/admin/bake_days/show.html.slim` | Dashboard capacite |
| `app/views/admin/bake_days/edit.html.slim` | Checkbox market_day |
| `app/views/admin/bake_days/new.html.slim` | Checkbox market_day |
| `app/views/admin/bake_days/_table.html.slim` | Badge marche |
| `app/views/admin/products/edit_variant.html.slim` | Select mold_type |
| `app/views/admin/products/new_variant.html.slim` | Select mold_type |
| `app/views/layouts/admin.html.erb` | Lien nav "Capacites" |
| `app/helpers/admin/bake_days_helper.rb` | mold_type_label helper |
| `config/routes.rb` | Route production_capacity |

---

## Verification

1. `bin/rails db:migrate` - les 4 migrations passent
2. Verifier en console : `ProductionCapacity.current` retourne la config avec les defaults
3. Verifier le backfill : `ProductVariant.joins(:product).where(products: {category: :breads}).where.not(mold_type: nil).count`
4. Admin : naviguer vers "Capacites", modifier une limite, sauvegarder
5. Admin : creer/editer un bake_day avec "Jour de marche" coche
6. Admin : editer une variante de pain, selectionner un type de moule
7. Admin : voir le dashboard d'un bake_day avec commandes - verifier les jauges moules + pate
8. Client : aller au panier, verifier les jauges sur les jours de cuisson
9. Client : tenter de commander sur un jour complet - verifier le blocage
10. Checkout : tenter de creer une commande depassant la capacite - verifier l'erreur
