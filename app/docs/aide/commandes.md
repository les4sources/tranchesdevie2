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

⚠️ **Attention au piège** : dans le formulaire **Modifier**, le menu « Statut de paiement » a une option « Remboursé ». Cette option **ne rembourse rien** — c'est une simple étiquette comptable, réservée aux paiements en espèces rendus de la main à la main. Pour rendre l'argent d'un paiement en ligne (Bancontact, carte) ou portefeuille, utilise toujours le bouton rouge **Rembourser** sur la page de la commande : lui seul renvoie vraiment l'argent au client.

Le bouton **Rembourser** n'est visible que tant que la commande est « Payée » et que la date limite de commande n'est pas passée. S'il n'apparaît plus et qu'il faut quand même rembourser, contacte Michael.

## Rembourser une partie seulement

Il arrive qu'un retrait se passe mal : il manque un pain dans le sac, on en a donné un autre que celui commandé. Rembourser toute la commande serait injuste des deux côtés — le bloc **Remboursement partiel**, en bas de la fiche d'une commande payée, sert exactement à ça.

![Le signalement du client et le bloc de remboursement partiel](shot:order-partial-refund)

Tu indiques la quantité à rendre sur chaque ligne, et le montant se calcule tout seul (la remise du client est déjà répartie dedans). Tu peux l'écraser : si tu décides d'offrir un pain plutôt que de le rembourser, tu baisses le montant, c'est toi qui décides.

Trois façons de rendre l'argent :

- **Carte / Bancontact** — le remboursement repart vers le moyen de paiement d'origine (2 à 5 jours ouvrables). Proposé seulement si la commande a été payée en ligne.
- **Portefeuille** — un avoir crédité tout de suite sur le portefeuille du mangeur. C'est le plus simple, et le client le réutilise à la fournée suivante.
- **Liquide** — tu rends les pièces toi-même. L'app n'en garde que la trace, pour que l'argent sorti du tiroir apparaisse dans le reporting.

Le client reçoit un e-mail avec le détail de ce qui lui est rendu, et un SMS court. La commande, elle, reste « prête » ou « récupérée » et reste comptée dans le chiffre d'affaires : elle a bien été livrée, on en a juste rendu un morceau. Tu peux rembourser plusieurs fois, tant que le cumul ne dépasse pas ce qui a été encaissé.

## Les signalements des clients

Un mangeur qui constate un problème en rentrant chez lui peut le signaler lui-même depuis « Mon compte », pendant les deux semaines qui suivent la fournée. Il coche les pains concernés et écrit ce qui s'est passé.

Vous recevez alors un e-mail à `boulangerie@les4sources.be`, et une pastille apparaît sur **Signalements** dans le menu de gauche. Rien n'est remboursé automatiquement : c'est vous qui décidez.

![La liste des signalements](shot:order-issues-index)

Depuis l'écran **Signalements**, tu ouvres la commande concernée : le message du client s'affiche sur sa fiche, et les quantités qu'il a signalées sont déjà pré-remplies dans le bloc de remboursement partiel. Rembourser clôt le signalement. S'il n'y a rien à rendre (pain remplacé sur place, malentendu), le bouton **Marquer traité sans rembourser** le referme aussi.
