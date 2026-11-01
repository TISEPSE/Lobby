---
name: roadmap
description: Feuille de route de Lobby (Interface Console) — ce qui reste à faire (étapes et fonctions façon warmUP). À lire quand on demande ce qu'il reste, quoi faire ensuite, ou quand une étape avance.
---

# Feuille de route

Étapes déjà faites (non détaillées ici) : socle, bibliothèque, recherche, réglages, détection de jeux, finitions.

5. **Fiches** : notes, genres, résumés et jaquettes récupérés automatiquement — *fait*. Les visuels sont **téléchargés une fois** dans `<app data>/artwork/` (`cache_game_art`) : l'interface lit un fichier, pas une adresse web, donc l'association jeu ↔ jaquette ne peut plus changer et tout s'affiche hors ligne.
6. **Système** : build Linux, Gamescope, systemd, boot direct.
8. **Au niveau de warmUP** (warmup-gamelauncher.com/features) :
   - Interface « couch gaming » 100 % manette — *fait*
   - Écrans de bienvenue au premier lancement (profil, comptes, jeux, habitudes), ouverture au démarrage de Windows, choix de repartir de zéro dans le setup — *fait*. Reste : désigner l'écran de jeu (« Jump Screen » de warmUP), Lobby ne sait pas encore en choisir un.
   - Panneau de droite (bouton Menu) : notifications, heure, semaine, manette — *fait*. Il est prêt à recevoir une section de plus. Reste à décider quoi y mettre : widgets modifiables, météo.
   - Statistiques (temps, parties, top jeux, genres, boutiques, par période) — *fait*. Jeux possédés / installés et mesure des jeux Steam (`RunningAppID`) — *fait*.
   - Bibliothèque unifiée : Steam, Epic, dossiers, `.lnk`, registre — *fait*. Reste : GOG, EA, Xbox, Ubisoft, Amazon, émulateurs (dossiers de ROMs, émulateur choisi par jeu).
   - Synchronisation : X dans la bibliothèque — *fait*
   - Reprise rapide : carte « Reprendre » en tête de l'accueil, la dernière partie se relance en un appui — *fait*
   - Écran de pré-lancement : captures, bandes-annonces et « Plus sur… » sous la fiche — *fait*
   - Onglet Découverte (« Pour toi ») : recommandations, sorties à venir, bandes-annonces Steam (`movies` de `appdetails`), liste de souhaits, jeux oubliés.
   - Succès : tableau de bord unifié, taux de complétion, rareté, progression dans le temps, filtres par plateforme (Steam sans clé si le profil est public, RetroAchievements avec une clé saisie dans Réglages).
   - Overlay FPS et historique de performances : MangoHud sous Linux, journaux relus dans les statistiques.
   - Discord : statut du jeu en cours (Rich Presence), puis amis en ligne, messages et groupes par code d'invitation. Les fonctions sociales exigent une application Discord, une connexion OAuth et, pour la liste d'amis, l'accord de Discord (`relationships.read`, programme Social SDK) : ça contredit « aucune clé », à trancher avant de s'y lancer.
   - Clavier virtuel : pensé aussi pour écrire des messages (Discord), commandes vocales plus tard.
