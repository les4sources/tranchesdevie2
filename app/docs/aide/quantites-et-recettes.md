---
title: "Régler les quantités et les recettes"
order: 11
icon: "⚖️"
summary: "Changer la quantité de pâte d'un pain, ajuster les ratios de panification d'une farine, retirer un produit : ce que vous pouvez faire vous-mêmes."
---

# Régler les quantités et les recettes

Tout ce qui suit, **vous pouvez le faire vous-mêmes**. Pas besoin d'attendre Michael, et pas besoin de toucher à la base de données. C'est le point de cette page : si un jour personne n'est là, celui qui reste doit pouvoir faire le pain.

Chaque réglage est suivi de **comment vérifier** que le changement a bien pris. C'est la partie qu'on oublie, et c'est celle qui évite de découvrir une erreur un mardi matin.

## Changer la quantité de pâte d'un pain

C'est le réglage le plus fréquent : « on met un peu plus de pâte dans les grands ».

**Où ça se passe** : **Produits** → cliquez sur le produit → cliquez sur la variante concernée → **Modifier**. Le champ s'appelle **Quantité de pâte requise**, en grammes.

![La fiche d'une variante : le champ « Quantité de pâte requise »](shot:product-variant-edit)

**Ce que ça change**, dès l'enregistrement et pour tous les jours de cuisson à venir :

- le **poids de pâte** total du jour, affiché sur la page du jour de cuisson ;
- la **panification** — farine, eau, sel, levain — puisque tout se calcule à partir de la pâte ;
- le **remplissage du pétrin et du four**, donc les pourcentages de capacité.

> **Attention.** La quantité de pâte n'est **pas** le poids du pain cuit. C'est le poids de pâte crue que le pain consomme. Si vous saisissez le poids cuit, toutes les quantités du jour seront sous-évaluées.

Ce que ça ne change **pas** : le prix de vente, le prix coûtant, et les commandes **déjà passées** gardent leur montant. Seules les quantités à produire bougent.

## Ajuster les ratios de panification d'une farine

**Où ça se passe** : **Paramètres** → **Farines** → la farine concernée → **Modifier**. Le bloc s'appelle **Ratio de panification**.

![Le formulaire d'une farine : le bloc « Ratio de panification »](shot:settings-flour-edit)

### La convention, à lire avant de toucher aux chiffres

**Les quatre ratios sont des fractions de la PÂTE, pas de la farine.** C'est la décision prise en réunion le 25 août 2026, et c'est la seule règle à retenir.

Concrètement, pour 10 kg de pâte avec un ratio farine de `0,532` : il faut **5,32 kg de farine**. Pas 10 kg de farine plus le reste.

C'est contre-intuitif si vous avez l'habitude du boulanger classique, où l'eau et le sel s'expriment **en pourcentage de la farine**. Ici, tout se rapporte à la pâte, pour les quatre ingrédients — farine, eau, sel, levain.

### Ce que la somme des quatre vous dit

Le formulaire affiche la **somme** des quatre ratios pendant que vous tapez.

- **Somme = 1,000** : la recette boucle exactement.
- **Somme > 1,000** : l'excédent est votre **marge de pétrissage** — la perte au façonnage. Un ratio à `1,055` veut dire 5,5 % de marge. C'est normal et voulu.
- **Somme < 1,000** : **il manquera de la matière**. La fournée ne sortira pas le poids annoncé.

L'application ne vous impose rien : elle affiche la somme et vous laisse décider. C'est un choix de boulanger, pas une contrainte de logiciel.

### Le type de levain

Chaque farine porte aussi son **type de levain** — froment ou seigle. C'est lui qui fait apparaître deux totaux distincts en bas du tableau de panification. Si vous changez ce type, le levain de cette farine bascule d'un total à l'autre.

## Retirer un pain, pour un jour ou pour un temps

Trois manières, de la plus fine à la plus radicale.

### 1. Le retirer d'un jour de la semaine

**Produits** → la variante → **Modifier** → le bloc **Restriction par jour**. Cochez les jours où ce format est proposé. Ne rien cocher = disponible tous les jours de cuisson.

C'est le bon outil pour « ce pain-là, on ne le fait que le vendredi ».

### 2. Le désactiver complètement

Sur la même page, décochez **Actif**. Le produit disparaît du catalogue et personne ne peut plus le commander. Les commandes déjà passées ne bougent pas.

C'est le bon outil pour « on arrête ce pain ».

### 3. Pour une période précise — pas encore faisable seul

> **À savoir.** L'application sait techniquement rendre une variante indisponible **entre deux dates**, mais **cet écran n'existe pas encore** : le réglage n'est accessible ni depuis Produits, ni depuis Paramètres.
>
> En attendant, pour une absence ponctuelle (« pas de pain aux figues pendant les vacances »), utilisez la **restriction par jour** ou la **désactivation**, puis remettez comme avant au retour. Si le besoin devient fréquent, dites-le : c'est un écran à ajouter, pas une refonte.

## Vérifier qu'un réglage a bien pris

C'est la méthode utilisée en réunion, et elle marche pour n'importe lequel des réglages ci-dessus.

1. **Créez un jour de cuisson futur**, ou prenez-en un qui n'a encore aucune commande.
2. **Encodez une commande de test** : Commandes → **Nouvelle commande**, un client quelconque, ce jour-là, une quantité ronde du produit concerné — 10, c'est parfait, les calculs mentaux sont plus simples.
3. **Ouvrez la page du jour de cuisson** et comparez :
   - la ligne **Quantité totale de pâte** doit valoir `quantité commandée × quantité de pâte de la variante` ;
   - dans le tableau **Panification**, la colonne de la farine concernée doit valoir `pâte × ratio`.
4. **Supprimez la commande de test** quand vous avez vérifié. Une commande de test oubliée fausse la feuille compta du jour.

**Un exemple complet.** 10 grands pains à 800 g de pâte, farine 100 % froment T80 dont le ratio farine vaut 0,532 :

- pâte : `10 × 800 g` = **8 000 g**, soit 8 kg ;
- farine : `8 kg × 0,532` = **4,26 kg** ;
- si vous lisez ça, le réglage est bon.

> **Le brouillon, encore mieux.** Si un jour de cuisson peut être marqué **Brouillon**, utilisez-le pour vos tests : les calculs fonctionnent normalement, mais rien n'entre dans la comptabilité — vous n'avez même pas à penser à supprimer la commande.

## Ce qui n'est PAS réglable ici

Pour éviter de chercher :

- **le prix de vente** d'une variante se règle sur la même page, mais c'est un autre champ (**Prix**) ;
- **le prix coûtant** est un historique, sur la fiche de la variante : on n'écrase jamais un coûtant, on ajoute un palier avec sa date ;
- **la capacité du four et du pétrin** : Paramètres → **Capacités de production**, et la limite du pétrin est portée par chaque farine ;
- **les moules** : Paramètres → **Types de moules**, et l'association moule ↔ variante se fait sur la variante.
