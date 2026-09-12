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

## Les Pizza parties à préparer

Une Pizza party privée consomme des **pâtons** qu'il faut pétrir à l'avance,
mais elle n'a pas de fournée à elle. Quand une party se prépare sur la fournée
que tu regardes, un bloc **Pizza parties à préparer** apparaît en haut du détail,
avec la date de la party, son créneau, le nombre de personnes et le nom du
client.

La fournée qui prépare une party n'est pas toujours celle du jour même :

- party le **soir** d'un jour de fournée → cette fournée-là ;
- party à **midi**, ou un jour **sans fournée** (samedi, dimanche…) → la
  **fournée d'avant**, puisque la pâte ne peut pas être prête le matin même.

C'est pour ça que le bloc précise « à préparer pour le samedi 5 septembre »
quand la party n'a pas lieu le jour même : ne cherche pas un groupe qui
n'arrivera que plus tard.

> Les pâtons de party comptent dans le **pétrin** et dans les quantités de
> **farine**, mais **pas dans le four** ni dans les **moules** : les pizzas
> cuisent au four à bois, pas dans le four à pain de la fournée.

## Les feuilles à imprimer

Depuis une fournée, tu peux sortir :

- **La feuille d'émargement** d'un point de retrait — la liste des clients à
  cocher au fur et à mesure des retraits.
- **La feuille compta** — le récap chiffré de la journée (validation des
  montants boulangers / Les 4 Sources, au format de la feuille de Stéphanie).

## La feuille compta

![La feuille compta d'un jour de cuisson](shot:bake-day-sheet)

Le chiffre d'affaires affiché est un **CA facturé** : une commande compte dès qu'elle est livrée, qu'elle soit encaissée ou non. C'est ce qui fait entrer dans le total les commandes payées en liquide, celles des épiceries, de Semisto et des restaurants, et toutes celles que tu encodes toi-même depuis l'admin — elles naissent « non payées » et n'apparaissaient pas dans le CA avant. Les seules ventes qui restent dehors sont celles qui ne correspondent à aucun pain livré : les commandes annulées, les commandes du calendrier pas encore confirmées, et les paiements en ligne abandonnés en cours de route.

Le tableau **Ventes par format** liste chaque format vendu, pains d'abord, puis les **Pizza parties** sur leurs propres lignes avec un sous-total séparé. Le total du tableau égale toujours, au centime, la carte **CA total** en bas de page — si jamais un écart apparaissait, la feuille te le signalerait en rouge : ce serait un bug à remonter.

### Le bloc « Encaissement »

Ce bloc répartit le CA du jour selon le moyen de paiement que l'application a **réellement enregistré** : Stripe (paiement en ligne), portefeuille, et « aucun paiement enregistré ».

Cette dernière ligne demande une précision importante : **ce n'est pas un impayé.** L'application ne trace pas les encaissements en liquide — quand tu es payée en espèces au comptoir, rien ne vient le lui dire. Une commande réglée en liquide se retrouve donc forcément dans cette ligne. Elle répond à la question « par quel canal l'argent est-il passé, d'après ce que l'app sait ? », et surtout pas à « qui me doit encore de l'argent ? ». Pour cette seconde question, c'est la facturation des clients professionnels qui fait foi.

## Annuler une fournée

Si on ne cuit pas un jour prévu : ouvre la fournée → **Annuler**. Une
confirmation t'est demandée, car les commandes rattachées sont impactées.
