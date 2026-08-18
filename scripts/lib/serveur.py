#!/usr/bin/env python3
"""Serveur de transfert Miguation.

Ne sert que deux routes, toutes deux préfixées par un token aléatoire :

    /<token>/miguation.tar.gz
    /<token>/miguation.tar.gz.sha256

Toute autre requête reçoit un 404 — y compris « / ». C'est le point important :
`python3 -m http.server` sert le répertoire entier et en publie le listing, ce
qui exposait l'archive sans le token et révélait le token lui-même dans le
listing. Ici le token est réellement le seul moyen d'accès.
"""

import hmac
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

TAILLE_BLOC = 1 << 20  # 1 Mio


def construire_handler(token, chemin_archive, somme):
    route_archive = "/%s/miguation.tar.gz" % token
    route_somme = route_archive + ".sha256"

    class Handler(BaseHTTPRequestHandler):
        server_version = "Miguation"
        sys_version = ""

        def _route_demandee(self):
            """Compare en temps constant pour ne pas fuiter le token octet par octet."""
            chemin = self.path.split("?", 1)[0]
            if hmac.compare_digest(chemin, route_archive):
                return "archive"
            if hmac.compare_digest(chemin, route_somme):
                return "somme"
            return None

        def do_HEAD(self):
            self._servir(corps=False)

        def do_GET(self):
            self._servir(corps=True)

        def _servir(self, corps):
            quoi = self._route_demandee()
            if quoi is None:
                self.send_error(404, "Not Found")
                return

            if quoi == "somme":
                donnees = (somme + "  miguation.tar.gz\n").encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/plain; charset=utf-8")
                self.send_header("Content-Length", str(len(donnees)))
                self.end_headers()
                if corps:
                    self.wfile.write(donnees)
                return

            taille = os.path.getsize(chemin_archive)
            self.send_response(200)
            self.send_header("Content-Type", "application/gzip")
            self.send_header("Content-Length", str(taille))
            self.end_headers()
            if not corps:
                return
            with open(chemin_archive, "rb") as f:
                while True:
                    bloc = f.read(TAILLE_BLOC)
                    if not bloc:
                        break
                    try:
                        self.wfile.write(bloc)
                    except (BrokenPipeError, ConnectionResetError):
                        return

        def log_message(self, *args):
            pass  # pas de bruit dans le terminal de l'utilisateur

    return Handler


def main():
    if len(sys.argv) != 5:
        print("usage: serveur.py PORT TOKEN ARCHIVE SHA256", file=sys.stderr)
        return 2
    port, token, archive, somme = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
    if not os.path.isfile(archive):
        print("archive introuvable: %s" % archive, file=sys.stderr)
        return 1
    httpd = HTTPServer(("", port), construire_handler(token, archive, somme))
    httpd.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
