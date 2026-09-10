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
