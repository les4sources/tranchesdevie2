---
title: La facturation
order: 7
icon: "💳"
summary: Retrouver les paiements et générer les factures PDF (commande ou période).
---

# La facturation

L'onglet **Facturation** regroupe le suivi des **paiements** et la génération
des **factures**.

## Les paiements

Chaque commande payée en ligne est liée à un **paiement** Stripe (carte,
Bancontact, Apple Pay, Google Pay). Tu peux retrouver l'état d'un paiement et le
rapprocher de sa commande.

Les commandes payées avec le **portefeuille** du client apparaissent aussi comme
réglées, mais via le solde prépayé plutôt que Stripe.

## Marquer les commandes facturées et payées

L'écran **Facturation mensuelle** liste, mois par mois, les commandes des clients professionnels. Chaque ligne porte deux pastilles : où en est le **paiement**, et où en est la **facturation**.

Coche les commandes concernées — la case « Tout sélectionner » d'un client coche toutes ses lignes — puis utilise la barre d'actions en bas de l'écran :

- **Marquer comme facturées** — au moment où la facture part chez le client.
- **Marquer comme payées** — quand l'argent arrive. Choisis la **date de paiement** avant de valider ; elle sert au rapprochement comptable. Une commande déjà payée en ligne garde sa date d'encaissement réelle.
- **Annuler la facturation** — remet les commandes en « non facturée », en cas d'erreur.

> Ces deux marquages sont indépendants du **statut de la commande** (prête, récupérée…) : facturer n'est pas cuire, encaisser n'est pas remettre le pain.

## Repérer les montants qui ne collent pas

Le montant d'une commande est un champ à part : il peut avoir été saisi à la main, et donc ne plus correspondre au détail des articles. Quand c'est le cas, le relevé du client affiche un sous-total qui ne se déduit pas de ses propres lignes.

Le bouton **Écarts de montant**, en haut de l'écran Facturation, dresse la liste des commandes concernées.

![Les écarts de montant à relire](shot:billing-discrepancies)

Deux familles :

- **Montant au-dessus du détail** — à corriger : aucune remise ne rend une commande plus chère que la somme de ses lignes. Sur le relevé du client, l'écart apparaît en « Ajustement ».
- **Montant sous le détail, sans remise applicable** — à relire : le client n'appartient à aucun groupe de remise, donc rien dans le barème n'explique la réduction.

Chaque ligne renvoie vers la commande et vers son formulaire de correction. Le bouton **Télécharger le PDF** produit la même liste sur papier, pour faire le point.

> Les commandes sous leur détail chez un client qui bénéficie d'une remise de groupe ne sont pas listées : le taux appliqué le jour de la commande n'est pas conservé, les comparer au barème d'aujourd'hui ne donnerait que de fausses alertes. Leur nombre est affiché en haut de l'écran.

## Générer une facture PDF

Un client a besoin d'une facture ? Deux cas :

- **Facture d'une commande** — le PDF d'une commande précise.
- **Facture d'une période** — un ensemble de commandes sur une période (par ex.
  toutes les commandes d'un mois pour un même client). Pratique pour les clients
  réguliers ou les factures mensuelles.

> Une commande n'a besoin d'une facture que si le client la demande. Le champ
> « facture requise » de la commande le signale.

## Et pour les chiffres globaux ?

Pour les totaux, les remboursements, les payouts et la répartition des revenus,
va voir le [Reporting](reporting) et les [Revenus boulangers](revenus-boulangers).
