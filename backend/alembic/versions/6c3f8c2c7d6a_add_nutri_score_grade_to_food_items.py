"""add nutri_score_grade to food_items

Revision ID: 6c3f8c2c7d6a
Revises: 2cbda5149116
Create Date: 2026-01-28 20:00:00.000000

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = "6c3f8c2c7d6a"
down_revision = "2cbda5149116"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "food_items",
        sa.Column("nutri_score_grade", sa.String(length=5), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("food_items", "nutri_score_grade")
