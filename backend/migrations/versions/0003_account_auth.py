"""Persistent account credentials, sessions and shared login throttling."""
from alembic import op
import sqlalchemy as sa
revision = '0003'
down_revision = '0002'
branch_labels = None
depends_on = None

def upgrade():
    op.create_table('account_credentials',
        sa.Column('user_id',sa.Integer(),sa.ForeignKey('users.id',ondelete='CASCADE'),primary_key=True),
        sa.Column('password_hash',sa.String(256),nullable=False),
        sa.Column('enabled',sa.Boolean(),nullable=False))
    op.create_table('account_sessions',
        sa.Column('token_hash',sa.String(64),primary_key=True),
        sa.Column('user_id',sa.Integer(),sa.ForeignKey('users.id',ondelete='CASCADE'),nullable=False),
        sa.Column('expires_at',sa.DateTime(timezone=True),nullable=False))
    op.create_index('ix_account_sessions_user_id','account_sessions',['user_id'])
    op.create_index('ix_account_sessions_expires_at','account_sessions',['expires_at'])
    op.create_table('login_rates',
        sa.Column('key',sa.String(100),primary_key=True),
        sa.Column('count',sa.Integer(),nullable=False),
        sa.Column('expires_at',sa.DateTime(timezone=True),nullable=False))
    op.create_index('ix_login_rates_expires_at','login_rates',['expires_at'])

def downgrade():
    op.drop_table('login_rates')
    op.drop_table('account_sessions')
    op.drop_table('account_credentials')
