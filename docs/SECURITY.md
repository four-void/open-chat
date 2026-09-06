# Modèle de sécurité

Cette implémentation n’a pas fait l’objet d’un audit cryptographique indépendant et ne revendique pas la sécurité absolue.

## Données et clés

| Donnée | Protection |
|---|---|
| Texte d’un message | AES-256-GCM dans le navigateur, IV aléatoire 96 bits ; contexte authentifié liant salon, auteur, nonce et identifiant du fil pour les réponses |
| Clés des serveurs | Coffre AES-GCM propre à l’utilisateur, clé dérivée du mot de passe via PBKDF2-SHA256 (600 000 itérations), sel aléatoire |
| Secret de connexion | Dérivation PBKDF2 distincte dans le navigateur ; le mot de passe d’origine n’est pas transmis ; le backend hache ce secret avec un autre sel et 600 000 itérations |
| E-mail, pseudo, noms des serveurs/salons, définitions/attributions de rôles, exceptions de permissions, coffre et enveloppes des messages | Champs SQL chiffrés AES-256-GCM avec une clé applicative extérieure à PostgreSQL |
| Recherche d’e-mail | Index aveugle HMAC-SHA256, clé extérieure à PostgreSQL |
| Sessions et invitations | Jetons aléatoires 256 bits ; seule leur empreinte SHA-256 est stockée |
| UUID, propriétaires, appartenances, type de salon, dates, tailles | Métadonnées visibles en base, nécessaires aux requêtes et contrôles d’accès |
| Voix et écran | Transport WebRTC DTLS-SRTP entre navigateurs, éventuellement relayé par TURN |

Le serveur déchiffre les métadonnées privées nécessaires à l’interface. Il ne reçoit pas les clés de messages dans les parcours normaux. Le chiffrement applicatif de la base et le chiffrement des messages côté navigateur sont deux protections différentes.

Le coffre est verrouillé à chaque rechargement. Une modification concurrente est refusée pour empêcher un onglet d’écraser silencieusement les clés ajoutées par un autre. Un mot de passe perdu peut rendre l’historique irrécupérable. Il n’existe pas de fonction de réinitialisation contournant ce chiffrement.

## Invitations et limites cryptographiques

Le fragment du lien d’invitation contient la clé partagée du serveur. Toute personne possédant le lien peut rejoindre tant que le jeton n’a pas expiré ; les nouveaux membres peuvent lire l’historique antérieur. Ne jamais publier ces liens. La clé reste connue d’un destinataire après expiration du lien : cette expiration n’est pas une révocation de clé.

Il n’y a pas de Double Ratchet, de confidentialité persistante (forward secrecy), de rotation automatique de clé, ni de vérification indépendante des identités/fingerprints WebRTC. Un membre disposant de la clé peut fabriquer des contenus chiffrés ; l’auteur affiché est imposé par le backend, pas certifié par une signature individuelle. La signalisation WebRTC repose sur la confiance dans le serveur et HTTPS.

Un serveur compromis capable de modifier le JavaScript distribué peut voler le mot de passe ou les clés au moment du déverrouillage. Une extension malveillante ou un terminal compromis peut lire les messages. Cette application web ne protège pas contre ces scénarios. Les membres d’un serveur peuvent copier les conversations auxquelles ils ont accès.

## Contrôles applicatifs

- Appartenance contrôlée pour lecture, écriture, abonnement WebSocket, présence et signalisation ; droits effectifs revérifiés pour les salons, messages, fils et appels. Gestion des rôles réservée au propriétaire et aux administrateurs, avec contrôle de hiérarchie côté serveur ; création de salons et invitations délégables.
- Sessions en cookie chiffré, HttpOnly, SameSite Strict, Secure en production, expiration 24 heures ; rotation à la connexion et révocation à la déconnexion.
- CSRF sur mutations HTTP ; WebSocket authentifié et origines contrôlées. Session revérifiée à chaque événement et périodiquement pour les abonnements inactifs.
- Limites de taille des requêtes, frames WebSocket, messages et coffres. Pagination de l’historique.
- Limitation de fréquence des connexions, API et événements. Le limiteur est **local à un nœud**, pas distribué ; ajouter une protection d’entrée partagée pour un déploiement en cluster.
- CSP sans scripts externes ni scripts inline, protection contre les iframes, politique de référent restrictive, échappement Svelte et absence de rendu HTML fourni par les utilisateurs.
- Paramètres sensibles filtrés des logs Phoenix, logs SQL désactivés. Les proxys et outils de suivi doivent appliquer la même discipline ; ne pas journaliser les corps de requêtes.

## Exploitation

En production, `DATA_ENCRYPTION_KEY` doit être un secret aléatoire de 32 octets en base64, obligatoire au démarrage. Sa perte rend les champs chiffrés inutilisables ; la remplacer sans migration de rechiffrement détruit l’accès aux données et index aveugles. Sauvegarder la clé séparément de PostgreSQL, avec contrôle d’accès strict. Les secrets de développement ne doivent jamais être réutilisés en production.

**État local actuel :** en l’absence de `DATA_ENCRYPTION_KEY`, cette version utilise une clé de développement déterministe publique. Elle permet les tests mais ne protège pas les métadonnées privées contre une personne ayant accès à la base et au code. Les textes des messages restent protégés par leurs clés côté navigateur. Le remplacement de cette clé sur la base existante requiert un rechiffrement et une sauvegarde, opération refusée par la vérification automatique sans accord explicite. Ne pas utiliser cette configuration pour des données confidentielles. En production, aucun repli sur cette clé n’est autorisé.

La base Docker locale n’expose son port que sur loopback. Pour la production, fournir TLS, réseau privé, sauvegardes chiffrées, rétention des logs, mises à jour de dépendances et protection anti-abus adaptée. Avant ouverture publique : audit indépendant, tests de charge, validation TURN sur les réseaux ciblés et ajout des fonctions de gestion de compte/modération nécessaires à votre exploitation.

Références : [Phoenix Channels](https://phoenix.hexdocs.pm/channels.html), [négociation WebRTC](https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API/Perfect_negotiation), [coturn](https://github.com/coturn/coturn).

## Portée des permissions

Les salons privés sont protégés par le contrôle d’accès du backend. La clé de chiffrement des messages reste partagée à l’échelle du serveur : les permissions ne constituent pas une séparation cryptographique entre salons. Une révocation ne peut pas effacer les messages déjà reçus ni empêcher leur déchiffrement si leur ciphertext et la clé ont été conservés. Des clés par salon et leur rotation seraient nécessaires pour une isolation cryptographique plus fine.

Les droits vocaux contrôlent l’entrée, les offres/réponses de signalisation et le comportement du client fourni. Une modification des droits coupe la signalisation et ferme les appels dans ce client. Le média circule directement entre navigateurs : un client modifié pourrait conserver une connexion déjà établie avec un autre client complice. Ce maillage ne fournit pas la modération forcée du média d’un serveur central.

## Messages privés individuels

Les deux navigateurs dérivent une clé AES-256-GCM avec ECDH P-256 puis HKDF-SHA256, avec séparation par identifiant de conversation. Le contexte authentifié lie chaque ciphertext à la conversation, à l’auteur et au nonce. La clé privée d’identité reste dans le coffre chiffré de l’utilisateur ; seul son point public est publié, et il est immuable dans cette version. Les clés des serveurs ne permettent pas de déchiffrer les MP. L’API refuse la lecture et l’écriture à tout tiers, même propriétaire d’un serveur commun. Les événements temps réel passent par un abonnement privé à l’utilisateur et recontrôlent la session et la participation.

Les identités publiques sont distribuées par le backend de confiance, sans vérification indépendante d’empreinte. Ce mécanisme utilise des identités statiques, sans Double Ratchet ni confidentialité persistante. La perte de la clé privée rend l’historique privé illisible ; la récupération et la rotation ne sont pas implémentées. Le serveur peut observer les identifiants des deux participants, les dates et les volumes des échanges. Les enveloppes des messages et les identités publiques bénéficient aussi du chiffrement applicatif au repos.

Référence de l’implémentation Web Crypto : [ECDH suivi de HKDF](https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto/deriveKey).
