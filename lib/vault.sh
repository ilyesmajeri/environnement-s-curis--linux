luks_formater() { sudo cryptsetup luksFormat --type luks2 "$coffre_conteneur" || erreur "Échec de l'initialisation LUKS"; }
luks_ouvrir() { sudo cryptsetup luksOpen "$coffre_conteneur" "$coffre_mapper" || erreur "Phrase secrète incorrecte ou conteneur invalide"; }

monter_coffre() {
    sudo mount -o nodev,nosuid "/dev/mapper/$coffre_mapper" "$coffre_point_montage" || erreur "Échec du montage sur $coffre_point_montage"
    sudo chown "$(id -un):$(id -gn)" "$coffre_point_montage"
    chmod 700 "$coffre_point_montage"
}

creer_arborescence() { install -d -m 700 "$coffre_rep_ssh" "$coffre_rep_cles_ssh" "$coffre_rep_gpg" "$coffre_rep_gpg_pub" "$coffre_rep_gpg_priv"; }

installer_coffre() {
    [[ "$(etat_coffre)" == absent ]] || erreur "Un coffre existe déjà, suppression manuelle requise avant réinstallation"
    install -d -m 700 "$coffre_rep_donnees" "$coffre_point_montage"
    dd if=/dev/zero of="$coffre_conteneur" bs=5M count=1024 status=none || erreur "Échec de l'allocation du conteneur"
    chmod 600 "$coffre_conteneur"
    luks_formater
    luks_ouvrir
    sudo mkfs.ext4 -q -L coffre "/dev/mapper/$coffre_mapper" || erreur "Échec de la création du système de fichiers"
    monter_coffre
    creer_arborescence
    sync
    sudo umount "$coffre_point_montage" || erreur "Échec du démontage final"
    sudo cryptsetup luksClose "$coffre_mapper" || erreur "Échec de la fermeture LUKS finale"
}

ouvrir_coffre() {
    case "$(etat_coffre)" in
        absent)       erreur "Aucun coffre installé, lancez d'abord 'coffre install'" ;;
        ouvert)       return 0 ;;
        deverrouille) : ;;
        ferme)        luks_ouvrir ;;
    esac
    install -d -m 700 "$coffre_point_montage"
    monter_coffre
    creer_arborescence
    ssh_assurer_lien
}

fermer_coffre() {
    case "$(etat_coffre)" in
        absent)       erreur "Aucun coffre installé" ;;
        ferme)        return 0 ;;
        deverrouille) sudo cryptsetup luksClose "$coffre_mapper" || erreur "Échec de la fermeture LUKS"; return 0 ;;
        ouvert)       : ;;
    esac
    sync
    sudo umount "$coffre_point_montage" || erreur "Échec du démontage (coffre occupé ?)"
    sudo cryptsetup luksClose "$coffre_mapper" || erreur "Échec de la fermeture LUKS"
}
