# Points de retrait — choix client, activation par fournée, répartition boulangers

## Context

Aujourd'hui, toute commande est implicitement retirée aux 4 Sources : le lieu de retrait n'existe nulle part dans le modèle de données. La boulangerie veut désormais proposer plusieurs points de retrait, dont certains ne sont ouverts que sur certaines fournées — typiquement le **Marché d'Anhée**, qui n'a lieu que certains jours.

Trois besoins en découlent :
1. **Client** — choisir son point de retrait au checkout, et pour chacune de ses commandes planifiées sur le calendrier.
2. **Admin** — déclarer les points de retrait, et cocher lesquels sont ouverts sur chaque fournée (dans les deux sens : depuis la fournée, et depuis le lieu).
3. **Boulangers** — voir, sur le tableau de bord d'une fournée, les commandes regroupées par point de retrait, et imprimer un PDF par lieu servant de feuille d'émargement au retrait.

Toutes les commandes existantes doivent être rattachées rétroactivement à « Les 4 Sources ».

## Décisions de cadrage (validées avec Michael)

- **Calendrier** : sélecteur de lieu dans la modale de chaque date, pré-rempli avec le **dernier lieu choisi par le client** (à défaut, le lieu par défaut). Modifiable date par date. Pas de nouveau modèle de préférence.
- **Conflit admin** : un admin ne peut **pas** décocher d'une fournée un lieu déjà utilisé par des commandes de cette fournée → validation bloquante + message listant le nombre de commandes concernées.
- **PDF** : cases à cocher **papier uniquement**. Aucun pointage en ligne, aucun changement de statut de commande.
- **Admin commande** : le lieu de retrait est **éditable** sur la page d'une commande en admin (restreint aux lieux ouverts sur la fournée de la commande).

## Modèle de données

### `pickup_locations` (nouvelle table)

| Colonne | Type | Notes |
|---|---|---|
| `name` | string, NOT NULL | ex. « Les 4 Sources », « Marché d'Anhée » |
| `description` | text | courte, **affichée au client** (horaires, adresse, repères) |
| `default` | boolean, NOT NULL, default false | un seul `true` — validé au modèle |
| `position` | integer | ordre d'affichage dans les sélecteurs |
| `deleted_at` | datetime | soft delete via le gem `soft_deletion` déjà présent |

Un lieu `default` est **automatiquement coché sur toute nouvelle fournée** (callback `after_create` sur `BakeDay`).

### `bake_day_pickup_locations` (table de jointure)

`bake_day_id` + `pickup_location_id`, index unique sur la paire — calquée sur `bake_day_artisans` (`db/schema.rb:71-79`).

### `orders.pickup_location_id`

`belongs_to :pickup_location` (obligatoire à terme). Migration de backfill : toutes les commandes existantes → « Les 4 Sources ».

### Migration & seed

Une migration de données qui : crée « Les 4 Sources » (`default: true`), crée « Marché d'Anhée », rattache « Les 4 Sources » à **toutes** les fournées existantes, puis backfill `orders.pickup_location_id`. Poser le `NOT NULL` sur `orders.pickup_location_id` seulement **après** le backfill.

## Fichiers concernés

### Nouveaux
- `app/models/pickup_location.rb`, `app/models/bake_day_pickup_location.rb`
- `app/controllers/admin/pickup_locations_controller.rb` + vues `app/views/admin/pickup_locations/` (index, new, edit)
- `app/services/pickup_sheet_pdf_service.rb` — **calqué sur `app/services/invoice_pdf_service.rb`** (Prawn + prawn-table, mêmes constantes de charte `BRAND_COLOR`, même contrat `#render` / `#filename`)
- `spec/factories/pickup_locations.rb`

### Modifiés
- `app/models/bake_day.rb` — `has_many :pickup_locations, through:` ; auto-cochage du lieu par défaut à la création ; validation bloquant le retrait d'un lieu encore utilisé par des commandes de la fournée
- `app/models/order.rb` — `belongs_to :pickup_location` + validation « le lieu doit être ouvert sur cette fournée »
- `app/controllers/checkout_controller.rb` — accepter `pickup_location_id` dans `create_payment_intent`, `create_cash_order`, `create_wallet_order`
- `app/services/order_creation_service.rb` — nouveau kwarg `pickup_location:`, validé contre les lieux ouverts sur la fournée
- `app/views/checkout/new.html.erb` — sélecteur de lieu (nom + description), pré-sélectionné sur le lieu par défaut, **filtré sur les lieux ouverts pour la fournée choisie**
- `app/controllers/customers/calendar_controller.rb` + `app/services/planned_order_service.rb` — `pickup_location_id` dans le payload `update_day` et dans `upsert`
- `app/views/customers/calendar/show.html.erb` + `app/javascript/controllers/calendar_controller.js` — sélecteur dans la modale, valeur par défaut = dernier lieu choisi par le client
- `app/controllers/admin/bake_days_controller.rb` + `app/views/admin/bake_days/{new,edit}.html.slim` — `pickup_location_ids: []` dans les params forts + `collection_check_boxes` (les deux vues sont dupliquées, pas de partial `_form` — modifier les deux)
- `app/presenters/admin/bake_day_dashboard.rb` — nouvelle méthode `orders_by_pickup_location` (et agrégat des variantes par lieu, pour la répartition)
- `app/views/admin/bake_days/show.html.slim` — nouvel onglet « Par point de retrait » dans le bloc à onglets existant, avec un bouton PDF par lieu
- `app/controllers/admin/orders_controller.rb` + `app/views/admin/orders/{show,edit}.html.erb` — afficher et éditer le lieu de retrait
- `app/views/orders/show.html.erb` + `app/views/customers/account/_order_modal.html.erb` — afficher le lieu de retrait (nom + description) au client
- `config/routes.rb` — `resources :pickup_locations` dans le namespace admin ; route PDF en `member` sur `bake_days` (ex. `get :pickup_sheet`, paramétrée par `pickup_location_id`), à côté des routes factures existantes
- `app/controllers/api/v1/resource_catalog.rb` (+ serializers) — exposer `pickup_locations` et le champ sur `order` (le catalogue est la source de vérité des 3 surfaces de doc de l'API)

## Le PDF par point de retrait

Route admin en `member` sur la fournée, `send_data` (pattern `Admin::InvoicesController`, pas de `respond_to :pdf`). Contenu :

- **En-tête** : nom du point de retrait + sa description + date de la fournée
- **Tableau** : une ligne par client — nom, téléphone, détail de la commande (variantes × quantités), total
- **Une case à cocher vide** en fin de ligne, à cocher au stylo quand le client est venu
- Trié par nom de client ; statuts inclus : ceux déjà retenus par le dashboard (`PRODUCTION_STATUSES = %i[unpaid paid ready picked_up planned]`)

## Hors périmètre

- Aucun pointage en ligne des retraits, aucun changement de statut de commande depuis le PDF
- Pas de mention du lieu de retrait dans les SMS de confirmation (à traiter séparément si besoin)
- Pas de récurrence de commandes planifiées (n'existe pas dans le produit — chaque commande planifiée est saisie date par date)
- Pas de gestion de capacité par lieu de retrait

## Vérification

1. `bundle exec rspec` — vert.
2. Specs à ajouter :
   - `spec/models/pickup_location_spec.rb` — unicité du lieu par défaut, soft delete
   - `spec/models/bake_day_spec.rb` — auto-cochage du lieu par défaut à la création ; **refus de décocher un lieu utilisé par des commandes** de la fournée
   - `spec/services/order_creation_service_spec.rb` — `pickup_location` persisté ; rejet d'un lieu non ouvert sur la fournée
   - `spec/services/planned_order_service_spec.rb` — `pickup_location` sur `upsert`, et conservé à la mise à jour
   - `spec/services/pickup_sheet_pdf_service_spec.rb` — via `pdf-reader` (comme `invoice_pdf_service_spec.rb`) : le nom du lieu, les clients attendus et **seulement eux**
   - `spec/requests/checkout_spec.rb`, `spec/requests/customers/calendar_spec.rb`, `spec/requests/admin/bake_days_spec.rb` — le lieu circule bien de bout en bout
   - Migration de backfill : toutes les commandes pré-existantes pointent sur « Les 4 Sources »
3. `bin/rubocop` et `bin/brakeman --no-pager` — verts (ce sont les gates de la CI).
4. Vérification navigateur (skill Interceptor) : passer une commande au checkout en choisissant le Marché d'Anhée sur une fournée où il est ouvert ; vérifier qu'il n'est **pas** proposé sur une fournée où il ne l'est pas ; ouvrir le tableau de bord de la fournée, vérifier le regroupement par lieu, télécharger le PDF et vérifier son contenu.
