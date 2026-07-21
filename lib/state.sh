conteneur_existe() { [[ -f "$coffre_conteneur" ]]; }
mapper_actif() { [[ -e "/dev/mapper/$coffre_mapper" ]]; }
coffre_monte() { findmnt -rn "$coffre_point_montage" >/dev/null 2>&1; }

etat_coffre() {
    if ! conteneur_existe; then printf 'absent\n'
    elif coffre_monte; then printf 'ouvert\n'
    elif mapper_actif; then printf 'deverrouille\n'
    else printf 'ferme\n'; fi
}

exiger_ouvert() { [[ "$(etat_coffre)" == ouvert ]] || erreur "Cette opération nécessite un coffre ouvert (coffre open)"; }
