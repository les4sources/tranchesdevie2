---
title: Les paramètres
order: 10
icon: "⚙️"
summary: Farines, moules, capacités du four, points de retrait, notifications, partenariats.
---

# Les paramètres

L'entrée **⚙️** de la nav regroupe tous les **réglages de fond**. On y touche
rarement, mais ce sont eux qui font tourner le reste correctement.

![Les paramètres](shot:settings-index)

## Ce qu'on y règle

| Réglage | À quoi ça sert |
| --- | --- |
| **Farines** | Les types de farine et la **limite de pétrin** de chacune (g). Sert au calcul des capacités. |
| **Types de moules** | Les moules et le **nombre d'unités** disponibles par fournée. |
| **Capacités de production** | La **capacité du four** (110 kg normal, 165 kg jour de marché). |
| **Ingrédients** | Les ingrédients utilisés par les produits. |
| **Points de retrait** | Les lieux où les clients récupèrent leurs commandes. |
| **Notifications** | Le message « commande prête » (SMS + email), éditable. |
| **Artisans** | Les boulangers et leurs **parts de revenu**. |
| **Partenariats** | Les regroupements de boulangers qui partagent leur revenu (voir [Revenus boulangers](revenus-boulangers)). |

## Points de retrait : deux textes, deux questions

Un point de retrait porte **deux champs de texte**, et ils ne racontent pas la même chose. C'est la confusion la plus facile à faire, alors autant la lever tout de suite.

| Champ | Répond à | Vu par le client |
| --- | --- | --- |
| **Description affichée au client** | « C'est où ? » | Au moment du **choix** : sur le checkout et dans le calendrier, sous le nom du lieu. |
| **Quand venir chercher sa commande** | « Quand est-ce que je viens ? » | **Après** la commande : sur l'écran de confirmation, dans l'email de confirmation et sur la page de sa commande. |

Le second champ existe parce que les horaires dépendent du lieu : aux 4 Sources on retire le jour de la cuisson à partir de 18h, au Marché d'Anhée ce sont les heures du marché. Écris la phrase que **tu** veux voir — rien n'est calculé automatiquement.

Laissé vide, il n'affiche rien du tout : ni bloc, ni titre orphelin. Le client voit alors seulement le nom du lieu et la phrase générique « Ta commande t'attendra le jour de cuisson indiqué ci-dessus ».

> **À faire une fois :** ce champ est **vide partout** au départ. Tant qu'il n'est pas rempli pour « Les 4 Sources », l'email de confirmation ne rappelle plus l'adresse de l'épicerie — c'est là qu'il faut la remettre, avec l'heure. Par exemple : « Épicerie aux 4 Sources — Fonds d'Ahinvaux 1, 5530 Yvoir. Le jour de la cuisson, à partir de 18h. »

## Prudence

Ces réglages impactent le calcul des capacités (four, pétrin, moules) et la
répartition des revenus. Une modification se répercute sur les fournées et la
compta : change-les en connaissance de cause, idéalement à froid (pas en plein
coup de feu un matin de fournée).

Les paramètres de revenus sont **historisés** : modifier un taux ne réécrit pas
le passé, il s'applique à partir de sa date.
