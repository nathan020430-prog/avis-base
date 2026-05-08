# Avis Basé — De PWA à App Store / Play Store

Ce document explique comment publier l'app Avis Basé sur l'App Store iOS et le Play Store Android **sans installer Node.js, Xcode ou Android Studio en local**.

---

## Ce qui est déjà fait (côté code)

- ✅ `manifest.json` — métadonnées de l'app (nom, couleurs, icônes, raccourcis)
- ✅ `sw.js` — service worker (offline + mises à jour automatiques)
- ✅ `icon.svg` — icône maître (vectorielle)
- ✅ Meta tags PWA + iOS dans `index.html`
- ✅ Enregistrement du service worker au chargement
- ✅ Headers Cloudflare configurés (`_headers`)

L'app est **déjà installable** depuis Chrome / Safari sur mobile (icône "Ajouter à l'écran d'accueil"). Pour la publier sur les stores, suis les étapes ci-dessous.

---

## Étape 1 — Déployer le site avec les nouveaux fichiers

```bash
# Pousse les changements sur Cloudflare Pages (via Git ou wrangler)
# Les fichiers nouveaux/modifiés :
#   - manifest.json
#   - sw.js
#   - icon.svg
#   - index.html
#   - _headers
```

Vérifie ensuite sur https://avis-base.com :

1. Ouvre les DevTools Chrome (F12) → onglet **Application** → **Manifest** : doit afficher tous les champs sans erreur
2. Onglet **Service Workers** : doit montrer `sw.js` activé et "running"
3. Lance un audit **Lighthouse** → catégorie "PWA" → doit valider tous les critères

---

## Étape 2 — Générer les icônes PNG manquantes

L'`icon.svg` actuel est un placeholder (lettre "A" stylisée). Pour un rendu propre :

**Option A — Utiliser PWABuilder (gratuit, en ligne) :**
1. Va sur https://www.pwabuilder.com/imageGenerator
2. Upload `icon.svg` (ou un visuel 512x512 minimum)
3. Télécharge le ZIP avec toutes les tailles (192, 512, 180 pour iOS, maskable, etc.)
4. Place les fichiers à la racine du site :
   - `icon-192.png`
   - `icon-512.png`
   - `icon-maskable-512.png`
   - `icon-180.png`

**Option B — Confier à un designer :**
- Fournis le brief : couleur fond `#F4EFE4`, encre `#1A1108`, accent `#8C1C13`, typo serif (Fraunces)
- Demande les tailles 192, 512, 180, et une version "maskable" (zone safe au centre, fond plein bord à bord)

---

## Étape 3 — Générer le package Android (.aab pour Play Store)

**PWABuilder fait tout le travail :**

1. Va sur https://www.pwabuilder.com/
2. Entre l'URL : `https://avis-base.com`
3. Clique **Start** → l'outil audite la PWA et donne un score
4. Clique **Package For Stores** → **Android**
5. Configure :
   - **Package ID** : `com.avisbase.app` (ou ton choix, doit être unique)
   - **App name** : `Avis Basé`
   - **Launcher name** : `Avis Basé`
   - **Display mode** : `standalone`
   - **Notification delegation** : activé si tu veux des notifs push plus tard
6. Télécharge le ZIP — il contient :
   - `app-release-bundle.aab` ← le fichier à uploader sur le Play Store
   - `app-release-signed.apk` ← pour tester localement
   - `signing-key-info.zip` ← **GARDE-LE PRÉCIEUSEMENT** (sans, tu ne pourras plus jamais publier de mise à jour)
   - Instructions de soumission

L'APK généré est un **TWA (Trusted Web Activity)** : c'est l'app qui charge avis-base.com en mode plein écran natif. **Toute mise à jour du site se reflète instantanément dans l'app.**

---

## Étape 4 — Soumettre sur le Play Store

1. Crée un compte développeur Google Play : https://play.google.com/console (frais unique 25 €)
2. Console Play Store → **Créer une application**
3. Onglet **Production** → **Créer une nouvelle release**
4. Upload le `app-release-bundle.aab`
5. Remplis :
   - Description courte (80 car. max)
   - Description longue (4000 car. max)
   - 2-8 captures d'écran (téléphone) — au moins 320×320 px
   - Icône 512×512
   - Image de bannière 1024×500
   - Catégorie : **Actualités et magazines**
   - Politique de confidentialité (obligatoire — URL vers une page sur ton site)
   - Classement de contenu (questionnaire IARC)
6. Soumets pour examen — délai habituel **3 à 7 jours**

---

## Étape 5 — Générer le package iOS

PWABuilder génère aussi un projet iOS, mais **iOS impose une compilation sur Mac**. Trois options :

### Option A — Mac à disposition (la plus simple)

1. Sur PWABuilder : **Package For Stores** → **iOS** → télécharge le ZIP
2. Ouvre le projet dans Xcode (Mac)
3. Configure le **Bundle Identifier** : `com.avisbase.app`
4. Configure le **Team** (compte développeur Apple)
5. **Product** → **Archive** → upload sur App Store Connect

### Option B — Pas de Mac : services de build cloud

- **Codemagic** (https://codemagic.io) — 500 min/mois gratuites, builds iOS dans le cloud
- **Ionic Appflow** (https://ionic.io/appflow) — payant
- **MacStadium** ou **MacInCloud** — location d'un Mac à l'heure

### Option C — Pas de Mac : louer le service à un freelance

Un dev iOS sur Malt/Fiverr peut compiler et soumettre le projet PWABuilder pour 50-150 €.

---

## Étape 6 — Soumettre sur l'App Store

1. Crée un compte développeur Apple : https://developer.apple.com/programs/ (99 €/an)
2. App Store Connect → **Mes apps** → **Nouvelle app**
3. Upload via Xcode ou Transporter
4. Remplis :
   - Captures (1290×2796 pour iPhone 15 Pro Max minimum)
   - Description
   - Catégorie : **Actualités**
   - Politique de confidentialité
   - Classement par âge
5. Soumets pour examen — délai habituel **24 à 48 h** (parfois plus en cas de questions)

---

## Mises à jour ultérieures — c'est là que c'est magique

| Type de changement | Action requise |
|--------------------|----------------|
| Modification du contenu, du CSS, du JS, ajout d'une feature web | **Push sur Cloudflare** — l'app se met à jour automatiquement, comme un site web |
| Changement de l'icône, du nom, des permissions natives | Regénérer le package via PWABuilder + soumettre une nouvelle version aux stores |
| Mise à jour majeure de la PWA (manifest) | Optionnel : nouvelle release pour rafraîchir les métadonnées |

**Concrètement :** 99 % de tes mises à jour ne passent **jamais** par les stores. C'est exactement le modèle des grands réseaux sociaux (Facebook, Instagram, Twitter) qui mettent à jour leur app en continu côté serveur.

---

## Checklist avant soumission

- [ ] Site déployé sur https://avis-base.com avec manifest + sw + icônes
- [ ] Lighthouse PWA score : 100/100
- [ ] Icônes PNG générées (192, 512, 180, maskable)
- [ ] Politique de confidentialité publiée sur une URL dédiée
- [ ] Compte Google Play créé (25 €)
- [ ] Compte Apple Developer créé (99 €/an)
- [ ] Captures d'écran préparées (téléphone Android + iPhone)
- [ ] Description courte et longue rédigées
- [ ] Catégorie choisie : "Actualités et magazines"

---

## Coûts récapitulatifs

| Poste | Coût | Récurrence |
|-------|------|------------|
| Google Play Developer | 25 € | Une fois |
| Apple Developer Program | 99 € | Par an |
| PWABuilder | Gratuit | — |
| Compilation iOS sans Mac (option B) | 0-30 € | Par release |
| Hébergement Cloudflare Pages | 0 € | — |
| **Total minimum première année** | **124 €** | — |

---

## Ressources

- PWABuilder : https://www.pwabuilder.com/
- Doc TWA Android : https://developer.chrome.com/docs/android/trusted-web-activity
- Doc Cloudflare Pages : https://developers.cloudflare.com/pages/
- Lighthouse PWA criteria : https://web.dev/pwa-checklist/
