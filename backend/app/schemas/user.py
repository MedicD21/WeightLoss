"""User and profile schemas."""
from datetime import datetime, date
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, EmailStr, Field

from app.models.user import Sex, ActivityLevel, GoalType


class UserCreate(BaseModel):
    """Schema for creating a new user."""
    email: EmailStr


class UserUpdate(BaseModel):
    """Schema for updating user profile."""
    display_name: Optional[str] = Field(None, max_length=100)
    sex: Optional[Sex] = None
    birth_date: Optional[date] = None
    height_cm: Optional[float] = Field(None, ge=50, le=300)
    current_weight_kg: Optional[float] = Field(None, ge=20, le=500)
    activity_level: Optional[ActivityLevel] = None
    goal_type: Optional[GoalType] = None
    goal_rate_kg_per_week: Optional[float] = Field(None, ge=0, le=1.5)
    target_weight_kg: Optional[float] = Field(None, ge=20, le=500)
    use_metric: Optional[bool] = None
    daily_water_goal_ml: Optional[int] = Field(None, ge=500, le=10000)
    protein_per_kg: Optional[float] = Field(None, ge=0.5, le=3.0)


class UserResponse(BaseModel):
    """Schema for user response."""
    id: UUID
    email: str
    display_name: Optional[str] = None
    sex: Optional[Sex] = None
    birth_date: Optional[date] = None
    age: Optional[int] = None
    height_cm: Optional[float] = None
    current_weight_kg: Optional[float] = None
    activity_level: ActivityLevel
    goal_type: GoalType
    goal_rate_kg_per_week: float
    target_weight_kg: Optional[float] = None
    use_metric: bool
    daily_water_goal_ml: int
    protein_per_kg: float
    is_verified: bool
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class MacroTargetsResponse(BaseModel):
    """Schema for macro targets response."""
    id: UUID
    user_id: UUID
    calories: int
    protein_g: float
    carbs_g: float
    fat_g: float
    fiber_g: Optional[float] = None
    bmr: Optional[int] = None
    tdee: Optional[int] = None
    calculated_at: datetime

    class Config:
        from_attributes = True


class MacroTargetsCalculateRequest(BaseModel):
    """Request to calculate macro targets."""
    # Optional overrides (uses profile values if not provided)
    sex: Optional[Sex] = None
    age: Optional[int] = Field(None, ge=10, le=120)
    height_cm: Optional[float] = Field(None, ge=50, le=300)
    weight_kg: Optional[float] = Field(None, ge=20, le=500)
    activity_level: Optional[ActivityLevel] = None
    goal_type: Optional[GoalType] = None
    goal_rate_kg_per_week: Optional[float] = Field(None, ge=0, le=1.5)
    protein_per_kg: Optional[float] = Field(None, ge=0.5, le=3.0)


class MacroTargetsPreview(BaseModel):
    """Preview of calculated macro targets (not saved)."""
    calories: int
    protein_g: float
    carbs_g: float
    fat_g: float
    fiber_g: Optional[float] = None
    bmr: int
    tdee: int
    deficit_or_surplus: int  # Negative for deficit


class ProfileCompleteness(BaseModel):
    """Profile completeness status."""
    is_complete: bool
    missing_fields: list[str]
    completion_percent: int
