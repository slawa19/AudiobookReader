#!/usr/bin/env python3
"""Serves the prototype web build (build/web) at the given address with browser caching disabled.

Without `Cache-Control: no-cache` the browser shows the old version after a rebuild.
Started from scripts/prototype.sh; not needed by hand.
"""
import functools
import http.server
import sys


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))


def main():
    host, port, root = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    handler = functools.partial(NoCacheHandler, directory=root)
    with http.server.ThreadingHTTPServer((host, port), handler) as httpd:
        httpd.serve_forever()


if __name__ == "__main__":
    main()
