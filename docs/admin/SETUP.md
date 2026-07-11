# Configurer la documentation dans GitBook

> Ce fichier s'adresse à **l'équipe technique**. Il n'est pas destiné aux
> boulangers. Il explique comment brancher le dépôt Git à GitBook pour que
> la doc se publie automatiquement.

## Pré-requis

- Un compte GitBook (offre gratuite suffisante pour commencer).
- Les droits `write` sur le dépôt `les4sources/tranchesdevie2`.
- L'installation de l'application GitHub GitBook sur l'organisation
  `les4sources` (bouton *Install* depuis GitBook).

## Étape 1 — Créer l'espace GitBook

1. Se connecter sur https://app.gitbook.com.
2. **New space** → nommer `Guide boulanger — Tranches de Vie`.
3. Le mettre dans une **Collection** dédiée (option payante) ou le
   laisser en espace autonome.

## Étape 2 — Brancher le dépôt via Git Sync

1. Dans l'espace, ouvrir **Sync → Configure GitHub Sync**.
2. Sélectionner :
   - **Organization** : `les4sources`
   - **Repository** : `tranchesdevie2`
   - **Branch** : `main`
   - **Project directory** : `docs/admin/`
3. **Sync direction** : *bidirectionnelle*. Cela signifie que :
   - un push Git → GitBook se met à jour ;
   - une édition dans GitBook → GitBook pousse un commit sur `main`
     (via un compte de service GitBook, auteur `gitbook-com[bot]`).
4. **Preserve existing content** : *no*. Le repo est la source de vérité.
5. Cliquer **Sync**.

GitBook lit alors :
- `docs/admin/README.md` comme page d'accueil ;
- `docs/admin/SUMMARY.md` comme table des matières ;
- toutes les pages `.md` référencées.

La configuration précise vient du fichier `.gitbook.yaml` à la racine.

## Étape 3 — Publier

Dans l'espace GitBook, cliquer **Publish** :
- **Public** si vous voulez rendre la doc accessible à tous par un lien
  simple (recommandé pour de la doc utilisateur ne contenant pas
  d'information sensible) ;
- **Public unlisted** si vous voulez qu'un lien direct suffise mais que
  l'espace ne soit pas indexé publiquement.

Notez le domaine, par exemple `tranchesdevie.gitbook.io/guide-boulanger/`.

## Étape 4 — Vérifier que la resynchro fonctionne

Créez un commit trivial dans `docs/admin/` :

```bash
echo "" >> docs/admin/README.md
git commit -am "test sync gitbook"
git push
```

Sous 30 à 60 secondes, l'espace GitBook doit refléter le changement.

## Comment le pipeline de captures d'écran s'insère

Voir `.github/workflows/docs-screenshots.yml`. À chaque push touchant
l'admin ou la doc :

1. GitHub Actions démarre une base de données Postgres jetable, remplit
   la base avec les seeds démo (`db/seeds/demo.rb`), démarre un serveur
   Rails, lance Playwright pour prendre toutes les captures listées dans
   `script/docs/screenshot_manifest.yml`, puis les sauve dans
   `docs/admin/images/`.
2. Si des captures ont changé, une **pull request automatique** est ouverte
   (branche `bot/docs-screenshots-refresh`). Elle passe par une relecture
   humaine avant merge — jamais de commit direct sur `main`.
3. Une fois la PR mergée, GitBook Git Sync récupère les nouvelles
   captures et met la doc en ligne à jour.

## MCP GitBook — pour aller plus loin

Le MCP GitBook (publié fin 2025) permet à un agent d'**interroger et
d'éditer** la doc dans le cadre d'une conversation :

- lire la doc pour répondre à une question du boulanger ;
- proposer une refonte d'une page depuis Slack ou une session Claude ;
- suggérer des cross-links vers d'autres pages.

Il n'est **pas nécessaire** pour la synchronisation continue — Git Sync
s'en charge. Si vous voulez l'activer, ajoutez-le comme MCP server dans
votre configuration Claude (voir la doc GitBook), en fournissant un token
d'API GitBook avec les droits lecture/écriture sur l'espace « Guide
boulanger ».

## Coûts

- **GitBook** : plan Community (gratuit) suffit pour un espace unique.
  Le plan Plus (~8 €/mois/utilisateur éditeur) débloque les analytics et
  la recherche améliorée.
- **GitHub Actions** : le job de captures tourne en 5-8 min. Sur un projet
  privé, l'offre gratuite couvre largement l'usage attendu.
- **Stockage** : les PNG font ~100-300 KB chacun ; ~30 images totales →
  ~10 MB dans le repo, négligeable.
