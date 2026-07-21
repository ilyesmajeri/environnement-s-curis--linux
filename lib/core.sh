coffre_rep_config="${XDG_CONFIG_HOME:-$HOME/.config}/coffre"
coffre_rep_donnees="$HOME/.local/share/coffre"
coffre_conteneur="$coffre_rep_donnees/conteneur.luks"
coffre_mapper="coffre-$(id -un)"
coffre_point_montage="$HOME/.coffre"

coffre_rep_ssh="$coffre_point_montage/ssh"
coffre_config_ssh="$coffre_rep_ssh/config"
coffre_rep_cles_ssh="$coffre_rep_ssh/cles"
coffre_rep_gpg="$coffre_point_montage/gpg"
coffre_rep_gpg_pub="$coffre_rep_gpg/publiques"
coffre_rep_gpg_priv="$coffre_rep_gpg/privees"
coffre_lien_ssh="$coffre_rep_config/ssh-config"
coffre_fichier_alias="$coffre_rep_config/alias.sh"

erreur() { printf 'coffre: %s\n' "$*" >&2; exit 1; }
confirmer() { local r=""; read -r -p "$1 [o/N] " r || true; [[ "$r" == [oO] ]]; }
confirmer_mot() { local r=""; read -r -p "$1 (tapez $2 pour confirmer) : " r || true; [[ "$r" == "$2" ]]; }
