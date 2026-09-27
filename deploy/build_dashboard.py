"""Package the unchanged native dashboard on a Python-only hosting builder."""
from pathlib import Path
import shutil


def build(root=None):
    root = Path(root) if root else Path(__file__).resolve().parents[1]
    dashboard = root / 'dashboard'
    destination = dashboard / 'dist'
    destination.mkdir(parents=True, exist_ok=True)
    # Explicit allowlist: no .env files, databases, tests or development tooling.
    names = ['index.html', 'demo.html', 'demo.js', 'app.js', 'api.js', 'domain.js', 'views.js', 'styles.css']
    for name in names:
        shutil.copyfile(dashboard / 'src' / name, destination / name)
    shutil.copyfile(dashboard / 'public' / 'beacon-logo.png', destination / 'beacon-logo.png')
    return destination


if __name__ == '__main__':
    build()
    print('Dashboard assets packaged. No database connection or credentials used.')
