/*
 * Exécutable de ~/Applications/Firefox (hors VPN).app : passe la main
 * au script ~/.local/bin/firefox-novpn.
 *
 * Un binaire natif plutôt que le script lui-même : LaunchServices ne
 * peut pas déduire l'architecture d'un script, et lance alors l'app sous
 * Rosetta. Toute la chaîne lancée ensuite (Firefox compris) héritait de
 * cette préférence x86_64.
 *
 * Compilé sur place par firefox-novpn-setup.
 */
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
  const char *home = getenv("HOME");
  char script[PATH_MAX];
  int n;

  (void)argc;
  if (home == NULL) {
    fprintf(stderr, "firefox-novpn : HOME non défini\n");
    return 1;
  }
  n = snprintf(script, sizeof script, "%s/.local/bin/firefox-novpn", home);
  if (n < 0 || (size_t)n >= sizeof script) {
    fprintf(stderr, "firefox-novpn : chemin trop long\n");
    return 1;
  }
  argv[0] = script;
  execv(script, argv);
  perror(script);
  return 127;
}
