---
title: Les commandes
order: 2
icon: "🧾"
summary: Suivre, préparer, encaisser et modifier les commandes du jour.
---

# Les commandes

L'onglet **Commandes** est ton tableau de bord au quotidien. Tu y vois toutes
les commandes, tu les filtres par jour de cuisson, et tu suis leur avancement
jusqu'au retrait.

![La liste des commandes](shot:orders-index)

## Lire la liste

Chaque ligne, c'est une commande :

- **Commande** — le numéro unique, au format `TV-AAAAMMJJ-NNNN`.
- **Client** — le mangeur qui a commandé.
- **Jour de cuisson** — la fournée pour laquelle c'est prévu.
- **Total** — le montant de la commande.
- **Statut** — où en est la commande (voir plus bas).
- **Paiement** — payée en ligne, par portefeuille, ou non payée.
- **Actions** — **Voir** (le détail) ou **Modifier**.

## Filtrer

En haut à droite, trois menus déroulants + le bouton **Filtrer** :

- **Tous les statuts** → n'afficher que les commandes en attente, prêtes…
- **Tous les paiements** → trier payées / non payées.
- **Tous les jours** → se concentrer sur une fournée précise.

> Le matin d'une fournée : filtre sur **le jour du jour** pour n'avoir sous les
> yeux que les commandes à préparer.

## Comprendre les statuts

Une commande avance dans cet ordre :

| Statut | Ce que ça veut dire |
| --- | --- |
| **En attente** | Commande créée, paiement pas encore confirmé. |
| **Payée** | Payée, à produire. |
| **Prête** | Préparée, elle attend son retrait (SMS envoyé au client). |
| **Récupérée** | Le client est passé la chercher. C'est bouclé. |
| **Absente** | Le client n'est pas venu (no-show). |

Il existe aussi **Annulée** (commande annulée + remboursée) et **Planifiée**
(commande récurrente du calendrier, pas encore confirmée).

## Changer le statut d'une commande

1. Clique sur **Voir** pour ouvrir la commande.
2. Change le statut avec les boutons prévus (par ex. passer une commande de
   **Payée** à **Prête** quand le sac est prêt).

![Le détail d'une commande](shot:order-show)

Beaucoup de transitions sont automatiques : après la fournée, les commandes
payées passent **Prêtes** toutes seules et le client reçoit un SMS. Tu n'as
donc pas à tout faire à la main.

## Créer une commande à la main

Un client passe au comptoir ou t'appelle ? Bouton **Nouvelle commande** en haut
à droite. Tu choisis le mangeur (ou tu en crées un avec **Nouveau mangeur**), la
fournée, et les produits.

## Rembourser

Depuis le détail d'une commande, l'action **Rembourser** annule la commande,
rend l'argent (en ligne ou sur le portefeuille) et prévient le client par SMS.
