"""Store private merchant signup contact name."""
from alembic import op
import sqlalchemy as sa
revision='0004'
down_revision='0003'
branch_labels=None
depends_on=None

def upgrade():
    op.add_column('merchants',sa.Column('contact_name',sa.String(200),nullable=True))

def downgrade():
    op.drop_column('merchants','contact_name')
