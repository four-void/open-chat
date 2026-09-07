# Vérification locale — 5 septembre 2026

Environnement : PostgreSQL 17 dans Docker, Phoenix sur localhost:4000, Chromium via Playwright.

- Inscription de deux comptes QA, connexion, verrouillage et déverrouillage du coffre après rechargement.
- Création de serveur et de ses salons initiaux ; ajout d’un salon textuel personnalisé.
- Génération et acceptation d’une invitation depuis un deuxième compte indépendant.
- Déchiffrement de l’historique par le membre invité ; envoi dans les deux sens et présence en temps réel.
- Appel entre deux contextes navigateur avec **microphones synthétiques** : connexion `connected`, paquets RTP audio effectivement reçus.
- Partage d’un **canvas synthétique** via le véritable RTCPeerConnection : 178 images décodées au point de mesure, vidéo 640×360 en lecture côté destinataire.
- Micro désactivé (`track.enabled == false`), audio conservé lorsque le participant retourne au salon textuel.
- Captures de vérification dans `output/playwright/` (fichiers locaux ignorés par Git).

Ces essais ne valident pas le microphone physique, le sélecteur d’écran du système, les réseaux NAT externes, TURN en production, Safari/Firefox, ni la tenue en charge.

Les tests automatisés sont décrits dans le README. Le test CSRF inclut l’enchaînement réel connexion puis mutation avec le nouveau jeton de session, après correction d’une régression identifiée dans le navigateur.

## Refonte, rôles et fils

- `mix precommit` : 30 tests réussis, dont accès privés, combinaison des exceptions, interdiction d’élévation de droits, fils isolés/paginés/archivables, fermeture d’un abonnement actif après retrait d’accès et refus des offres vocales émettrices pour un auditeur.
- `npm run check` : aucun diagnostic Svelte ; 4 tests JavaScript, dont liaison cryptographique des réponses au fil attendu.
- Inspection de la navigation, du dialogue des rôles et de l’ouverture d’un fil à partir d’un message du compte QA dans Chrome via l’accessibilité native et captures d’écran. Les appels WebRTC synthétiques décrits plus haut concernent la version précédente ; la signalisation soumise aux permissions est couverte ici par les tests backend.

## Messages privés

- 38 tests backend passent : conversations uniques par duo, contacts limités aux serveurs communs, identité publique immuable, refus d’accès aux tiers, pagination, chiffrement applicatif SQL et livraison sur l’inbox privée.
- 5 tests JavaScript passent, dont échange ECDH/HKDF entre deux identités, rejet d’un tiers, séparation des conversations et récupération de l’identité depuis le coffre chiffré. Vérification Svelte sans erreur ni avertissement et build de production réussi.
- Chrome, comptes locaux Camille QA et Morgan QA : activation des deux identités à la connexion, ouverture via le logo, sélection d’un contact, création de conversation, envoi d’un message synthétique QA, déconnexion puis lecture et déchiffrement de ce même message avec le compte destinataire. L’accueil et la conversation ont été inspectés visuellement.
- Le parcours navigateur a été vérifié séquentiellement ; la livraison temps réel au destinataire est couverte par le test du canal Inbox.

## Salons, administration et emojis — 6 septembre 2026

`mix precommit` : 54 tests réussis. Les tests couvrent la création textuelle/vocale déléguée et son retrait immédiat, le refus des gestionnaires non administrateurs, ainsi que la sauvegarde, la conservation et la suppression des emojis (y compris drapeaux et séquences jointes). Les noms et emojis restent dans le champ chiffré des rôles. Vérification Svelte sans diagnostic, 12 tests JavaScript réussis et build de production réussi.

## Gestion directe des membres — 6 septembre 2026

56 tests backend réussis, dont ajout/retrait ciblé et idempotent d’un rôle, conservation des autres attributions et refus par statut administrateur, hiérarchie et serveur. 12 tests JavaScript réussis ; Svelte sans diagnostic et build réussi. Inspection native de Chrome indisponible (échec de démarrage du canal Computer Use) : le nouveau rendu des fiches membres n’a pas été validé visuellement dans cette passe.

## Interactions des messages — 6 septembre 2026

- `mix precommit` réussi avec un dossier de compilation isolé : 61 tests. Vérification des routes salons/MP, auteur seul autorisé à éditer/supprimer, droits de lecture/écriture, réactions idempotentes et conservation des fils après suppression du message initial.
- 14 tests JavaScript réussis, dont compatibilité des anciens messages, références de réponse chiffrées et protection contre les événements arrivant dans le désordre. Svelte sans diagnostic et build réussi.
- Migration appliquée. Le serveur Phoenix local était bloqué et ignorait SIGTERM ; il a été arrêté puis relancé. Les routes de session, salons et historiques répondent HTTP 200 avec la nouvelle version.
- Contrôle visuel indisponible : le canal natif Computer Use échoue au démarrage. Le rendu et les interactions réelles dans le navigateur restent à vérifier ; aucune validation visuelle n’est revendiquée.
