# Rembourser un client

Un client ne pourra pas venir chercher sa commande ? Il y a eu une erreur
de facturation ? Vous devez lui rembourser son argent.

Il y a **deux façons** de rembourser, selon comment le client a payé :

1. Si la commande a été **payée en ligne par carte / Bancontact / Apple Pay
   / Google Pay** → le remboursement passe par Stripe et arrive sur la
   carte du client sous 3 à 10 jours.
2. Si le client a payé **avec son portefeuille** (crédit prépayé), le
   montant retourne dans son portefeuille immédiatement.

L'espace d'administration s'occupe **automatiquement** de choisir la bonne
méthode. Vous n'avez qu'à cliquer sur *Rembourser*.

## À savoir avant de rembourser

Le remboursement est **irréversible**. Une fois lancé, on ne peut pas
faire marche arrière. Vérifiez avant de cliquer :

- que c'est **la bonne commande** (le numéro et le nom du client) ;
- que vous voulez rembourser **la totalité** — un remboursement partiel
  n'est pas possible depuis cette action.

Le remboursement **n'est possible que si** :

- la commande est actuellement **« Payée »** (pas encore prête, pas encore
  récupérée) ;
- **la date limite du jour de cuisson n'est pas passée**. Après clôture,
  vous êtes déjà engagé côté production ; le remboursement doit alors
  passer par un autre canal (échange avec le client, geste commercial…).

Si l'une de ces deux conditions n'est pas remplie, le bouton **Rembourser
n'apparaîtra pas** sur la fiche de la commande.

## Pas à pas

### 1. Trouver la commande

Cliquez sur **Commandes** dans le menu, puis sur la commande concernée
dans la liste. Vous pouvez aussi passer par la fiche du client ([Lire une
fiche mangeur](../mangeurs/consulter-un-profil.md)) : ses commandes y
sont listées.

### 2. Ouvrir la fiche de la commande

![Fiche d'une commande, panneau Actions](../images/order-show-actions.png)

Sur la droite, le panneau **Actions** liste tout ce que vous pouvez faire.
Si le bouton rouge **« Rembourser »** est présent, vous pouvez y aller.

### 3. Cliquer sur « Rembourser »

Une boîte de dialogue s'affiche pour vous demander confirmation :

> **Rembourser intégralement cette commande ? Le remboursement est
> irréversible.**

Prenez une seconde pour vérifier que vous êtes bien sur la bonne commande.

Cliquez **OK** pour lancer le remboursement.

### 4. Ce qui se passe ensuite

L'espace d'administration effectue en enchaînement, en une seule fois :

1. **Le remboursement financier** : soit sur la carte du client (Stripe),
   soit sur son portefeuille selon comment il a payé.
2. **La mise à jour du statut** : la commande passe en « Remboursée » et
   elle est retirée de la production du jour — la capacité de la fournée
   est libérée automatiquement.
3. **Un SMS au client** pour l'informer que sa commande a été annulée et
   qu'il a été remboursé.

Vous retombez sur la fiche de la commande, avec le nouveau statut affiché.

## Cas particuliers

### Le bouton « Rembourser » n'apparaît pas

Deux raisons possibles :

- **La commande n'est plus dans un état remboursable** : elle est déjà
  prête, récupérée, non venue, ou déjà remboursée. Dans ces cas-là, aucun
  remboursement automatique n'est possible.
- **La clôture du jour de cuisson est passée**. À ce moment-là, la
  production est déjà lancée. Contactez l'équipe technique si un
  remboursement exceptionnel doit être fait à la main.

### Le client a payé en cash et je veux quand même le rembourser

Le bouton « Rembourser » ne gère que les paiements électroniques et le
portefeuille. Pour un cash au comptoir, remettez l'argent en main propre
puis passez la commande en **« Non payée »** via
[Modifier une commande](modifier-une-commande.md), ou annulez-la
manuellement selon votre pratique de caisse.

### Le remboursement Stripe est en attente

C'est normal : Stripe met **3 à 10 jours** pour renvoyer l'argent sur la
carte du client. De votre côté, la commande est déjà passée en
« Remboursée » et vous n'avez plus rien à faire.

## Pour aller plus loin

- [Suivre les remboursements](../reporting/suivre-les-remboursements.md) —
  le tableau de bord de tous les remboursements du mois.
- [Comprendre le portefeuille](../mangeurs/gerer-le-portefeuille.md) — si
  vous voulez comprendre la logique du crédit prépayé.
