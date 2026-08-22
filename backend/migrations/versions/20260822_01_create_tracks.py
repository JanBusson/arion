"""Create the initial track catalog."""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260822_01"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "tracks",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("sha256", sa.String(length=64), nullable=False),
        sa.Column("audio_storage_key", sa.String(length=255), nullable=False),
        sa.Column("cover_storage_key", sa.String(length=255), nullable=True),
        sa.Column("cover_media_type", sa.String(length=32), nullable=True),
        sa.Column("title", sa.String(length=512), nullable=False),
        sa.Column("artist", sa.String(length=512), nullable=False),
        sa.Column("album", sa.String(length=512), nullable=False),
        sa.Column("duration_ms", sa.BigInteger(), nullable=False),
        sa.Column("codec", sa.String(length=64), nullable=False),
        sa.Column("bitrate_kbps", sa.Integer(), nullable=True),
        sa.Column("sample_rate_hz", sa.Integer(), nullable=False),
        sa.Column("original_filename", sa.String(length=1024), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("audio_storage_key"),
        sa.UniqueConstraint("cover_storage_key"),
        sa.UniqueConstraint("sha256"),
    )


def downgrade() -> None:
    op.drop_table("tracks")
