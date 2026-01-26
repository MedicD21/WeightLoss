"""Body metrics and daily tracking models."""
import uuid
from datetime import datetime, date
from typing import Optional

from sqlalchemy import String, Float, Integer, ForeignKey, DateTime, Date, Boolean
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class BodyWeightEntry(Base):
    """Body weight log entry."""

    __tablename__ = "body_weight_entries"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("user_profiles.id", ondelete="CASCADE"), index=True
    )

    # Weight
    weight_kg: Mapped[float] = mapped_column(Float)
    timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)

    # Optional details
    notes: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    body_fat_percent: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    muscle_mass_kg: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    water_percent: Mapped[Optional[float]] = mapped_column(Float, nullable=True)

    # Sync
    is_synced: Mapped[bool] = mapped_column(Boolean, default=True)
    local_id: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    source: Mapped[str] = mapped_column(String(50), default="manual")  # manual, health_kit, chat


class WaterEntry(Base):
    """Water intake log entry."""

    __tablename__ = "water_entries"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("user_profiles.id", ondelete="CASCADE"), index=True
    )

    # Water amount
    amount_ml: Mapped[int] = mapped_column(Integer)
    timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)

    # Sync
    is_synced: Mapped[bool] = mapped_column(Boolean, default=True)
    local_id: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    source: Mapped[str] = mapped_column(String(50), default="manual")  # manual, chat


class StepsDaily(Base):
    """Daily step count (aggregated from HealthKit)."""

    __tablename__ = "steps_daily"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("user_profiles.id", ondelete="CASCADE"), index=True
    )

    # Date and steps
    date: Mapped[date] = mapped_column(Date, index=True)
    steps: Mapped[int] = mapped_column(Integer)

    # Additional metrics from HealthKit
    distance_km: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    flights_climbed: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    active_energy_kcal: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)

    # Source
    source: Mapped[str] = mapped_column(String(50), default="health_kit")
    synced_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))

    class Config:
        # Unique constraint on user_id + date
        __table_args__ = (
            {"sqlite_autoincrement": True},
        )


class ProgressSnapshot(Base):
    """Computed progress metrics snapshot."""

    __tablename__ = "progress_snapshots"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("user_profiles.id", ondelete="CASCADE"), index=True
    )

    # Snapshot date
    date: Mapped[date] = mapped_column(Date, index=True)

    # Weight metrics
    weight_kg: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    weight_7d_avg: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    weight_change_7d: Mapped[Optional[float]] = mapped_column(Float, nullable=True)

    # Nutrition metrics (daily averages)
    avg_calories: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    avg_protein_g: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    avg_carbs_g: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    avg_fat_g: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    calorie_adherence_percent: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    protein_adherence_percent: Mapped[Optional[float]] = mapped_column(Float, nullable=True)

    # Activity metrics
    avg_steps: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    workouts_count: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    total_workout_min: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)

    # Water
    avg_water_ml: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    water_goal_hit_days: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
