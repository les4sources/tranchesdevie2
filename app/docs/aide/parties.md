---
title: Les Pizza Parties
order: 6
icon: "🍕"
summary: "Comment une party privée est réservée en ligne, où la retrouver, et comment gérer les parties publiques et les créneaux."
---

# Les Pizza Parties

L'onglet **Parties** gère les **pizza parties**. Il y a deux familles :

- **Les parties publiques** — des événements ouverts aux inscriptions (avec une
  capacité et une date limite d'inscription).
- **Les parties privées** — réservées **en ligne** par un groupe, sans que
  personne n'intervienne. C'est le cas le plus fréquent, et celui qu'il faut
  bien comprendre : **personne n'est prévenu automatiquement**, la réservation
  attend dans l'admin qu'on aille la voir.

![La liste des parties](shot:parties-index)

## Comment un client réserve une party privée

Tout se passe sur la page publique de réservation, sans nous. Le client :

1. Ouvre la page **Pizza Party privée** du site.
2. Choisit une **date** dans le calendrier — seuls les jours disponibles sont
   cliquables.
3. Choisit le **créneau** (midi ou soir) et le **nombre de personnes**.
4. Le **forfait de 40 €** s'ajoute tout seul au panier.
5. S'**identifie**, par son GSM **ou** par son adresse email.
6. **Paie en ligne**.

Le créneau n'est **définitivement bloqué qu'une fois le paiement abouti**. Tant
que le client n'a pas payé, sa réservation n'est pas acquise et le créneau reste
proposé aux autres.

### Les tarifs

- **5 € par personne** — une personne = un pâton.
- **40 € de forfait**, une seule fois par party, quel que soit le nombre de
  convives. Il couvre la préparation, le bois, le matériel et la mise en place.

### Pourquoi une date n'est pas disponible

Le calendrier ferme un créneau tout seul dans quatre cas :

1. **Moins de 7 jours** avant la date — il faut ce délai pour préparer les
   pâtons.
2. Le créneau a été **bloqué par l'équipe** (voir plus bas).
3. Une **party publique** occupe déjà cette soirée — les parties publiques sont
   toujours en soirée, donc elles ne ferment que le créneau du soir.
4. La **capacité de parties privées** sur ce créneau est atteinte. Ce nombre se
   règle dans **Paramètres → Production**.

### Le four sera-t-il chaud ?

Les **mardis et vendredis** sont nos jours de boulangerie : le four est **déjà
chaud**, le groupe enfourne directement. Les autres jours, le groupe doit
prévoir **environ 3 heures de chauffe** avant de pouvoir enfourner. Le client
voit cette information au moment où il choisit sa date.

## Ce que le client reçoit — et ce qu'il ne reçoit pas

Il reçoit :

- une **page de confirmation** avec son numéro de commande ;
- un **email de confirmation** ;
- sa réservation **visible dans son compte**.

Il ne reçoit **pas** :

- de **SMS** — aucune commande n'en déclenche à la réservation ;
- de **rappel** à l'approche de la date. Si un rappel est utile, il faut le
  faire à la main.

## Où retrouver une réservation privée

Deux endroits :

- **Parties** → section **Réservations privées à venir** : la date, le créneau
  et le client.
- **Commandes** : la commande elle-même, avec le détail et le montant payé.

> ⚠️ **Une party privée n'apparaît sur aucune feuille de production.** Elle n'a
> pas de fournée à elle, et personne n'est prévenu quand elle arrive : si
> personne n'ouvre l'onglet Parties, une réservation peut rester invisible
> jusqu'au jour J. Prends l'habitude d'y jeter un œil.

## Ce que le formulaire ne demande pas

Le formulaire de réservation ne collecte **que** la date, le créneau et le
nombre de personnes. Il ne demande **ni l'heure d'arrivée, ni l'occasion, ni les
allergies, ni qui s'occupe du feu**.

Pour tout le reste, **il faut contacter le client**. Et attention : un client qui
s'est identifié **par son email n'a aucun numéro de téléphone enregistré** —
l'email est alors le seul moyen de le joindre.

## Créer une party publique

1. Bouton **Nouvel événement public**.
2. Renseigne le **titre**, la **date**, la **capacité** (nombre de places) et la
   **date limite d'inscription**.
3. Enregistre. L'événement s'ouvre alors aux inscriptions.

Tu peux **Modifier** ou **Supprimer** une party depuis la liste.

## Bloquer un créneau de party privée

Pour empêcher une réservation sur une date (four indisponible, équipe absente,
lieu déjà pris), **bloque le créneau** : il disparaît alors du calendrier du
client. La section **Créneaux privés (blocages)** sert exactement à ça — tu
ajoutes une date + un créneau, et il devient indisponible.

Un blocage sans créneau précisé ferme **toute la journée**.

## Compta des parties

La comptabilité des parties (barèmes privé / public, répartition
boulangers / Les 4 Sources) est un sujet à part. Les chiffres se retrouvent dans
le [Reporting](reporting) → **Pizza parties**.
