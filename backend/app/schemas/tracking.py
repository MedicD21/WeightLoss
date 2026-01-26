"""Tracking schemas for weight, water, steps, and progress."""
from datetime import datetime, date
from typing import Optional, List
from uuid import UUID

from pydantic import BaseModel, Field, ConfigDict


class BodyWeightBase(BaseModel):
    """Base schema for body weight entry."""
    weight_kg: float = Field(..., ge=20, le=500)
    timestamp: datetime
    notes: Optional[str] = Field(None, max_length=500)
    body_fat_percent: Optional[float] = Field(None, ge=0, le=100)
    muscle_mass_kg: Optional[float] = Field(None, ge=0, le=200)
    water_percent: Optional[float] = Field(None, ge=0, le=100)


class BodyWeightCreate(BodyWeightBase):
    """Schema for creating a body weight entry."""
    source: str = Field(default="manual", max_length=50)
    local_id: Optional[str] = Field(None, max_length=100)


class BodyWeightResponse(BodyWeightBase):
    """Schema for body weight response."""
    id: UUID
    user_id: UUID
    source: str
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class WaterBase(BaseModel):
    """Base schema for water entry."""
    amount_ml: int = Field(..., ge=1, le=5000)
    timestamp: datetime


class WaterCreate(WaterBase):
    """Schema for creating a water entry."""
    source: str = Field(default="manual", max_length=50)
    local_id: Optional[str] = Field(None, max_length=100)


class WaterResponse(WaterBase):
    """Schema for water response."""
    id: UUID
    user_id: UUID
    source: str
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class StepsDailyResponse(BaseModel):
    """Schema for daily steps response."""
    id: UUID
    user_id: UUID
    date: date
    steps: int
    distance_km: Optional[float] = None
    flights_climbed: Optional[int] = None
    active_energy_kcal: Optional[int] = None
    source: str
    synced_at: datetime

    model_config = ConfigDict(from_attributes=True)


class DailyWaterSummary(BaseModel):
    """Daily water intake summary."""
    date: date
    total_ml: int
    goal_ml: int
    entries_count: int
    goal_achieved: bool
    percent_of_goal: float


class WeightTrend(BaseModel):
    """Weight trend analysis."""
    current_weight: float
    start_weight: float
    change: float
    change_percent: float
    period_days: int
    trend: str  # "losing", "gaining", "maintaining"
    avg_weekly_change: float
    data_points: List[dict]  # [{date, weight}]


class ProgressSummary(BaseModel):
    """Overall progress summary."""
    # Period
    period_start: date
    period_end: date
    period_days: int

    # Weight
    weight_current: Optional[float] = None
    weight_start: Optional[float] = None
    weight_change: Optional[float] = None
    weight_goal: Optional[float] = None
    weight_to_goal: Optional[float] = None

    # Nutrition adherence (averages)
    avg_daily_calories: Optional[int] = None
    avg_daily_protein_g: Optional[float] = None
    calories_target: Optional[int] = None
    protein_target: Optional[float] = None
    calorie_adherence_percent: Optional[float] = None
    protein_adherence_percent: Optional[float] = None
    days_on_target: int = 0

    # Activity
    total_workouts: int = 0
    total_workout_minutes: int = 0
    avg_daily_steps: Optional[int] = None
    total_calories_burned: Optional[int] = None

    # Water
    avg_daily_water_ml: Optional[int] = None
    water_goal_ml: Optional[int] = None
    water_goal_days_hit: int = 0


class DailySummary(BaseModel):
    """Complete daily summary."""
    date: date

    # Nutrition
    calories_consumed: int = 0
    calories_target: Optional[int] = None
    calories_remaining: Optional[int] = None
    protein_g: float = 0
    protein_target: Optional[float] = None
    carbs_g: float = 0
    carbs_target: Optional[float] = None
    fat_g: float = 0
    fat_target: Optional[float] = None
    meals_count: int = 0

    # Activity
    steps: Optional[int] = None
    steps_goal: int = 10000
    active_calories: Optional[int] = None
    workouts_count: int = 0
    workout_minutes: int = 0

    # Water
    water_ml: int = 0
    water_goal_ml: int = 2500

    # Weight (if logged today)
    weight_kg: Optional[float] = None


class ChartDataPoint(BaseModel):
    """Single data point for charts."""
    date: date
    value: float
    label: Optional[str] = None


class ChartData(BaseModel):
    """Data for rendering a chart."""
    metric: str
    unit: str
    data_points: List[ChartDataPoint]
    period_start: date
    period_end: date
    average: Optional[float] = None
    minimum: Optional[float] = None
    maximum: Optional[float] = None
    target: Optional[float] = None
