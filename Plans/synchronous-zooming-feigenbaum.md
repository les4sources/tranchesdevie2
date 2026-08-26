# Plan — Réparer les confirmations d'actions destructives (bug `data-confirm` mort)

## Context

Ce matin (03/07/2026), les boulangers ont cliqué « Annuler la fournée » **sans aucune boîte de
confirmation**. L'action a déclenché des remboursements Stripe irréversibles + un SMS à tous les
clients, puis a dû être réparée à la main.

Cause racine identifiée : le bouton **avait** une confirmation, écrite en `data: { confirm: … }`
(syntaxe **Rails UJS**). Or l'app est en **Turbo/Hotwire** et **rails-ujs n'est chargé nulle part**
(vérifié : aucune trace dans `app/javascript` ni `config/importmap.rb`). En Turbo, seul
`data-turbo-confirm` est honoré ; `data-confirm` est donc **silencieusement ignoré** → l'action part
au premier clic.

Ce n'est pas isolé : **6 actions destructives** de l'app portent le même bug latent (dont le
remboursement d'une commande — financier). Les autres actions destructives utilisent déjà
correctement `turbo_confirm` (8 occurrences), ce qui prouve que le mécanisme Turbo est bien actif.

Résultat visé : **toute action destructive redemande confirmation**. Deux niveaux :
- **Immédiat (ce plan)** : réparer les 6 `data-confirm` cassés → `turbo_confirm`. Rebouche le trou
  aujourd'hui.
- **Renforcé (issue nocturne)** : pour l'annulation de fournée spécifiquement, une confirmation qui
  montre l'impact chiffré + double garde (rédigée plus bas, à créer après approbation).

Décision déjà prise par Michael : « Correctif now + issue » (via AskUserQuestion).

---

## Part A — Correctif immédiat (à exécuter après approbation)

Bug : `data: { confirm: … }` (UJS, mort) → `data: { turbo_confirm: … }` (Turbo, actif).

**Deux patterns selon le helper :**

1. **`button_to`** — le `turbo_confirm` va sur le **formulaire** via `form:` (convention déjà
   utilisée dans `app/views/admin/customers/show.html.erb`) :
   ```
   button_to "…", path, method: :delete, form: { data: { turbo_confirm: "…" } }
   ```

2. **`form_with … do |f|` + `f.submit`** — le `turbo_confirm` va sur le **`form_with`**, pas sur le
   submit (Turbo lit l'attribut au niveau du formulaire) :
   ```erb
   <%= form_with url: …, method: :patch, data: { turbo_confirm: "…" } do |f| %>
     <%= f.submit "…" %>
   <% end %>
   ```

**Fichiers / occurrences :**

| Fichier | Action | Helper | Sévérité |
|---|---|---|---|
| `app/views/admin/bake_days/show.html.slim:30` | Annuler la fournée | `button_to` | 🔴 **déjà corrigé** cette session |
| `app/views/admin/bake_days/show.html.slim:31` | Supprimer la fournée | `button_to` | 🔴 **déjà corrigé** cette session |
| `app/views/admin/orders/show.html.erb:139` | Rembourser intégralement | `form_with`+`f.submit` | 🔴 financier |
| `app/views/admin/orders/show.html.erb:107` | Marquer comme payée | `form_with`+`f.submit` | 🟠 |
| `app/views/admin/orders/show.html.erb:116` | Envoyer SMS « prête » | `form_with`+`f.submit` | 🟠 envoi SMS |
| `app/views/admin/orders/show.html.erb:131` | Marquer non récupérée | `form_with`+`f.submit` | 🟡 |
| `app/views/admin/products/show.html.slim:84` | Supprimer un variant | `button_to` | 🟠 |
| `app/views/cart/show.html.erb:123` | Retirer un article du panier | `button_to` | 🟢 client, faible enjeu |

> Les deux lignes `bake_days/show` sont **déjà** passées en `form: { data: { turbo_confirm: … } }`
> pendant cette session (avec un texte de confirmation « suppression définitive » enrichi pour le
> bouton Supprimer). Reste à traiter les 6 autres.

**Commit + déploiement :** commit sur `main` → auto-deploy Hatchbox. Message libre FR/EN (convention
repo), ex. `fix: confirmations d'actions destructives (data-confirm → turbo_confirm, rails-ujs absent)`.

---

## Part B — Issue nocturne : confirmation renforcée de l'annulation de fournée

À créer via `gh issue create` (repo `tranches-de-vie`) **après approbation**, puis poser
`agent:ready` (issue auto-suffisante ci-dessous). Périmètre volontairement limité à l'annulation de
fournée — l'action la plus dangereuse.

**Titre :** Confirmation renforcée avant annulation d'une fournée (impact chiffré + double garde)

**Contexte / problème :** L'annulation d'une fournée déclenche des remboursements Stripe
**irréversibles** + un SMS à tous les clients concernés. Une simple confirmation native (« OK »)
reste à un clic du drame et ne montre pas ce qui va se passer. Un incident réel a eu lieu le
03/07/2026. Le correctif `turbo_confirm` (Part A) rebouche le trou immédiat mais reste faible pour
une action de cette gravité.

**Critères d'acceptation (atomiques) :**
- [ ] Cliquer « Annuler la fournée » ouvre un écran/modale de confirmation dédié (pas la boîte
      native), affichant : nombre de commandes impactées, montant total à rembourser (€), ventilation
      par mode (carte Stripe / portefeuille / non encaissé), et nombre de SMS qui seront envoyés.
- [ ] Le bouton de confirmation final est **désactivé** tant que l'admin n'a pas saisi une garde
      explicite (ex. retaper la date de la fournée `JJ/MM/AAAA`, ou le mot `ANNULER`).
- [ ] Les chiffres affichés proviennent du même périmètre que `BakeDayCancellationService`
      (statuts `PROCESSABLE_STATUSES = paid, ready, unpaid, planned`) — pas d'écart entre l'aperçu et
      l'exécution.
- [ ] Annuler/fermer la modale ne déclenche **aucune** action serveur.
- [ ] Garde serveur idempotente : si la fournée n'a plus aucune commande annulable, l'action ne
      rembourse rien et affiche un message neutre (pas d'erreur 500).

**Périmètre (in/out) :**
- IN : la seule action « Annuler la fournée » (`Admin::BakeDaysController#cancel` +
  `app/views/admin/bake_days/show.html.slim`), un contrôleur/vue d'aperçu, éventuellement une méthode
  d'aperçu sur `BakeDayCancellationService` (dry-run comptant sans écrire).
- OUT : les autres confirmations (traitées en Part A), la logique de remboursement elle-même, la
  re-collecte des paiements Stripe.

**Zones de code concernées :**
- `app/controllers/admin/bake_days_controller.rb` (`#cancel`, + éventuelle action `#confirm_cancel`)
- `app/services/bake_day_cancellation_service.rb` (ajouter un aperçu/dry-run réutilisant
  `PROCESSABLE_STATUSES` et `order.payment_method`)
- `app/views/admin/bake_days/show.html.slim` (bouton) + nouvelle vue d'aperçu
- Route `post :cancel` (+ éventuellement `get :confirm_cancel`) dans `config/routes.rb`

**Stratégie de test :**
- Spec service : l'aperçu renvoie les bons compteurs (Stripe/wallet/non payé) sans muter la DB.
- Spec request : `GET confirm_cancel` affiche les chiffres ; `POST cancel` sans la garde saisie est
  refusé ; avec la garde, exécute.
- Vérif manuelle Interceptor sur le site déployé (admin protégé) : parcours complet.

**Definition of Done :** critères cochés, specs vertes (`bundle exec rspec`), rubocop OK, déployé et
vérifié sur l'admin réel via Interceptor, aucun remboursement possible sans double confirmation.

---

## Vérification (Part A, après exécution)

1. **Statique** : `grep -rn "data: { confirm:" app/views` (via built-in Grep, pas RTK) ne renvoie
   plus rien ; `grep -rn "turbo_confirm" app/views` couvre bien les 8 actions destructives.
2. **Déploiement** : confirmer que Hatchbox a embarqué le dernier commit `main`.
3. **Fonctionnel (Interceptor, mandatory)** : se connecter à l'admin déployé, ouvrir une fournée,
   cliquer « Annuler la fournée » → **la boîte de confirmation Turbo doit apparaître** ; « Annuler »
   dans la boîte ne doit déclencher aucune requête. Répéter le check sur « Rembourser » d'une
   commande. Ne PAS confirmer réellement (action destructive) — vérifier seulement l'apparition du
   dialogue et l'annulation propre.
