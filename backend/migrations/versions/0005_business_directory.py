"""Optional merchant website and explicit directory consent; existing accounts opt out."""
from alembic import op
import sqlalchemy as sa
revision='0005'
down_revision='0004'
branch_labels=None
depends_on=None

def upgrade():
    op.add_column('merchants',sa.Column('website',sa.String(2048),nullable=True))
    op.add_column('merchants',sa.Column('directory_opt_in',sa.Boolean(),server_default=sa.false(),nullable=False))

def downgrade():
    op.drop_column('merchants','directory_opt_in')
    op.drop_column('merchants','website')
