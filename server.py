#!/usr/bin/env python3
"""Simple HTTP server that serves both the viewer and the memory MD files."""

import os
import sys
from http.server import HTTPServer, SimpleHTTPRequestHandler

MEMORY_DIR = '/home/gong/.openclaw/workspace/memory'
VIEWER_DIR = '/home/gong/.openclaw/workspace-xiaozhushou/skills/isekai-companion/viewer'

class DualHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=VIEWER_DIR, **kwargs)

    def translate_path(self, path):
        if path.startswith('/workspace/'):
            # Serve memory files
            md_path = path[len('/workspace'):]
            full_path = os.path.join(MEMORY_DIR, md_path.lstrip('/'))
            if os.path.exists(full_path):
                return full_path
        # Default: serve from viewer directory
        return super().translate_path(path)

    def end_headers(self):
        # Add CORS headers for local dev
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Cache-Control', 'no-cache')
        super().end_headers()

    def log_message(self, format, *args):
        pass  # suppress logging

PORT = 8082
server = HTTPServer(('0.0.0.0', PORT), DualHandler)
print(f'Serving viewer → http://localhost:{PORT}/')
print(f'Memory files   → http://localhost:{PORT}/workspace/...')
sys.stdout.flush()
server.serve_forever()