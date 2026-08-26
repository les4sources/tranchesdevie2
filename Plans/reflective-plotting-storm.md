# Plan — Connexion client par SMS **ou** e-mail, à parité

## Context

Aujourd'hui le login client est **entièrement ancré sur le numéro de téléphone** :

- `Customers::SessionsController#create` normalise/valide un GSM, puis `Customer.find_or_create_by(phone_e164:)` (sessions_controller.rb:8-22).
- L'OTP est stocké dans `PhoneVerification`, dont la colonne `phone_e164` est **NOT NULL** et validée `presence` (phone_verification.rb:6). Le code, le TTL (15 min), le compteur de tentatives (5) et le cooldown (20 s) sont tous indexés par téléphone.
- L'e-mail n'est qu'un **secours** : il ne marche que pour un client existant ayant déjà une adresse au dossier (`allow_email_entry: false` au login), et il est présenté comme un lien discret « Tu ne reçois pas le SMS ? » sous le champ OTP (new.html.erb:75-83).
- En base, **`email` n'est pas unique** (customer.rb:13 — seul `phone_e164` l'est).

Problème réel : des clients ne reçoivent pas le SMS et restent bloqués. On veut que le client puisse se connecter **soit par SMS, soit par e-mail, au même niveau**, avec une UX impeccable.

**Décisions prises avec Michael :**
1. **Un seul champ « Téléphone ou e-mail »** : on détecte le type saisi et on envoie le code par le bon canal. Parité totale (pas de canal « principal »).
2. **E-mail inconnu → saisir + enregistrer** : si le client choisit/saisit un e-mail qu'on ne connaît pas, on envoie le code à cette adresse et on l'**enregistre sur le compte** (même pattern que le checkout).

**Défauts d'implémentation retenus (à valider) :**
- L'e-mail devient l'**identité alternative** : on normalise en minuscules et on ajoute une unicité applicative (insensible à la casse). L'index DB unique n'est posé qu'**après audit des doublons existants** (cf. § Données).
- Un client qui se connecte par e-mail **sans GSM** est autorisé (conséquence de la parité). Il ne recevra pas les SMS « commande prête » — voir § Conséquences.

## Design — un OTP « agnostique au canal »

Le cœur du changement : la vérification OTP ne doit plus être rattachée *uniquement* au téléphone, mais à un **identifiant** qui est soit un GSM, soit un e-mail.

**Classification de l'identifiant (nouveau helper, dans `OtpService`)** :
- contient `@` / matche `URI::MailTo::EMAIL_REGEXP` → **e-mail** (canal e-mail) ;
- sinon → on tente la normalisation GSM existante (`normalize_phone` → E.164) → **téléphone** (canal SMS) ;
- ni l'un ni l'autre → erreur « Entre un numéro de GSM ou une adresse e-mail valide ».

## Changements par zone

### 1. Modèle de vérification — `PhoneVerification` (+ migration)
Fichiers : `app/models/phone_verification.rb`, nouvelle migration, `db/schema.rb`.
- Migration : ajouter `email:string` (nullable, indexé) ; rendre `phone_e164` **nullable**.
- Validation : exiger **au moins un** des deux (`phone_e164` ou `email`) présent, plus le format e-mail si présent.
- Généraliser les helpers de classe à une **clé de canal** plutôt qu'au seul téléphone :
  - `for_identifier(phone: nil, email: nil)` (remplace/complète `for_phone`),
  - `create_for(phone: nil, email: nil)` (remplace/complète `create_for_phone`),
  - `can_send_new?(phone: nil, email: nil)` (cooldown par identifiant).
- Garder `for_phone`/`create_for_phone` comme alias fins pour limiter le blast-radius, ou migrer tous les appelants (peu nombreux : `OtpService`).
- (Cosmétique, hors scope) le nom `PhoneVerification` reste — renommer serait du churn pur.

### 2. Service OTP — `app/services/otp_service.rb`
- Nouvelle API agnostique : `send_code(identifier:, allow_signup: true)` qui classe l'identifiant, crée/réutilise une vérification **par identifiant** (réutilise un code actif s'il existe, comme aujourd'hui pour faire matcher SMS et e-mail), et envoie via le bon canal :
  - **téléphone** → `send_otp_sms` (inchangé).
  - **e-mail** → `AuthMailer.otp(email, code, customer:)`. Résout le client par e-mail (`find_by` insensible casse). L'adresse saisie EST l'adresse d'envoi (cas « saisir + enregistrer »).
- `verify_code(identifier:, code:)` : look-up par identifiant (phone OU email), même logique d'expiration/tentatives/destruction qu'aujourd'hui.
- Conserver `send_otp`/`verify_otp` en **façades** déléguant à la nouvelle API pour ne pas casser les appelants existants (checkout, specs, helpers de test).
- Réutiliser : `URI::MailTo::EMAIL_REGEXP` (déjà utilisé otp_service.rb:66), `AuthMailer.otp` (auth_mailer.rb), `send_otp_sms` (otp_service.rb:118).

### 3. Contrôleur de session — `app/controllers/customers/sessions_controller.rb`
- Accepter un seul champ `params[:identifier]` (rétro-compat : retomber sur `params[:phone_e164]` si présent).
- Étape « envoi » : `OtpService.send_code(identifier:)` ; mémoriser l'identifiant en session (`session[:login_identifier]`) au lieu de `phone_e164` seul.
- Étape « vérification » : `OtpService.verify_code(identifier:, code:)`. Sur succès, **résoudre le client** :
  - identifiant = GSM → `Customer.find_or_create_by(phone_e164:)` (comportement actuel).
  - identifiant = e-mail → `Customer.find_by("lower(email)=?", email)` ; sinon créer un client avec cet e-mail. Si l'identifiant initial était un GSM mais qu'un e-mail a été saisi en cours de route (cas « pas d'e-mail au dossier »), **enregistrer l'e-mail** sur le client résolu.
  - Doublons d'e-mail hérités : `.order(:created_at).first` + `Rails.logger.warn` (défensif — voir § Données).
- Garder `normalize_phone` / `valid_e164?` (réutilisés par le helper de classification).
- **Caveat `first_name` (préexistant)** : `Customer` valide `first_name` en présence (customer.rb:12), donc `find_or_create_by` crée un enregistrement **non sauvé** (id nil) pour un tout nouveau compte sans prénom — déjà vrai aujourd'hui pour le GSM. À gérer : soit traiter le cas (rediriger vers complétion de profil), soit confirmer que les nouveaux comptes passent toujours par le checkout (qui collecte le prénom). À vérifier en test.

### 4. Vue de connexion — `app/views/customers/sessions/new.html.erb`
- Un seul champ **« Téléphone ou e-mail »** + un bouton unique **« Recevoir mon code »** (fin du modèle « SMS d'abord, e-mail en secours »).
- Indice dynamique du canal détecté (« 📱 par SMS » / « ✉️ par e-mail ») sous le champ pendant la saisie.
- Réécrire l'encart bleu d'info (actuellement 100 % « numéro de téléphone ») pour refléter les deux canaux.
- Conserver le style existant (carte blanche `bg-white rounded-lg shadow-sm border`, inputs `rounded-md`, boutons). Étape OTP (champ 6 chiffres + « Vérifier le code ») inchangée dans sa structure.

### 5. Stimulus — `app/javascript/controllers/`
- `customer_session_controller.js` : un seul `sendCode()` (remplace `sendOTP`/`sendOTPByEmail`), POST `identifier` (+ `otp_code` à la vérif). Conserver le pattern fetch + DOMParser existant ; afficher le canal détecté.
- **`phone_input_controller.js` (point UX critique)** : aujourd'hui il force le format E.164 et préfixe `+32` à la saisie — il **massacrerait un e-mail**. Le rendre conditionnel : dès que la valeur ressemble à un e-mail (présence d'une lettre/`@`), désactiver le formatage et masquer le drapeau ; ne formater que quand ça ressemble à un numéro.

### 6. Checkout — `app/controllers/checkout_controller.rb`
- `verify_phone`/`verify_otp` partagent `OtpService`. Les façades (§2) gardent le checkout fonctionnel sans changement immédiat.
- **Recommandé (cohérence UX)** : aligner le checkout sur le même champ unique « téléphone ou e-mail ». Peut être fait dans la foulée ou en suivi — à décider. Par défaut je l'inclus pour ne pas laisser deux UX divergentes.

### 7. Rate limiting — `config/initializers/rack_attack.rb`
- Aujourd'hui seul `/checkout/verify_phone` est throttlé ; `/connexion` ne l'est pas. Ajouter des throttles sur `POST /connexion` par **identifiant** et par **IP** (mêmes seuils que checkout : 5/60s par cible, 8/60s par IP).

## Données — unicité e-mail & doublons hérités
- Ajouter à `Customer` : normalisation `before_validation` (`email = email.strip.downcase` si présent) + `validates :email, uniqueness: { case_sensitive: false, allow_nil: true }`.
- **Avant** de poser un index unique DB : auditer les doublons existants
  `Customer.where.not(email: [nil, ""]).group("lower(email)").having("count(*) > 1")`.
  - Aucun doublon → ajouter l'index unique (insensible casse).
  - Doublons présents → ne pas poser l'index dur ; rester sur la résolution défensive (`order(:created_at).first` + warn) et remonter la liste à Michael pour dédoublonnage manuel.

## Conséquences à connaître
- **Compte e-mail sans GSM** : pas de SMS « commande prête ». Les notifications passent déjà par `sms_enabled?` (customer.rb:19, vérifie présence du GSM) donc pas de crash ; mais ce client ne sera pas prévenu par SMS. Suivi possible : bascule e-mail pour la notif « prête » quand le GSM manque (hors scope de ce plan).

## Vérification
1. **Tests RSpec** (le suite tourne via `bundle exec rspec`) :
   - Nouveau `spec/requests/customers/sessions_spec.rb` : login par GSM (SMS), par e-mail (client existant avec e-mail), par e-mail inconnu → création + sauvegarde, GSM connu sans e-mail → saisie e-mail → envoi + sauvegarde, identifiant invalide, cooldown, e-mail dupliqué (résolution défensive).
   - Adapter `spec/services/otp_service_spec.rb` à la nouvelle API (garder la couverture e-mail existante via les façades) ; ajouter la couverture canal SMS (stub `HTTParty.post` comme dans `spec/services/sms_service_spec.rb:9-20`).
   - Vérifier que les helpers `authenticate_customer` de `spec/requests/customers/account_spec.rb:6-12` et `calendar_spec.rb` (qui stubbent `OtpService.send_otp`/`verify_otp`) passent toujours grâce aux façades.
   - `spec/mailers/auth_mailer_spec.rb` reste valide (envoi OTP inchangé).
2. **Vérification visuelle réelle** (obligatoire, skill **Interceptor**) : ouvrir `/connexion`, tester (a) saisie GSM → code SMS (loggé en dev), (b) saisie e-mail → code e-mail (letter_opener en dev), (c) e-mail inconnu → champ + sauvegarde, sur desktop **et** mobile. Confirmer qu'aucun `+32` ne se colle quand on tape un e-mail.
3. **Garde-fous** : `bin/rubocop` + `bin/brakeman --no-pager` (CI les exige sur push `main`).

## Hors scope / suivis
- Renommage `PhoneVerification` → nom générique (cosmétique).
- Notification « commande prête » par e-mail pour les comptes sans GSM.
- Refonte complète de l'UX checkout au-delà de l'alignement du champ unique.
