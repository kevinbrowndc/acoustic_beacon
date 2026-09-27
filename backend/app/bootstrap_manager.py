"""Private operator command: migrate and provision a Manager, never seed demo content."""
import getpass
import warnings
from pathlib import Path
from alembic import command
from alembic.config import Config
from sqlalchemy import select
from sqlalchemy.orm import Session
from .auth import hash_password
from .config import Settings
from .database import make_engine
from .models import User, AccountCredential

def provision(session, email, password):
    email=email.strip().lower()
    if len(email)>320 or '@' not in email or any(c.isspace() for c in email):
        raise ValueError('Enter a valid email address')
    if not 15 <= len(password) <= 256:
        raise ValueError('Use a password or passphrase of 15 to 256 characters')
    user=session.scalar(select(User).where(User.email==email))
    if user and (user.role!='manager' or session.get(AccountCredential,user.id)):
        raise ValueError('Account already exists; no role or password was changed')
    if not user:
        user=User(email=email,role='manager');session.add(user);session.flush()
    session.add(AccountCredential(user_id=user.id,password_hash=hash_password(password),enabled=True))
    session.flush()
    return user

def main():
    settings=Settings()
    config=Config(str(Path(__file__).resolve().parents[1]/'alembic.ini'))
    config.attributes['database_url']=settings.database_url.get_secret_value()
    # Existing additive migration path; never calls a development seed.
    command.upgrade(config,'head')
    email=input('Manager email: ').strip()
    with warnings.catch_warnings():
        warnings.simplefilter('error',getpass.GetPassWarning)
        password=getpass.getpass('Manager password (15+ characters, hidden): ')
        confirmation=getpass.getpass('Confirm password (hidden): ')
    if password!=confirmation:
        raise SystemExit('Passwords did not match; no account was created')
    engine=make_engine(settings.database_url.get_secret_value())
    try:
        with Session(engine) as session, session.begin():
            provision(session,email,password)
        print('Manager account ready. Sign in at https://merchant.acousticbeacon.com/merchant/')
    except ValueError as error:
        raise SystemExit(str(error)) from None
    finally:
        engine.dispose()

if __name__=='__main__':
    main()
