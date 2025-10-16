#!/usr/bin/env python3
"""
mock_http_server.py - Simple HTTP server for testing HTTPHelper

This server accepts GET and POST requests and echoes back the received data,
allowing us to verify that form-encoded POST data is being sent correctly.
"""

from http.server import HTTPServer, BaseHTTPRequestHandler
import json
import urllib.parse
from datetime import datetime

class MockHTTPHandler(BaseHTTPRequestHandler):
    """Handler for mock HTTP requests"""

    def log_message(self, format, *args):
        """Custom log format"""
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        print(f"[{timestamp}] {self.client_address[0]} - {format % args}")

    def _get_status_message(self, status_code):
        """Get HTTP status message"""
        messages = {
            200: 'OK',
            201: 'Created',
            204: 'No Content',
            400: 'Bad Request',
            401: 'Unauthorized',
            403: 'Forbidden',
            404: 'Not Found',
            500: 'Internal Server Error',
            502: 'Bad Gateway',
            503: 'Service Unavailable'
        }
        return messages.get(status_code, 'Unknown')

    def _send_json_response(self, status_code, data):
        """Send a JSON response"""
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()

        response = json.dumps(data, indent=2)
        self.wfile.write(response.encode('utf-8'))

    def do_GET(self):
        """Handle GET requests"""
        print("\n" + "="*60)
        print(f"GET request received: {self.path}")
        print("="*60)

        # Parse query parameters
        parsed_path = urllib.parse.urlparse(self.path)
        query_params = urllib.parse.parse_qs(parsed_path.query)

        # Flatten single-item lists in query params
        query_dict = {k: v[0] if len(v) == 1 else v for k, v in query_params.items()}

        # Handle special endpoints like httpbin.org
        path = parsed_path.path

        # Status code endpoints: /status/XXX
        if path.startswith('/status/'):
            status_code = int(path.split('/')[-1])
            response_data = {
                'status': status_code,
                'message': self._get_status_message(status_code)
            }
            self._send_json_response(status_code, response_data)
            return

        # Delay endpoint: /delay/X
        if path.startswith('/delay/'):
            import time
            delay_seconds = int(path.split('/')[-1])
            time.sleep(delay_seconds)

        # HTML endpoint
        if path == '/html':
            self.send_response(200)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            html = '<html><head><title>Test Page</title></head><body><h1>Test</h1></body></html>'
            self.wfile.write(html.encode('utf-8'))
            return

        # JSON endpoint
        if path == '/json':
            response_data = {
                'test': 'data',
                'number': 123,
                'nested': {'key': 'value'}
            }
            self._send_json_response(200, response_data)
            return

        # Headers endpoint
        if path == '/headers':
            response_data = {
                'headers': dict(self.headers)
            }
            self._send_json_response(200, response_data)
            return

        # User-agent endpoint
        if path == '/user-agent':
            response_data = {
                'user-agent': self.headers.get('User-Agent', '')
            }
            self._send_json_response(200, response_data)
            return

        # Default GET response
        response_data = {
            'method': 'GET',
            'path': parsed_path.path,
            'query': query_dict,
            'headers': dict(self.headers),
            'url': f'http://{self.headers.get("Host", "localhost")}{self.path}',
            'timestamp': datetime.now().isoformat(),
            'success': True
        }

        print(f"Query parameters: {query_dict}")

        self._send_json_response(200, response_data)

    def do_POST(self):
        """Handle POST requests"""
        print("\n" + "="*60)
        print(f"POST request received: {self.path}")
        print("="*60)

        # Get content length
        content_length = int(self.headers.get('Content-Length', 0))

        # Read POST data
        post_data = self.rfile.read(content_length).decode('utf-8') if content_length > 0 else ''

        print(f"Content-Type: {self.headers.get('Content-Type')}")
        print(f"Content-Length: {content_length}")
        print(f"Raw POST data: {post_data}")

        # Parse form data
        form_data = {}
        json_data = None
        content_type = self.headers.get('Content-Type', '')

        if 'application/x-www-form-urlencoded' in content_type:
            # Parse URL-encoded form data
            if post_data:
                parsed_data = urllib.parse.parse_qs(post_data)
                # Flatten single-item lists
                form_data = {k: v[0] if len(v) == 1 else v for k, v in parsed_data.items()}
                print(f"Parsed form data: {form_data}")
        elif 'application/json' in content_type:
            # Parse JSON data
            if post_data:
                json_data = json.loads(post_data)
                print(f"Parsed JSON data: {json_data}")
        else:
            if post_data:
                form_data = {'raw': post_data}

        # Build response similar to httpbin.org
        response_data = {
            'method': 'POST',
            'path': self.path,
            'headers': dict(self.headers),
            'url': f'http://{self.headers.get("Host", "localhost")}{self.path}',
            'origin': self.client_address[0],
            'timestamp': datetime.now().isoformat(),
            'success': True
        }

        # Add parsed data to response
        if form_data:
            response_data['form'] = form_data
            response_data['form_data'] = form_data  # Alias for compatibility
        if json_data:
            response_data['json'] = json_data
        if post_data:
            response_data['data'] = post_data
            response_data['raw_body'] = post_data  # Alias for compatibility

        self._send_json_response(200, response_data)

    def do_OPTIONS(self):
        """Handle OPTIONS requests (CORS preflight)"""
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

def run_server(port=8888):
    """Run the mock HTTP server"""
    server_address = ('', port)
    httpd = HTTPServer(server_address, MockHTTPHandler)

    print("=" * 60)
    print(f"Mock HTTP Server Started")
    print("=" * 60)
    print(f"Listening on: http://localhost:{port}")
    print(f"Started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("\nEndpoints:")
    print(f"  GET  http://localhost:{port}/test")
    print(f"  POST http://localhost:{port}/test")
    print("\nPress Ctrl+C to stop the server")
    print("=" * 60)
    print()

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n\nShutting down server...")
        httpd.shutdown()
        print("Server stopped.")

if __name__ == '__main__':
    import sys

    port = 8888
    if len(sys.argv) > 1:
        try:
            port = int(sys.argv[1])
        except ValueError:
            print(f"Invalid port: {sys.argv[1]}, using default 8888")

    run_server(port)
