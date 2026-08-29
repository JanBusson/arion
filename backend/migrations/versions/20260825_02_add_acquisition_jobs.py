"""Add durable acquisition jobs and track provenance."""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "20260825_02"
down_revision: str | None = "20260822_01"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "acquisition_jobs",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("provider", sa.String(length=32), nullable=False),
        sa.Column("external_id", sa.String(length=64), nullable=False),
        sa.Column("candidate_title", sa.String(length=512), nullable=False),
        sa.Column("candidate_channel", sa.String(length=512), nullable=False),
        sa.Column("candidate_duration_seconds", sa.Integer(), nullable=True),
        sa.Column("candidate_thumbnail_url", sa.String(length=2048), nullable=True),
        sa.Column("candidate_page_url", sa.String(length=2048), nullable=False),
        sa.Column(
            "authorization_acknowledged_at",
            sa.DateTime(timezone=True),
            nullable=False,
        ),
        sa.Column("state", sa.String(length=32), nullable=False),
        sa.Column("phase", sa.String(length=64), nullable=False),
        sa.Column("progress_percent", sa.Integer(), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False),
        sa.Column("lease_expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("failure_code", sa.String(length=64), nullable=True),
        sa.Column("failure_message", sa.String(length=512), nullable=True),
        sa.Column("track_id", sa.Uuid(), nullable=True),
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
        sa.CheckConstraint(
            "state IN ('queued', 'downloading', 'processing', "
            "'completed', 'failed', 'cancelled')",
            name="ck_acquisition_jobs_state",
        ),
        sa.CheckConstraint(
            "progress_percent >= 0 AND progress_percent <= 100",
            name="ck_acquisition_jobs_progress_percent",
        ),
        sa.ForeignKeyConstraint(["track_id"], ["tracks.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_acquisition_jobs_external_id",
        "acquisition_jobs",
        ["external_id"],
    )
    op.create_index("ix_acquisition_jobs_state", "acquisition_jobs", ["state"])

    op.create_table(
        "track_sources",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("track_id", sa.Uuid(), nullable=False),
        sa.Column("provider", sa.String(length=32), nullable=False),
        sa.Column("external_id", sa.String(length=64), nullable=False),
        sa.Column("source_page_url", sa.String(length=2048), nullable=False),
        sa.Column("source_title", sa.String(length=512), nullable=False),
        sa.Column("source_channel", sa.String(length=512), nullable=False),
        sa.Column(
            "acquired_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["track_id"], ["tracks.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("provider", "external_id", name="uq_track_sources_origin"),
    )
    op.create_index("ix_track_sources_track_id", "track_sources", ["track_id"])


def downgrade() -> None:
    op.drop_index("ix_track_sources_track_id", table_name="track_sources")
    op.drop_table("track_sources")
    op.drop_index("ix_acquisition_jobs_state", table_name="acquisition_jobs")
    op.drop_index("ix_acquisition_jobs_external_id", table_name="acquisition_jobs")
    op.drop_table("acquisition_jobs")
