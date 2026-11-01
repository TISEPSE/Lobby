; Crochets de l'installeur Lobby (`bundle.windows.nsis.installerHooks`).
; Fichier en UTF-8 AVEC BOM : sans lui, makensis casse les accents.

; Relancer le setup sur un PC qui a déjà des données : on demande, on ne décide
; pas. Non par défaut, et jamais en mode silencieux ni pendant une mise à jour :
; une mise à jour ne doit faire perdre ni les comptes ni les statistiques.
; `POSTINSTALL` et pas `PREINSTALL` : c'est après `CheckIfAppIsRunning`, Lobby est
; fermé et ses fichiers ne sont plus verrouillés.
!macro NSIS_HOOK_POSTINSTALL
  ${If} $UpdateMode <> 1
  ${AndIfNot} ${Silent}
    SetShellVarContext current
    ${If} ${FileExists} "$APPDATA\${BUNDLEID}\*.*"
      ${If} ${Cmd} `MessageBox MB_YESNO|MB_ICONQUESTION|MB_DEFBUTTON2 "Lobby a déjà des données sur ce PC : comptes Steam et Epic, statistiques, jaquettes, réglages.$\n$\nRepartir de zéro ? Tout sera effacé et les écrans de bienvenue s'ouvriront au prochain lancement.$\n$\nOui : tout effacer.$\nNon : garder mes données." /SD IDNO IDYES`
        RmDir /r "$APPDATA\${BUNDLEID}"
        RmDir /r "$LOCALAPPDATA\${BUNDLEID}"
      ${EndIf}
    ${EndIf}
  ${EndIf}
!macroend
