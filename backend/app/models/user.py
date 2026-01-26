"""User and profile models."""
import enum
import uuid
from datetime import datetime
from typing import Optional

from sqlalchemy import Enum, String, Float, Integer, Boolean, ForeignKey, DateTime, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class Sex(str, enum.Enum):
    """Biological sex for BMR calculations."""
    MALE = "male"
    FEMALE = "female"


class ActivityLevel(str, enum.Enum):
    """Activity level multipliers for TDEE."""
    SEDENTARY = "sedentary"  # Little or no exercise
    LIGHT = "light"  # Light exercise 1-3 days/week
    MODERATE = "moderate"  # Moderate exercise 3-5 days/week
    ACTIVE = "active"  # Hard exercise 6-7 days/week
    VERY_ACTIVE = "very_active"  # Very hard exercise, physical job


class GoalType(str, enum.Enum):
    """Fitness goal type."""
    CUT = "cut"  # Lose fat
    MAINTAIN = "maintain"  # Maintain weight
    BULK = "bulk"  # Build muscle/gain weight


class UserProfile(Base):
    """User profile with body metrics and goals."""

    __tablename__ = "user_profiles"

    # Authentication
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    apple_user_id: Mapped[Optional[str]] = mapped_column(String(255), unique=True, nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    is_verified: Mapped[bool] = mapped_column(Boolean, default=False)

    # Profile
    display_name: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)

    # Body Metrics
    sex: Mapped[Optional[Sex]] = mapped_column(Enum(Sex), nullable=True)
    birth_date: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    height_cm: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    current_weight_kg: Mapped[Optional[float]] = mapped_column(Float, nullable=True)

    # Goals
    activity_level: Mapped[ActivityLevel] = mapped_column(
        Enum(ActivityLevel), default=ActivityLevel.MODERATE
    )
    goal_type: Mapped[GoalType] = mapped_column(
        Enum(GoalType), default=GoalType.MAINTAIN
    )
    goal_rate_kg_per_week: Mapped[float] = mapped_column(Float, default=0.0)
    target_weight_kg: Mapped[Optional[float]] = mapped_column(Float, nullable=True)

    # Preferences
    use_metric: Mapped[bool] = mapped_column(Boolean, default=True)
    daily_water_goal_ml: Mapped[int] = mapped_column(Integer, default=2500)
    protein_per_kg: Mapped[float] = mapped_column(Float, default=1.8)  # g protein per kg body weight

    # Relationships
    macro_targets: Mapped[Optional["MacroTargets"]] = relationship(
        "MacroTargets", back_populates="user", uselist=False
    )

    @property
    def age(self) -> Optional[int]:
        """Calculate age from birth date."""
        if not self.birth_date:
            return None
        today = datetime.now()
        return today.year - self.birth_date.year - (
            (today.month, today.day) < (self.birth_date.month, self.birth_date.day)
        )


class MacroTargets(Base):
    """Calculated macro nutrient targets."""

    __tablename__ = "macro_targets"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("user_profiles.id", ondelete="CASCADE"), unique=True
    )

    # Calorie target
    calories: Mapped[int] = mapped_column(Integer)

    # Macro targets in grams
    protein_g: Mapped[float] = mapped_column(Float)
    carbs_g: Mapped[float] = mapped_column(Float)
    fat_g: Mapped[float] = mapped_column(Float)
    fiber_g: Mapped[Optional[float]] = mapped_column(Float, nullable=True)

    # Calculation metadata
    bmr: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    tdee: Mapped[Optional[int]] = mapped_column(Integer, nullable=True)
    calculated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    # Relationships
    user: Mapped["UserProfile"] = relationship("UserProfile", back_populates="macro_targets")
