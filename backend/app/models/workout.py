"""Workout planning and logging models."""
import enum
import uuid
from datetime import datetime
from typing import Optional, List

from sqlalchemy import Enum, String, Float, Integer, Boolean, ForeignKey, DateTime, Text
from sqlalchemy.dialects.postgresql import UUID, ARRAY
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class WorkoutType(str, enum.Enum):
    """Type of workout."""
    STRENGTH = "strength"
    CARDIO = "cardio"
    HIIT = "hiit"
    FLEXIBILITY = "flexibility"
    SPORTS = "sports"
    WALKING = "walking"
    RUNNING = "running"
    CYCLING = "cycling"
    SWIMMING = "swimming"
    OTHER = "other"


class LogSource(str, enum.Enum):
    """Source of workout log."""
    MANUAL = "manual"
    HEALTH_KIT = "health_kit"
    CHAT = "chat"


class MuscleGroup(str, enum.Enum):
    """Muscle groups for exercises."""
    CHEST = "chest"
    BACK = "back"
    SHOULDERS = "shoulders"
    BICEPS = "biceps"
    TRICEPS = "triceps"
    FOREARMS = "forearms"
    CORE = "core"
    QUADS = "quads"
    HAMSTRINGS = "hamstrings"
    GLUTES = "glutes"
    CALVES = "calves"
    FULL_BODY = "full_body"
    CARDIO = "cardio"


class WorkoutPlan(Base):
    """Workout plan template."""

    __tablename__ = "workout_plans"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("user_profiles.id", ondelete="CASCADE"), index=True
    )

    # Plan info
    name: Mapped[str] = mapped_column(String(200))
    description: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    workout_type: Mapped[WorkoutType] = mapped_column(Enum(WorkoutType))

    # Schedule (0=Monday, 6=Sunday)
    scheduled_days: Mapped[Optional[List[int]]] = mapped_column(ARRAY(Integer), nullable=True)
    estimated_duration_min: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)

    # Status
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    order_index: Mapped[int] = mapped_column(Integer, default=0)

    # Relationships
    exercises: Mapped[List["WorkoutExercise"]] = relationship(
        "WorkoutExercise", back_populates="plan", cascade="all, delete-orphan",
        order_by="WorkoutExercise.order_index"
    )
    logs: Mapped[List["WorkoutLog"]] = relationship("WorkoutLog", back_populates="plan")


class WorkoutExercise(Base):
    """Exercise within a workout plan."""

    __tablename__ = "workout_exercises"

    plan_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("workout_plans.id", ondelete="CASCADE"), index=True
    )

    # Exercise info
    name: Mapped[str] = mapped_column(String(200))
    muscle_group: Mapped[Optional[MuscleGroup]] = mapped_column(Enum(MuscleGroup), nullable=True)
    equipment: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)

    # Sets and reps (target)
    sets: Mapped[int] = mapped_column(Integer, default=3)
    reps_min: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    reps_max: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    duration_sec: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)  # For timed exercises

    # Rest
    rest_sec: Mapped[int] = mapped_column(Integer, default=60)

    # Order in workout
    order_index: Mapped[int] = mapped_column(Integer, default=0)

    # Superset grouping (optional)
    superset_group: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)

    # Relationships
    plan: Mapped["WorkoutPlan"] = relationship("WorkoutPlan", back_populates="exercises")


class WorkoutLog(Base):
    """Logged workout session."""

    __tablename__ = "workout_logs"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("user_profiles.id", ondelete="CASCADE"), index=True
    )
    plan_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("workout_plans.id", ondelete="SET NULL"), nullable=True
    )

    # Workout info
    name: Mapped[str] = mapped_column(String(200))
    workout_type: Mapped[WorkoutType] = mapped_column(Enum(WorkoutType))
    source: Mapped[LogSource] = mapped_column(Enum(LogSource), default=LogSource.MANUAL)

    # Timing
    start_time: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)
    end_time: Mapped[Optional[datetime]] = mapped_column(DateTime(timezone=True), nullable=True)
    duration_min: Mapped[int] = mapped_column(Integer)

    # Metrics
    calories_burned: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    avg_heart_rate: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    max_heart_rate: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    distance_km: Mapped[Optional[float]] = mapped_column(Float, nullable=True)

    # Notes
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    rating: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)  # 1-5 rating

    # HealthKit sync
    health_kit_id: Mapped[Optional[str]] = mapped_column(String(100), nullable=True, unique=True)
    is_synced: Mapped[bool] = mapped_column(Boolean, default=True)
    local_id: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)

    # Relationships
    plan: Mapped[Optional["WorkoutPlan"]] = relationship("WorkoutPlan", back_populates="logs")
    sets: Mapped[List["WorkoutSetLog"]] = relationship(
        "WorkoutSetLog", back_populates="log", cascade="all, delete-orphan",
        order_by="WorkoutSetLog.order_index"
    )


class WorkoutSetLog(Base):
    """Individual set log within a workout."""

    __tablename__ = "workout_set_logs"

    log_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("workout_logs.id", ondelete="CASCADE"), index=True
    )

    # Exercise info
    exercise_name: Mapped[str] = mapped_column(String(200))
    set_number: Mapped[int] = mapped_column(Integer)

    # Performance
    reps: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    weight_kg: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    duration_sec: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    distance_m: Mapped[Optional[float]] = mapped_column(Float, nullable=True)

    # Status
    completed: Mapped[bool] = mapped_column(Boolean, default=True)
    is_warmup: Mapped[bool] = mapped_column(Boolean, default=False)
    is_dropset: Mapped[bool] = mapped_column(Boolean, default=False)

    # RPE (Rate of Perceived Exertion, 1-10)
    rpe: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)

    # Order
    order_index: Mapped[int] = mapped_column(Integer, default=0)

    # Notes
    notes: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)

    # Relationships
    log: Mapped["WorkoutLog"] = relationship("WorkoutLog", back_populates="sets")
