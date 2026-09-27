"""Same-origin production dashboard delivery without enabling development auth."""
from fastapi.testclient import TestClient
from app.config import Settings
from app.database import make_engine
from app.main import create_app


def test_production_dashboard_entry_and_assets():
    settings = Settings(environment='production', database_url='postgresql://fake:fake@localhost/fake', _env_file=None)
    engine = make_engine('sqlite://')
    try:
        with TestClient(create_app(settings, engine), base_url='https://beacon.example.com') as client:
            response = client.get('/', follow_redirects=False)
            assert response.status_code == 307
            assert response.headers['location'] == '/merchant/'
            page = client.get('/merchant/')
            assert page.status_code == 200
            assert 'Acoustic Beacon' in page.text
            for asset, content_type in [('app.js','javascript'), ('activity.js','javascript'), ('api.js','javascript'), ('domain.js','javascript'), ('views.js','javascript'), ('styles.css','text/css'), ('beacon-logo.png','image/png')]:
                response = client.get('/merchant/' + asset)
                assert response.status_code == 200
                assert content_type in response.headers['content-type']
            config = client.get('/api/v1/dashboard/config').json()
            assert config['production'] is True
            assert config['api_base_url'] == ''  # Browser uses its real HTTPS origin.
            assert config['development_sign_in'] is False
            assert client.post('/api/v1/dashboard/dev-session', json={'role':'merchant'}).status_code == 404
            assert client.get('/api/v1/dashboard/workspace').status_code == 401
            assert client.get('/api/v1/dashboard/activity').status_code == 401
    finally:
        engine.dispose()

def test_public_demo_is_unauthenticated_and_network_isolated(client):
    response = client.get('/demo')
    assert response.status_code == 200
    assert 'set-cookie' not in response.headers
    assert "connect-src 'none'" in response.headers['content-security-policy']
    assert 'https://acousticbeacon.com/assets/social-card.jpg' in response.text
    assert client.get('/api/v1/dashboard/workspace').status_code in (401, 503)
