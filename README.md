# Météo meteodb pour KOReader

Plugin météo pour Kobo Mini utilisant KOReader. Il récupère les mesures de la station meteodb et les présente dans un tableau de bord monochrome. Aucun fichier ni réglage du serveur meteodb n'est modifié.

Les anciens prototypes pour le navigateur Nickel et NickelMenu ont été retirés du projet actif. Leur archive locale, dans `old/`, n'est pas publiée.

## Configuration

Copier `config.example.lua` vers `config.lua` dans le répertoire du plugin, puis renseigner `base_url`, `station_id` et `api_token`. Créer un jeton de lecture dans meteodb (menu **Jetons API**) et le copier dans `api_token`; meteodb ne l'affiche qu'une fois et permet de le révoquer. Les options `interval_minutes` (15 par défaut) et `low_battery_threshold` (10 % par défaut) sont facultatives. `station_id` est l'identifiant URL de « Avon vallée », à relever dans l'adresse de la station sur meteodb.

Le jeton reste un secret stocké dans `config.lua` sur la liseuse; il est limité à la lecture des stations accessibles au compte et peut être révoqué depuis meteodb. Garder `config.lua` local : il est ignoré par Git et exclu des archives de transfert.

## Installation

Copier `weather.koplugin` dans `/mnt/onboard/.adds/koreader/plugins/`, puis copier le fichier `config.lua` local dans `/mnt/onboard/.adds/koreader/plugins/weather.koplugin/`. Redémarrer KOReader et lancer **Météo meteodb** dans le menu Outils.

Le tableau de bord reste affiché en plein écran jusqu'à une action explicite. En paysage, quatre indicateurs prioritaires sont présentés en grille 2×2 et les autres valeurs dans une bande secondaire. En portrait, les quatre indicateurs sont empilés sur toute la largeur. Les commandes **Portrait/Paysage**, **Réduire** et **Fermer** restent visibles. Réduire suspend le rafraîchissement mais garde les mesures et la session en mémoire; Fermer efface la session du plugin. La suspension automatique de KOReader n'est pas désactivée.

À son ouverture, le tableau déclenche une synchronisation, coupe le Wi-Fi, programme un réveil RTC et suspend KOReader. À chaque réveil programmé, le plugin actualise les données, coupe le Wi-Fi et retourne en veille. L'intervalle est de quinze minutes par défaut. Le bouton **Actualiser** a été retiré : une reprise manuelle déclenche une actualisation, puis le cycle de veille reprend. Le plugin active le réglage KOReader **Restore Wi-Fi connection on resume** afin que `wifi_was_on` puisse être restauré après une reprise manuelle ou un redémarrage. En cas d'échec réseau, le dernier relevé reste visible avec l'avertissement **DONNÉES NON À JOUR**. Le cycle de synchronisation continue et réessaie à l'intervalle configuré, y compris après un échec de connexion Wi-Fi. Si l'appareil ou la version KOReader ne fournit pas de réveil RTC utilisable, le plugin reste actif et utilise son minuteur périodique.

Pour éviter que le message **Sleeping mode** par défaut de KOReader apparaisse au milieu de l'écran entre deux mises à jour, ouvrir **Paramètres** (roue crantée) > **Screen** > **Sleep Screen** > **Sleep screen message** > **Container and position**. Sélectionner **Banner**, puis régler **Vertical position** sur `0` ou `bottom`. Le message affiché peut aussi être personnalisé ici, par exemple avec **En veille**.

Si la charge atteint `low_battery_threshold` (10 % par défaut), le plugin coupe les tâches et réveils météo puis demande la mise en veille de KOReader. La protection ne réarme pas les synchronisations après une reprise manuelle. Elle ne remplace pas l'arrêt matériel automatique de la liseuse.

La température intérieure est lue dans la section **Intérieur** de la page authentifiée. La pression atmosphérique affichée par la station est relative, réduite au niveau de la mer. L'icône météo monochrome et le web meteodb utilisent la tendance de pression sur trois heures renvoyée par l'API. Les icônes soleil, éclaircies, nuage, pluie et temps perturbé sont des estimations barométriques; elles ne décrivent pas directement le ciel observé.

Les réveils périodiques dépendent du RTC et du chemin de reprise de la version KOReader installée; leur cadence et le retour en veille doivent être validés sur la Kobo Mini. Une extinction complète de la liseuse interrompt les actualisations jusqu'au prochain démarrage.

## Paquetage et validation

Lancer `./package.sh` pour créer `dist/kobo-weather-plugin.zip`, une archive contenant le plugin et ses fichiers d'exemple et de documentation. `config.lua`, l'archive locale `old/` et les autres fichiers ignorés ne sont jamais ajoutés au paquetage.

Sur Kobo Mini, vérifier la connexion, les huit lectures, le délai de rafraîchissement et la reprise après échec réseau ou suspension. Comparer l'autonomie sur des périodes de même durée et noter l'état du Wi-Fi et l'intervalle.

Le plugin appelle l'API JSON `/api/v1/stations/{station_id}/current` de meteodb avec un jeton Bearer via HTTPS. La réponse inclut `pressure_trend`, calculée à partir des relevés de pression autour de l'instant courant et de celui situé trois heures auparavant. Si l'historique est insuffisant, le serveur signale la tendance comme indisponible et le plugin affiche un libellé adapté. Si le jeton est révoqué, le réseau indisponible ou la réponse invalide, le dernier écran de mesures reste affiché.
