---
title: Les jours de cuisson
order: 3
icon: "🔥"
summary: Créer les fournées, suivre les capacités (four, pétrin, moules) et sortir les feuilles.
---

# Les jours de cuisson

Une **fournée** (ou « jour de cuisson »), c'est une date à laquelle on cuit.
Chez Tranches de Vie, c'est le **mardi** et le **vendredi**. Chaque fournée a
une **date limite de commande** (le dimanche et le mercredi à 18h) : après, on
ne peut plus commander pour cette date.

![La liste des jours de cuisson](shot:bake-days-index)

## Ouvrir une fournée

Bouton **Nouveau jour de cuisson**. Tu choisis la date ; la date limite se
calcule toute seule. Le lieu de retrait « Les 4 Sources » est coché
automatiquement.

## Une fournée réservée aux boulangers (marché, production spéciale)

Il arrive qu'on cuise **pour nous** : un marché, une commande spéciale, un
dépannage. On veut la fournée dans l'outil — pour la panification, les
capacités, la compta — mais **sans** que les clients puissent commander dessus.

C'est automatique : **une fournée posée un autre jour que le mardi ou le
vendredi n'apparaît jamais côté client.** Elle est absente du sélecteur de date
du panier, du bandeau « Prochaine fournée » du catalogue et de la liste des
prochaines dates du calendrier client — et rien ne peut être commandé dessus.

Concrètement, pour la fournée d'un marché le samedi :

1. **Nouveau jour de cuisson**, tu choisis la date du samedi.
2. Coche **Jour de marché (capacité four étendue)** si c'en est un : la jauge du
   four passe de 110 kg à 165 kg de farine, sinon tu serais bloquée trop tôt.
3. Encode les commandes toi-même depuis **Commandes → Nouvelle commande**, en
   choisissant cette fournée. C'est le seul chemin, puisque la boutique l'ignore.

Tu retrouves ensuite tout le reste comme d'habitude : les jauges de capacité, la
feuille d'émargement, la feuille compta.

> ⚠️ Cette confidentialité tient au **jour de la semaine**, pas à un réglage.
> Si un jour on ouvrait un troisième jour de cuisson hebdomadaire (le jeudi, par
> exemple), toutes les fournées déjà posées un jeudi deviendraient d'un coup
> commandables par les clients. À garder en tête avant de changer les jours de
> cuisson.

## Le détail d'une fournée : les capacités

Clique sur une fournée pour l'ouvrir. C'est ici que tu vérifies que la
production **tient dans la journée**. Trois jauges sont suivies :

![Le détail d'un jour de cuisson](shot:bake-day-show)

1. **Les moules** — chaque type de moule a un nombre d'unités disponibles. Quand
   c'est plein, on ne peut plus prendre de commande de ce format.
2. **Le pétrin** — le poids de pâte par type de farine. Chaque farine a une
   limite de pétrin (en grammes).
3. **Le four** — le poids total de farine par rapport à la capacité du four
   (110 kg en temps normal, 165 kg les jours de marché).

> Si une jauge est pleine, c'est le signal qu'il faut arrêter d'accepter des
> commandes sur cette fournée, ou ouvrir une capacité supplémentaire dans les
> **Paramètres**.

## Les feuilles à imprimer

Depuis une fournée, tu peux sortir :

- **La feuille d'émargement** d'un point de retrait — la liste des clients à
  cocher au fur et à mesure des retraits.
- **La feuille compta** — le récap chiffré de la journée (validation des
  montants boulangers / Les 4 Sources, au format de la feuille de Stéphanie).

## Annuler une fournée

Si on ne cuit pas un jour prévu : ouvre la fournée → **Annuler**. Une
confirmation t'est demandée, car les commandes rattachées sont impactées.
