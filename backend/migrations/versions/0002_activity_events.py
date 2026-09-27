"""Add merchant-scoped customer events. No existing data is modified."""
from alembic import op
import sqlalchemy as sa
revision = '0002'
down_revision = '0001'
branch_labels = None
depends_on = None

def upgrade():
    op.create_table('activity_events',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('event_key', sa.String(128), nullable=False, unique=True),
        sa.Column('merchant_id', sa.Integer(), sa.ForeignKey('merchants.id', ondelete='RESTRICT'), nullable=False),
        sa.Column('kind', sa.String(16), nullable=False),
        sa.Column('occurred_at', sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint("kind IN ('detections', 'views', 'saves', 'actions')", name='ck_activity_kind'))
    op.create_index('ix_activity_merchant_time', 'activity_events', ['merchant_id', 'occurred_at'])

def downgrade():
    op.drop_table('activity_events')
