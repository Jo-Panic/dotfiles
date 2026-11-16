/*
 * mullvad-exclude (macOS) : exécute une commande hors du tunnel Mullvad.
 * Équivalent du mullvad-exclude Linux :  mullvad-exclude <commande> [args…]
 *
 * Mullvad exclut par chemin exact d'exécutable, et l'exclusion se transmet
 * aux processus enfants, y compris à travers exec. Ce binaire, exclu dans
 * Mullvad, se remplace donc simplement par la commande demandée.
 *
 * Compilé sur place par firefox-novpn-setup, plutôt que copié depuis
 * /usr/bin/env : les binaires système n'ont qu'une tranche arm64e (en plus
 * de x86_64), réservée aux binaires d'Apple. Hors de /usr/bin, le noyau
 * refuse cette tranche et se rabat sur x86_64, donc sur Rosetta, et toute
 * la chaîne lancée ensuite (Firefox compris) reste en Intel.
 * Compilé ici, le binaire est arm64 natif, et ce qu'il lance aussi.
 */
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
  if (argc < 2) {
    fprintf(stderr, "usage : mullvad-exclude <commande> [arguments…]\n");
    return 2;
  }
  execvp(argv[1], &argv[1]);
  /* Codes de retour de env(1) : 127 introuvable, 126 non exécutable. */
  fprintf(stderr, "mullvad-exclude : %s : %s\n", argv[1], strerror(errno));
  return errno == ENOENT ? 127 : 126;
}
