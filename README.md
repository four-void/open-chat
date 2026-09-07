# Openchat

Plateforme de communautés : Phoenix 1.8 / PostgreSQL, interface Svelte 5 et composants officiels shadcn-svelte (style Nova). Messages chiffrés dans le navigateur, salons textuels et vocaux, appels WebRTC et partage d’écran.

## Démarrage local

Prérequis : Elixir 1.15+ / OTP compatible, Node 22+, npm et Docker avec Compose.

```sh
./scripts/dev
```

Ouvrir **http://localhost:4000**. PostgreSQL écoute uniquement sur `127.0.0.1:55432` ; son volume Docker est `openchat_secure_pg_v1`. Le script attend que PostgreSQL soit prêt, installe les dépendances, applique les migrations et démarre Phoenix avec la reconstruction automatique des assets.

Pour personnaliser la configuration, copier `.env.example` vers `.env`. Le script charge ce fichier ; une commande `mix` lancée directement ne le charge pas automatiquement. Le mot de passe PostgreSQL et la clé applicative par défaut sont réservés au développement local. La clé par défaut est publique : ne pas utiliser cette configuration avec des données confidentielles. Sur une base déjà remplie, changer la clé nécessite une migration de rechiffrement.

## Parcours

1. Créer un compte (pseudo, e-mail, mot de passe de 12 caractères minimum).
2. Créer un serveur : `général` et `Le salon` sont ajoutés automatiquement.
3. Le propriétaire peut créer des salons textuels/vocaux et générer des invitations de 24 heures ; ces droits peuvent être délégués à des rôles.
4. Envoyer le lien complet en privé à un autre utilisateur. Il contient la clé du serveur dans son fragment `#`, jamais envoyé au backend.
5. Le destinataire crée son compte ou se connecte puis accepte l’invitation. Il peut aussi coller le lien avec « Rejoindre un serveur ».
6. Échanger des messages en temps réel. L’historique est paginé par 50 messages et les clés sont retrouvées à la reconnexion grâce au coffre chiffré.
7. Ouvrir un salon vocal, rejoindre, autoriser le microphone, puis éventuellement partager un écran. Couper le micro et quitter libèrent les pistes multimédias. L’audio continue lorsqu’on ouvre un salon textuel.

Les clés déverrouillées restent en mémoire : après un rechargement de page, le mot de passe est demandé à nouveau. Aucun mot de passe ni clé déchiffrée n’est placé dans localStorage.

## Rôles, accès et fils

- **Membres → Gérer les rôles** : le propriétaire et les administrateurs configurent les droits de « Tout le monde », créent des rôles nommés, colorés et accompagnés d’un emoji facultatif, puis les attribuent aux membres. Les rôles ajoutent des droits aux droits de base.
- **Créer un salon** dans la barre latérale du serveur : réservé aux personnes ayant « Gérer les salons ». Les boutons + des sections textuelle et vocale présélectionnent le type de salon.
- **Permissions du salon** dans son en-tête : réglages rapides Ouvert, Lecture seule ou Privé, puis exceptions par rôle et par personne avec Hériter / Autoriser / Refuser.
- Ordre des exceptions : Tout le monde, ensemble des rôles (une autorisation l’emporte sur les refus de rôles), puis personne. Le propriétaire et le rôle Administrateur contournent les exceptions des salons. La gestion des rôles est réservée au propriétaire et aux administrateurs. Les administrateurs ne modifient que les rôles et membres de rang inférieur, jamais leurs propres rôles ni ceux du propriétaire. L’ancien droit `manage_roles` seul ne donne plus cet accès.
- Droits disponibles : voir, écrire, créer/gérer les fils, rejoindre les appels, parler, partager l’écran, gérer les salons, inviter et administrer. Les gestionnaires de salons ne peuvent pas s’accorder des droits qu’ils ne possèdent pas.
- **Répondre dans un fil** sous un message ouvre une conversation séparée. Le bouton **Fils** retrouve les discussions du salon. L’auteur du fil ou un membre autorisé peut le fermer et le rouvrir. Les réponses sont chiffrées et paginées ; elles héritent des accès du salon.
- Les salons non autorisés disparaissent et leurs API refusent l’accès. Les modifications sont propagées aux connexions ouvertes ; les appels doivent être rejoints à nouveau après modification des droits.

L’interface utilise une navigation compacte, une recherche locale des salons, un panneau contextuel pour les membres et les fils, et un menu de salons escamotable sur mobile.

## Interactions des messages

Dans les salons et les messages privés, survolez un message ou ouvrez son menu d’actions (également au clic droit). Sur écran tactile, les boutons restent visibles. Vous pouvez répondre à un message, réagir avec un emoji, copier son texte et modifier ou supprimer vos propres messages. Les fils disposent aussi des réactions, de l’édition et de la suppression. Les changements sont diffusés en temps réel.

Le champ de saisie accepte plusieurs lignes : **Entrée** envoie, **Maj + Entrée** ajoute une ligne. Le bouton emoji insère un emoji dans le texte. La suppression demande confirmation et laisse un repère « Message supprimé », afin de préserver les fils existants. Les réponses font référence au message original sans enregistrer une copie de son texte ; lorsque ce message n’est pas dans l’historique chargé, un libellé générique apparaît.

Cette version ne reproduit pas toutes les fonctions de Discord : pièces jointes/GIF, épingles, recherche globale et notifications de mentions restent à implémenter.

## Gérer les membres

Dans **Membres**, recherchez une personne ou filtrez par présence et par rôle. Un clic ou clic droit sur une ligne ouvre sa fiche : profil, message privé, demande d’amitié et rôles. Les administrateurs peuvent ajouter ou retirer un rôle avec un interrupteur ; chaque changement est enregistré immédiatement, sans formulaire de validation supplémentaire. Les rôles protégés restent visibles mais désactivés.

**Gérer les rôles** ouvre la configuration du serveur : sélection dans la liste hiérarchisée, création, emoji, permissions et suppression. L’ancien onglet d’attribution a été remplacé par les actions sur les fiches des membres. Les modifications ciblent un seul rôle sous verrou transactionnel pour préserver les autres attributions.

## Messages privés

Le logo en haut à gauche ouvre les **Messages privés** sans recharger l’application. « Nouvelle conversation » permet de rechercher une personne parmi les membres de vos serveurs communs. Le bouton de message dans la liste des membres ouvre également ce parcours. Les conversations existantes restent disponibles indépendamment des salons ; seul le duo peut les consulter.

Chaque compte active automatiquement une identité de chiffrement à sa prochaine connexion. Un membre qui ne s’est pas encore reconnecté apparaît comme indisponible dans le sélecteur. La clé privée est sauvegardée dans son coffre chiffré ; les clés des messages privés sont dérivées dans le navigateur, séparément des clés de serveurs. L’historique est paginé et conservé après reconnexion. Un compteur sur le logo signale les messages reçus pendant que vous consultez un serveur (compteur de session, sans accusés de lecture persistants).

Cette première version des MP couvre les messages textuels individuels ; elle ne comprend pas encore les groupes privés, les appels privés, les demandes d’amis ni le blocage de contacts.

## Appels sur Internet

Sans serveur TURN, les appels sont destinés aux réseaux où une connexion directe est possible, notamment en local. L’interface indique l’absence de TURN. Pour une utilisation entre réseaux différents :

- Déployer [coturn](https://github.com/coturn/coturn), avec `use-auth-secret`, un secret aléatoire robuste, un `realm` et une adresse publique correcte. Ouvrir les ports TURN et sa plage de relais dans le pare-feu.
- Définir `TURN_URLS` et `TURN_SECRET` côté Phoenix. `/api/ice` fournit uniquement aux utilisateurs connectés des identifiants temporaires d’une heure ; le secret partagé ne part pas au navigateur.
- Servir l’application en HTTPS. `localhost` est accepté en développement par les navigateurs ; une adresse HTTP distante ne permet pas normalement microphone et partage d’écran.

La topologie est un maillage WebRTC, adaptée aux petits groupes. Chaque participant envoie aux autres. Ce n’est pas une infrastructure SFU pour des centaines de participants. Le partage inclut la vidéo de l’écran, pas son audio système.

## Sécurité et limites

Lire [docs/SECURITY.md](docs/SECURITY.md) avant une mise en ligne. Les contenus privés sont chiffrés ; les UUID, relations et dates techniques sont visibles en base. « Aucune donnée en clair » au sens littéral et « sécurité absolue » ne sont pas des garanties fournies par cette implémentation.

La version actuelle couvre inscription/connexion/déconnexion, communautés privées, invitations, messages et appels. Elle ne comprend pas encore vérification d’adresse e-mail, récupération/changement de mot de passe, MFA, modération/exclusion, suppression de comptes/serveurs, pièces jointes ni rotation automatique des clés. Une adresse e-mail inscrite n’est donc pas une identité vérifiée.

## Vérifications

```sh
mix precommit
npm --prefix assets run check
npm --prefix assets test
npm --prefix assets run build
```

Les tests Elixir utilisent `openchat_test` sur PostgreSQL Docker. Ils vérifient notamment sessions révoquées/expirées, CSRF, accès aux salons, invitations, absence de contenu privé en clair dans SQL, coffre concurrent, diffusion de messages chiffrés, priorité des exceptions, prévention des élévations de droits, héritage/archivage des fils et révocation des abonnements ouverts. Les tests JavaScript vérifient la dérivation des clés et le rejet de messages altérés ou déchiffrés dans un mauvais contexte.

## Production

```sh
mix deps.get --only prod
npm --prefix assets ci
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
# Fournir les variables documentées ci-dessous avant de démarrer :
PHX_SERVER=true _build/prod/rel/openchat/bin/openchat start
```

Obligatoires au démarrage : `DATABASE_URL`, `DATA_ENCRYPTION_KEY` (32 octets en base64), `SECRET_KEY_BASE`, `PHX_HOST`. Configurer aussi `TURN_URLS` / `TURN_SECRET` pour les appels Internet. Le processus de release applique les migrations. Fournir les secrets depuis un gestionnaire de secrets ; ne jamais les stocker dans l’image ou le dépôt.

Placer Phoenix derrière un reverse proxy HTTPS de confiance qui remplace `X-Forwarded-Proto` et interdit l’accès public au port HTTP interne. L’application impose HTTPS et les cookies Secure en production. La connexion à une base distante doit être protégée par un réseau privé et/ou TLS configuré avec validation du certificat. Les sauvegardes de la base **et** des clés doivent être chiffrées et conservées séparément.
