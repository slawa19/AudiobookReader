#!/usr/bin/env python3
"""Раздаёт веб-сборку прототипа (build/web) на заданном адресе без кэша браузера.

Без `Cache-Control: no-cache` браузер после пересборки показывает старую версию.
Запускается из scripts/prototype.sh, руками не нужен.
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
