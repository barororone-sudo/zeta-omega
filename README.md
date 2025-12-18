# Projet Open World RPG - Architecture Modulaire

## Contexte
Ce projet est un Action-RPG Open World solo (style Zelda/Genshin) conçu pour être performant sur des machines de milieu de gamme (i7, 16Go RAM).

## Architecture
L'architecture se veut modulaire, séparant clairement les données (Assets, Resources), la logique (Scripts), et l'assemblage (Scenes).

### Structure du projet
- **_Core/** : Singletons, Managers globaux, Constantes.
- **Assets/** : Fichiers bruts (Modèles, Textures, Sons, Shaders).
- **Scenes/** : Assemblages de nœuds (.tscn).
- **Scripts/** : Logique pure (.gd). Structure miroir de `Scenes/`.
- **Resources/** : Données de jeu (Items, Quêtes, Stats) sous forme de `CustomResource`.

## Objectifs Techniques
- Modularité et évolutivité.
- Optimisation pour Forward+ Renderer.
- Structure de code propre et découplée.
