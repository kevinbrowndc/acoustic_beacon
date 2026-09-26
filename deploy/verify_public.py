"""Read-only public HTTPS smoke check. Does not claim to verify DB provenance."""
import argparse
import sys
from urllib.parse import urlsplit
import httpx


def verify(origin):
    url = urlsplit(origin)
    if url.scheme != 'https' or not url.netloc or url.username or url.password or url.path not in ('', '/') or url.query or url.fragment:
        raise ValueError('Provide only a public HTTPS origin without credentials or a path')
    with httpx.Client(base_url=origin.rstrip('/'), timeout=60, follow_redirects=False) as client:
        for path in ['/health/live', '/health/ready', '/merchant/', '/merchant/app.js', '/merchant/styles.css', '/merchant/beacon-logo.png']:
            response = client.get(path)
            if response.status_code != 200:
                raise RuntimeError(f'{path}: expected 200, got {response.status_code}')
            print(f'PASS {path}')
        config = client.get('/api/v1/dashboard/config')
        config.raise_for_status()
        if config.json()['production'] is not True or config.json()['development_sign_in'] is not False:
            raise RuntimeError('Production configuration check failed')
        result = client.get('/api/v1/beacons/0xABC123/offers')
        result.raise_for_status()
        body = result.json()
        if not body.get('campaign') or not any(o['title'] == 'wookiemeat' for o in body.get('offers', [])):
            raise RuntimeError('Expected test campaign/content absent')
        print('PASS 0xABC123 -> campaign -> wookiemeat')
        unknown = client.get('/api/v1/beacons/0xFFFFFF/offers')
        if unknown.status_code != 404:
            raise RuntimeError('Unknown test ID is assigned or unexpected response; inspect before choosing another ID')
        print('PASS unknown beacon: 404')
        # Existing production identity integration is missing; never claim this is working.
        management = client.get('/api/v1/dashboard/workspace')
        print(f'Management endpoint HTTP {management.status_code}; authenticated workflow still requires production identity integration.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('origin')
    args = parser.parse_args()
    try:
        verify(args.origin)
    except Exception:
        print('Live verification did not pass. Inspect the endpoint securely; no credentials or response bodies logged.', file=sys.stderr)
        raise SystemExit(1) from None
