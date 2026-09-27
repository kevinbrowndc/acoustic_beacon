"""Password authentication over the existing private dashboard session boundary."""
import hashlib
import hmac
import secrets
import threading
from datetime import datetime, timedelta, timezone
from fastapi import HTTPException
from sqlalchemy import delete, select
from .models import AccountCredential, AccountSession, LoginRate, User
from .lookup import aware

COOKIE = '__Host-ab_session'
HASH_LOCK = threading.BoundedSemaphore(1)  # Bound scrypt memory under concurrent attempts.
DUMMY = 'scrypt$' + '00'*16 + '$' + '00'*64

def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()

def hash_password(password, salt=None):
    salt = salt or secrets.token_bytes(16)
    with HASH_LOCK:
        value = hashlib.scrypt(password.encode('utf-8'), salt=salt, n=2**17, r=8, p=1, maxmem=256*1024*1024)
    return 'scrypt$' + salt.hex() + '$' + value.hex()

def verify_password(password, encoded):
    try:
        kind, salt, _ = encoded.split('$')
        if kind != 'scrypt':
            return False
        return hmac.compare_digest(hash_password(password, bytes.fromhex(salt)), encoded)
    except (ValueError, TypeError):
        return False

def require_origin(request):
    # Explicit public origin: the TLS-terminating proxy intentionally exposes HTTP internally.
    expected = request.app.state.settings.dashboard_public_origin
    if request.headers.get('origin') != expected:
        raise HTTPException(403, 'Cross-origin session actions are not allowed')

def rate_limit(session, email, now):
    from sqlalchemy.dialects.postgresql import insert as pg_insert
    from sqlalchemy.dialects.sqlite import insert as sqlite_insert
    insert = pg_insert if session.bind.dialect.name == 'postgresql' else sqlite_insert
    session.execute(delete(LoginRate).where(LoginRate.expires_at < now))
    # Shared DB counters work across processes/restarts. No trust in forwarded client IPs.
    for key, seconds, limit in [('global',60,30), (digest(email),900,10)]:
        bucket = int(now.timestamp()) // seconds
        stmt = insert(LoginRate).values(key=f'{key}:{bucket}', count=1, expires_at=now+timedelta(seconds=seconds*2))
        count = session.execute(stmt.on_conflict_do_update(index_elements=['key'],set_={'count':LoginRate.count+1}).returning(LoginRate.count)).scalar_one()
        if count > limit:
            session.commit()
            raise HTTPException(429, 'Too many sign-in attempts. Please try again later.', headers={'Retry-After':str(seconds)})
    session.commit()

def authenticate(request, response, session, email, password):
    require_origin(request)
    now = datetime.now(timezone.utc)
    rate_limit(session, email, now)
    user = session.scalar(select(User).where(User.email == email))
    credential = session.get(AccountCredential, user.id) if user else None
    valid = verify_password(password, credential.password_hash if credential else DUMMY)
    if not valid or not credential or not credential.enabled:
        raise HTTPException(401, 'Email or password is incorrect')
    previous = request.cookies.get(COOKIE)
    if previous:
        session.execute(delete(AccountSession).where(AccountSession.token_hash == digest(previous)))
    session.execute(delete(AccountSession).where(AccountSession.expires_at <= now))
    token = secrets.token_urlsafe(32)
    session.add(AccountSession(token_hash=digest(token),user_id=user.id,expires_at=now+timedelta(hours=8)))
    session.commit()
    response.set_cookie(COOKIE,token,httponly=True,secure=True,samesite='strict',max_age=28800,path='/')
    response.headers['Cache-Control']='no-store'
    return {'csrf_token':digest(token+':csrf')}

def current_user(request, session):
    token = request.cookies.get(COOKIE,'')
    if not token or len(token)>100:
        raise HTTPException(401,'Sign in to your workspace',headers={'Cache-Control':'no-store'})
    entry = session.get(AccountSession,digest(token))
    credential = session.get(AccountCredential,entry.user_id) if entry else None
    if not entry or aware(entry.expires_at)<=datetime.now(timezone.utc) or not credential or not credential.enabled:
        raise HTTPException(401,'Sign in to your workspace',headers={'Cache-Control':'no-store'})
    if request.method not in {'GET','HEAD'}:
        require_origin(request)
        if not hmac.compare_digest(request.headers.get('x-csrf-token',''),digest(token+':csrf')):
            raise HTTPException(403,'Session verification failed. Refresh and try again.')
    user = session.get(User,entry.user_id)
    if not user:
        raise HTTPException(401,'Account unavailable')
    return user

def sign_out(request,response,session):
    session.execute(delete(AccountSession).where(AccountSession.token_hash==digest(request.cookies.get(COOKIE,''))))
    session.commit()
    response.delete_cookie(COOKIE,path='/',secure=True,httponly=True,samesite='strict')
    response.headers['Cache-Control']='no-store'
    return {'signed_out':True}
