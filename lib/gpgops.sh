gpg_cle_publique_existe() { gpg --list-keys "$1" >/dev/null 2>&1; }
gpg_cle_secrete_existe() { gpg --list-secret-keys "$1" >/dev/null 2>&1; }
gpg_empreinte() { gpg --list-keys --with-colons "$1" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }'; }

gpg_resoudre_fichier_export() {
    local rep="$1" cible="$2" suffixe="$3"
    if [[ -f "$rep/$cible" ]]; then printf '%s\n' "$rep/$cible"
    elif [[ -f "$rep/${cible}${suffixe}" ]]; then printf '%s\n' "$rep/${cible}${suffixe}"
    else return 1; fi
}

gpg_generer() {
    exiger_ouvert
    local nom="" courriel="" commentaire="" phrase1="" phrase2=""
    read -r -p "Nom complet : " nom || true
    [[ -n "$nom" ]] || erreur "Le nom est obligatoire"
    read -r -p "Adresse e-mail : " courriel || true
    [[ "$courriel" == ?*@?*.?* ]] || erreur "Adresse e-mail invalide : $courriel"
    read -r -p "Commentaire (optionnel) : " commentaire || true
    read -r -s -p "Phrase secrète de la clé : " phrase1 || true; printf '\n' >&2
    read -r -s -p "Confirmation : " phrase2 || true; printf '\n' >&2
    [[ -n "$phrase1" ]] || erreur "La phrase secrète ne peut pas être vide"
    [[ "$phrase1" == "$phrase2" ]] || erreur "Les phrases secrètes ne correspondent pas"
    local lot; lot="$(mktemp)"; chmod 600 "$lot"
    {
        printf 'Key-Type: eddsa\nKey-Curve: ed25519\nKey-Usage: sign\n'
        printf 'Subkey-Type: ecdh\nSubkey-Curve: cv25519\nSubkey-Usage: encrypt\n'
        printf 'Name-Real: %s\n' "$nom"
        [[ -n "$commentaire" ]] && printf 'Name-Comment: %s\n' "$commentaire"
        printf 'Name-Email: %s\n' "$courriel"
        printf 'Expire-Date: 2y\n%%commit\n'
    } > "$lot"
    printf '%s' "$phrase1" | gpg --batch --quiet --pinentry-mode loopback --passphrase-fd 0 --generate-key "$lot" || { rm -f "$lot"; erreur "Échec de la génération GPG"; }
    phrase1=""; phrase2=""; rm -f "$lot"
    local empreinte; empreinte="$(gpg --list-secret-keys --with-colons "$courriel" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')" || true
    [[ -n "$empreinte" ]] || erreur "Clé générée introuvable dans le trousseau"
    gpg_exporter_publique "$empreinte"
}

gpg_exporter_publique() {
    exiger_ouvert
    local ident="${1:-}"
    [[ -n "$ident" ]] || erreur "Usage : coffre gpg export-pub <id|empreinte>"
    gpg_cle_publique_existe "$ident" || erreur "Clé publique introuvable dans le trousseau : $ident"
    local empreinte sortie; empreinte="$(gpg_empreinte "$ident")"; sortie="$coffre_rep_gpg_pub/${empreinte}.pub.asc"
    gpg --armor --export "$empreinte" > "$sortie" || { rm -f "$sortie"; erreur "Échec de l'export public"; }
    [[ -s "$sortie" ]] || { rm -f "$sortie"; erreur "Export public vide, clé $empreinte introuvable"; }
    chmod 644 "$sortie"
}

gpg_exporter_privee() {
    exiger_ouvert
    local ident="${1:-}"
    [[ -n "$ident" ]] || erreur "Usage : coffre gpg export-priv <id|empreinte>"
    gpg_cle_secrete_existe "$ident" || erreur "Clé privée introuvable dans le trousseau : $ident"
    printf 'Attention : export d une CLE PRIVEE. Ce fichier ne doit servir qu a une migration de poste, puis etre supprime du coffre.\n' >&2
    confirmer_mot "Confirmer l'export de la clé privée" "EXPORTER" || erreur "Export annulé"
    local empreinte sortie phrase_cle=""; empreinte="$(gpg_empreinte "$ident")"; sortie="$coffre_rep_gpg_priv/${empreinte}.sec.asc"
    read -r -s -p "Phrase secrète de la clé : " phrase_cle || true; printf '\n' >&2
    ( umask 077 && printf '%s' "$phrase_cle" | gpg --batch --quiet --pinentry-mode loopback --passphrase-fd 0 --armor --export-secret-keys "$empreinte" > "$sortie" ) || { rm -f "$sortie"; erreur "Échec de l'export privé (phrase secrète incorrecte ?)"; }
    phrase_cle=""
    [[ -s "$sortie" ]] || { rm -f "$sortie"; erreur "Export privé vide"; }
    chmod 400 "$sortie"
}

gpg_importer_publique() {
    exiger_ouvert
    local cible="${1:-}"
    [[ -n "$cible" ]] || erreur "Usage : coffre gpg import-pub <fichier|empreinte>"
    local fichier; fichier="$(gpg_resoudre_fichier_export "$coffre_rep_gpg_pub" "$cible" ".pub.asc")" || erreur "Aucun export public correspondant dans le coffre : $cible"
    gpg --quiet --import "$fichier" || erreur "Échec de l'import public"
}

gpg_importer_privee() {
    exiger_ouvert
    local cible="${1:-}"
    [[ -n "$cible" ]] || erreur "Usage : coffre gpg import-priv <fichier|empreinte>"
    confirmer "Importer une clé PRIVÉE dans le trousseau de cette machine ?" || erreur "Import annulé"
    local fichier; fichier="$(gpg_resoudre_fichier_export "$coffre_rep_gpg_priv" "$cible" ".sec.asc")" || erreur "Aucun export privé correspondant dans le coffre : $cible"
    gpg --quiet --import "$fichier" || erreur "Échec de l'import privé"
}

commande_gpg() {
    local sous_cmd="${1:-}"; [[ $# -gt 0 ]] && shift
    case "$sous_cmd" in
        generate)    gpg_generer ;;
        export-pub)  gpg_exporter_publique "${1:-}" ;;
        export-priv) gpg_exporter_privee "${1:-}" ;;
        import-pub)  gpg_importer_publique "${1:-}" ;;
        import-priv) gpg_importer_privee "${1:-}" ;;
        *)           erreur "Sous-commande gpg inconnue : $sous_cmd (generate, export-pub, export-priv, import-pub, import-priv)" ;;
    esac
}
