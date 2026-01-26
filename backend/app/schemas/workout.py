"""Workout schemas."""
from datetime import datetime
from typing import Optional, List
from uuid import UUID

from pydantic import BaseModel, Field

from app.models.workout import WorkoutType, LogSource, MuscleGroup


class WorkoutExerciseBase(BaseModel):
    """Base schema for workout exercise."""
    name: str = Field(..., max_length=200)
    muscle_group: Optional[MuscleGroup] = None
    equipment: Optional[str] = Field(None, max_length=100)
    notes: Optional[str] = None
    sets: int = Field(default=3, ge=1)
    reps_min: Optional[int] = Field(None, ge=1)
    reps_max: Optional[int] = Field(None, ge=1)
    duration_sec: Optional[int] = Field(None, ge=1)
    rest_sec: int = Field(default=60, ge=0)
    superset_group: Optional[int] = None


class WorkoutExerciseCreate(WorkoutExerciseBase):
    """Schema for creating a workout exercise."""
    order_index: int = Field(default=0, ge=0)


class WorkoutExerciseResponse(WorkoutExerciseBase):
    """Schema for workout exercise response."""
    id: UUID
    plan_id: UUID
    order_index: int
    created_at: datetime

    class Config:
        from_attributes = True


class WorkoutPlanBase(BaseModel):
    """Base schema for workout plan."""
    name: str = Field(..., max_length=200)
    description: Optional[str] = None
    workout_type: WorkoutType
    scheduled_days: Optional[List[int]] = Field(None, description="0=Monday, 6=Sunday")
    estimated_duration_min: Optional[int] = Field(None, ge=1)


class WorkoutPlanCreate(WorkoutPlanBase):
    """Schema for creating a workout plan."""
    exercises: List[WorkoutExerciseCreate] = Field(default_factory=list)
    is_active: bool = True


class WorkoutPlanUpdate(BaseModel):
    """Schema for updating a workout plan."""
    name: Optional[str] = Field(None, max_length=200)
    description: Optional[str] = None
    workout_type: Optional[WorkoutType] = None
    scheduled_days: Optional[List[int]] = None
    estimated_duration_min: Optional[int] = Field(None, ge=1)
    is_active: Optional[bool] = None
    order_index: Optional[int] = None


class WorkoutPlanResponse(WorkoutPlanBase):
    """Schema for workout plan response."""
    id: UUID
    user_id: UUID
    is_active: bool
    order_index: int
    exercises: List[WorkoutExerciseResponse]
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class WorkoutPlanSummary(BaseModel):
    """Brief workout plan summary for lists."""
    id: UUID
    name: str
    workout_type: WorkoutType
    exercise_count: int
    estimated_duration_min: Optional[int] = None
    scheduled_days: Optional[List[int]] = None
    is_active: bool


class WorkoutSetLogBase(BaseModel):
    """Base schema for workout set log."""
    exercise_name: str = Field(..., max_length=200)
    set_number: int = Field(..., ge=1)
    reps: Optional[int] = Field(None, ge=0)
    weight_kg: Optional[float] = Field(None, ge=0)
    duration_sec: Optional[int] = Field(None, ge=0)
    distance_m: Optional[float] = Field(None, ge=0)
    completed: bool = True
    is_warmup: bool = False
    is_dropset: bool = False
    rpe: Optional[int] = Field(None, ge=1, le=10)
    notes: Optional[str] = Field(None, max_length=500)


class WorkoutSetLogCreate(WorkoutSetLogBase):
    """Schema for creating a workout set log."""
    order_index: int = Field(default=0, ge=0)


class WorkoutSetLogResponse(WorkoutSetLogBase):
    """Schema for workout set log response."""
    id: UUID
    log_id: UUID
    order_index: int
    created_at: datetime

    class Config:
        from_attributes = True


class WorkoutLogBase(BaseModel):
    """Base schema for workout log."""
    name: str = Field(..., max_length=200)
    workout_type: WorkoutType
    start_time: datetime
    end_time: Optional[datetime] = None
    duration_min: int = Field(..., ge=1)
    calories_burned: Optional[int] = Field(None, ge=0)
    avg_heart_rate: Optional[int] = Field(None, ge=30, le=250)
    max_heart_rate: Optional[int] = Field(None, ge=30, le=250)
    distance_km: Optional[float] = Field(None, ge=0)
    notes: Optional[str] = None
    rating: Optional[int] = Field(None, ge=1, le=5)


class WorkoutLogCreate(WorkoutLogBase):
    """Schema for creating a workout log."""
    plan_id: Optional[UUID] = None
    source: LogSource = LogSource.MANUAL
    sets: List[WorkoutSetLogCreate] = Field(default_factory=list)
    health_kit_id: Optional[str] = Field(None, max_length=100)
    local_id: Optional[str] = Field(None, max_length=100)


class WorkoutLogUpdate(BaseModel):
    """Schema for updating a workout log."""
    name: Optional[str] = Field(None, max_length=200)
    workout_type: Optional[WorkoutType] = None
    end_time: Optional[datetime] = None
    duration_min: Optional[int] = Field(None, ge=1)
    calories_burned: Optional[int] = Field(None, ge=0)
    notes: Optional[str] = None
    rating: Optional[int] = Field(None, ge=1, le=5)


class WorkoutLogResponse(WorkoutLogBase):
    """Schema for workout log response."""
    id: UUID
    user_id: UUID
    plan_id: Optional[UUID] = None
    source: LogSource
    health_kit_id: Optional[str] = None
    sets: List[WorkoutSetLogResponse]
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class WorkoutLogSummary(BaseModel):
    """Brief workout log summary for lists."""
    id: UUID
    name: str
    workout_type: WorkoutType
    start_time: datetime
    duration_min: int
    calories_burned: Optional[int] = None
    sets_count: int
    source: LogSource


class WeeklyWorkoutStats(BaseModel):
    """Weekly workout statistics."""
    week_start: datetime
    total_workouts: int
    total_duration_min: int
    total_calories_burned: Optional[int] = None
    workout_types: dict[str, int]  # Type -> count
    avg_workout_duration: Optional[float] = None
