ssh_hotes_dans() {
    local fichier="$1"; [[ -f "$fichier" ]] || return 0
    awk 'tolower($1) == "host" { for (i = 2; i <= NF; i++) if ($i !~ /[*?]/) print $i }' "$fichier" | awk '!vu[$0]++'
}

ssh_extraire_bloc() {
    local fichier="$1" cible="$2"
    awk -v cible="$cible" '
        tolower($1) == "host" || tolower($1) == "match" {
            dansbloc = 0
            if (tolower($1) == "host") { for (i = 2; i <= NF; i++) if ($i == cible) dansbloc = 1 }
        }
        dansbloc { print }
    ' "$fichier"
}

ssh_supprimer_bloc() {
    local fichier="$1" cible="$2" temporaire; temporaire="$(mktemp)"
    awk -v cible="$cible" '
        tolower($1) == "host" || tolower($1) == "match" {
            sauter = 0
            if (tolower($1) == "host") { for (i = 2; i <= NF; i++) if ($i == cible) sauter = 1 }
        }
        !sauter { print }
    ' "$fichier" > "$temporaire"
    install -m 600 "$temporaire" "$fichier"; rm -f "$temporaire"
}

ssh_resoudre_chemin_cle() {
    local chemin="$1"
    case "$chemin" in
        "~")   chemin="$HOME" ;;
        "~/"*) chemin="$HOME/${chemin#\~/}" ;;
        /*)    : ;;
        *)     [[ -f "$HOME/.ssh/$chemin" ]] && chemin="$HOME/.ssh/$chemin" ;;
    esac
    [[ -f "$chemin" ]] && { printf '%s\n' "$chemin"; return 0; }
    return 1
}

ssh_reecrire_identite() {
    local bloc="$1" origine="$2" remplacement="$3"
    printf '%s\n' "$bloc" | awk -v orig="$origine" -v rempl="$remplacement" '
        {
            if (tolower($1) == "identityfile") {
                valeur = $0
                sub(/^[[:space:]]*[^[:space:]]+[[:space:]]+/, "", valeur)
                gsub(/"/, "", valeur)
                if (valeur == orig) { print "    IdentityFile " rempl; next }
            }
            print
        }
    '
}

ssh_ecrire_fichier_alias() {
    printf 'alias evsh="ssh -F %s"\n' "$coffre_lien_ssh" > "$coffre_fichier_alias"
    chmod 644 "$coffre_fichier_alias"
}

ssh_assurer_lien() {
    if [[ -L "$coffre_lien_ssh" ]]; then
        [[ "$(readlink "$coffre_lien_ssh")" == "$coffre_config_ssh" ]] || ln -sfn "$coffre_config_ssh" "$coffre_lien_ssh"
    elif [[ -e "$coffre_lien_ssh" ]]; then
        erreur "$coffre_lien_ssh existe et n'est pas un lien symbolique"
    else
        install -d -m 700 "$coffre_rep_config"; ln -s "$coffre_config_ssh" "$coffre_lien_ssh"
    fi
}

ssh_modele() {
    exiger_ouvert
    install -d -m 700 "$coffre_rep_config"
    [[ -f "$coffre_config_ssh" ]] && { confirmer "Une configuration existe déjà dans le coffre, la remplacer ?" || erreur "Opération annulée"; }
    cat > "$coffre_config_ssh" <<CFG
Host *
    IdentitiesOnly yes
    AddKeysToAgent no
    HashKnownHosts yes
    ServerAliveInterval 60
    ServerAliveCountMax 3
    UserKnownHostsFile $coffre_rep_ssh/known_hosts
CFG
    chmod 600 "$coffre_config_ssh"
    touch "$coffre_rep_ssh/known_hosts"; chmod 600 "$coffre_rep_ssh/known_hosts"
    ssh_ecrire_fichier_alias
    ssh_assurer_lien
}

ssh_importer() {
    exiger_ouvert
    local origine="$HOME/.ssh/config"
    [[ -f "$origine" ]] || erreur "Fichier source introuvable : $origine"
    local hotes=(); mapfile -t hotes < <(ssh_hotes_dans "$origine")
    (( ${#hotes[@]} > 0 )) || erreur "Aucun host déclaré dans $origine"
    local hote="${1:-}"
    if [[ -z "$hote" ]]; then
        local i; for i in "${!hotes[@]}"; do printf '%3d) %s\n' "$((i + 1))" "${hotes[i]}"; done
        local choix=""; read -r -p "Host à importer [1-${#hotes[@]}] : " choix || true
        [[ "$choix" =~ ^[0-9]+$ ]] && (( choix >= 1 && choix <= ${#hotes[@]} )) || erreur "Sélection invalide"
        hote="${hotes[choix - 1]}"
    else
        local trouve=0 h; for h in "${hotes[@]}"; do [[ "$h" == "$hote" ]] && trouve=1; done
        (( trouve == 1 )) || erreur "Host inconnu dans $origine : $hote"
    fi
    local bloc; bloc="$(ssh_extraire_bloc "$origine" "$hote")"
    [[ -n "$bloc" ]] || erreur "Impossible d'extraire le bloc de configuration du host $hote"
    if [[ -f "$coffre_config_ssh" ]] && ssh_hotes_dans "$coffre_config_ssh" | grep -qx "$hote"; then
        confirmer "Le host $hote existe déjà dans le coffre, le remplacer ?" || erreur "Import annulé"
        ssh_supprimer_bloc "$coffre_config_ssh" "$hote"
    fi
    local fichiers_cles=()
    mapfile -t fichiers_cles < <(printf '%s\n' "$bloc" | awk 'tolower($1) == "identityfile" { ligne = $0; sub(/^[[:space:]]*[^[:space:]]+[[:space:]]+/, "", ligne); gsub(/"/, "", ligne); print ligne }')
    local chemin_cle resolu base destination
    for chemin_cle in "${fichiers_cles[@]}"; do
        resolu="$(ssh_resoudre_chemin_cle "$chemin_cle")" || erreur "Clé privée introuvable pour $hote : $chemin_cle"
        base="$(basename "$resolu")"; destination="$coffre_rep_cles_ssh/${hote}_${base}"
        install -m 600 "$resolu" "$destination"
        [[ -f "${resolu}.pub" ]] && install -m 644 "${resolu}.pub" "${destination}.pub"
        bloc="$(ssh_reecrire_identite "$bloc" "$chemin_cle" "$destination")"
    done
    [[ -f "$coffre_config_ssh" ]] || { touch "$coffre_config_ssh"; chmod 600 "$coffre_config_ssh"; }
    printf '\n%s\n' "$bloc" >> "$coffre_config_ssh"
    chmod 600 "$coffre_config_ssh"
}

commande_ssh() {
    local sous_cmd="${1:-}"; [[ $# -gt 0 ]] && shift
    case "$sous_cmd" in
        template) ssh_modele ;;
        import)   ssh_importer "${1:-}" ;;
        *)        erreur "Sous-commande ssh inconnue : $sous_cmd (template, import)" ;;
    esac
}
