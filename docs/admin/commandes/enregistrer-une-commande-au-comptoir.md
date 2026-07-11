# Enregistrer une commande au comptoir

Un client vient au fournil et veut réserver du pain pour la prochaine
fournée ? Ou vous êtes au téléphone avec une habituée qui n'utilise pas
Internet ? Voici comment saisir sa commande à sa place.

Une commande enregistrée par ce biais est **exactement équivalente** à
une commande passée en ligne : elle apparaîtra dans les statistiques du
jour de cuisson, elle déclenchera le SMS « votre pain est prêt » au bon
moment, elle sera imprimable sur la feuille de fournée.

## Ce dont vous avez besoin

- Le **nom du client** (il doit déjà exister dans la base ; si ce n'est
  pas le cas, [créez-le d'abord](../mangeurs/creer-un-mangeur.md)).
- Le **jour de cuisson** pour lequel il commande. Ce jour doit exister
  (voir [Planifier un jour de cuisson](../jours-de-cuisson/planifier-un-jour-de-cuisson.md))
  et sa clôture ne doit pas être passée.
- Les **produits et quantités** demandés.
- Le **mode de paiement** (payé au comptoir en cash, à créditer sur son
  portefeuille, à facturer plus tard...).

## Pas à pas

### 1. Ouvrir le formulaire

Dans le menu, cliquez sur **Commandes**, puis sur le bouton
**« Nouvelle commande »** en haut à droite.

![Bouton nouvelle commande](../images/orders-new-button.png)

Vous arrivez sur ce formulaire :

![Formulaire nouvelle commande](../images/orders-new.png)

### 2. Choisir le client

Dans la première liste déroulante, cherchez le client. Vous pouvez **taper
son nom** pour filtrer la liste — pas besoin de faire défiler.

Les clients sont classés par **nom de famille en majuscules**, prénom
ensuite : « DUPONT Marie », « MARTIN Pierre ».

### 3. Choisir le jour de cuisson

Deuxième liste déroulante : sélectionnez le jour de cuisson concerné. La
liste ne montre que **les jours dont la clôture n'est pas encore passée**.

### 4. Saisir les quantités

Le tableau vous montre tous les produits actifs, avec leurs variantes en
colonnes (par exemple : *Grand*, *Petit*, *Individuel*).

Tapez la quantité souhaitée dans la case correspondante. Le **sous-total
de la ligne** se met à jour instantanément, et le **montant total** de la
commande apparaît en bas.

> **Astuce.** Si le client bénéficie d'une **remise de groupe**
> (professionnels, associations…), le montant total tient déjà compte de
> sa remise. Un petit message vert vous rappelle laquelle est appliquée.

### 5. Vérifier le montant final

En bas du formulaire, le champ **« Montant final de la commande »** reprend
le total calculé. Vous pouvez **le modifier à la main** si vous voulez
appliquer une remise exceptionnelle ou arrondir le montant.

### 6. Choisir le statut

Quatre choix :

| Statut | Quand l'utiliser |
|---|---|
| **Non payée** | Le client paiera plus tard (facturation mensuelle, à l'enlèvement…). |
| **Payée** | Le client vient de payer au comptoir en cash ou par carte. |
| **Prête** | Cas rare : la commande est déjà préparée et il vient la chercher tout de suite. Envoie automatiquement le SMS « votre pain est prêt ». |
| **Retirée** | Cas rare : tout est fait, il l'a déjà en main. Ne déclenche aucun SMS. |

### 7. Faut-il une facture ?

Cochez **« Il faut une facture pour cette commande »** si le client
est un professionnel qui vous a demandé une facture. Vous pourrez la
générer plus tard depuis la fiche de la commande.

### 8. Cliquer sur « Créer la commande »

Vous atterrissez sur la **fiche de la commande**, avec son numéro unique
(format `TV-20260714-0042`) et toutes les actions possibles.

![Fiche d'une commande](../images/order-show.png)

## Erreurs courantes

**« Client obligatoire »**
: vous n'avez pas sélectionné de client. Utilisez la recherche pour filtrer
  la liste si vous ne le trouvez pas.

**« Jour de cuisson obligatoire »** ou aucun jour dans la liste
: soit vous avez oublié de sélectionner un jour, soit **aucun jour de
  cuisson à venir n'est planifié**. Dans ce second cas, il faut d'abord
  [planifier un jour de cuisson](../jours-de-cuisson/planifier-un-jour-de-cuisson.md).

**« Capacité de production dépassée »**
: cette fournée est complète. Vous avez deux options : ajuster la commande
  pour rentrer dans la capacité restante, ou en discuter avec le client
  pour reporter sur une autre fournée.

## Pour aller plus loin

- [Modifier une commande](modifier-une-commande.md) — pour changer les
  quantités ou le statut après création.
- [Créer un mangeur au comptoir](../mangeurs/creer-un-mangeur.md) — si le
  client n'existe pas encore dans votre base.
- [Marquer une commande prête ou récupérée](marquer-prete-recuperee.md) — la
  suite logique du parcours.
