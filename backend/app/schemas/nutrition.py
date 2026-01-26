"""Nutrition and meal schemas."""
from datetime import datetime
from typing import Optional, List
from uuid import UUID

from pydantic import BaseModel, Field

from app.models.nutrition import FoodSource, MealType


class FoodItemBase(BaseModel):
    """Base schema for food item."""
    name: str = Field(..., max_length=200)
    grams: float = Field(..., ge=0)
    calories: int = Field(..., ge=0)
    protein_g: float = Field(..., ge=0)
    carbs_g: float = Field(..., ge=0)
    fat_g: float = Field(..., ge=0)
    fiber_g: Optional[float] = Field(None, ge=0)
    sodium_mg: Optional[float] = Field(None, ge=0)
    sugar_g: Optional[float] = Field(None, ge=0)
    saturated_fat_g: Optional[float] = Field(None, ge=0)


class FoodItemCreate(FoodItemBase):
    """Schema for creating a food item."""
    source: FoodSource = FoodSource.MANUAL
    serving_size: Optional[float] = None
    serving_unit: Optional[str] = Field(None, max_length=50)
    servings: float = Field(default=1.0, ge=0)
    barcode: Optional[str] = Field(None, max_length=50)
    off_product_id: Optional[str] = Field(None, max_length=100)
    confidence: Optional[float] = Field(None, ge=0, le=1)
    portion_description: Optional[str] = Field(None, max_length=200)


class FoodItemResponse(FoodItemBase):
    """Schema for food item response."""
    id: UUID
    meal_id: UUID
    source: FoodSource
    serving_size: Optional[float] = None
    serving_unit: Optional[str] = None
    servings: float
    barcode: Optional[str] = None
    confidence: Optional[float] = None
    portion_description: Optional[str] = None
    created_at: datetime

    class Config:
        from_attributes = True


class MealBase(BaseModel):
    """Base schema for meal."""
    name: str = Field(..., max_length=200)
    meal_type: MealType = MealType.OTHER
    timestamp: datetime
    notes: Optional[str] = None
    photo_url: Optional[str] = Field(None, max_length=500)


class MealCreate(MealBase):
    """Schema for creating a meal."""
    items: List[FoodItemCreate] = Field(default_factory=list)
    local_id: Optional[str] = Field(None, max_length=100)


class MealUpdate(BaseModel):
    """Schema for updating a meal."""
    name: Optional[str] = Field(None, max_length=200)
    meal_type: Optional[MealType] = None
    timestamp: Optional[datetime] = None
    notes: Optional[str] = None
    photo_url: Optional[str] = Field(None, max_length=500)


class MealResponse(MealBase):
    """Schema for meal response."""
    id: UUID
    user_id: UUID
    total_calories: int
    total_protein_g: float
    total_carbs_g: float
    total_fat_g: float
    total_fiber_g: Optional[float] = None
    items: List[FoodItemResponse]
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class MealSummary(BaseModel):
    """Brief meal summary for lists."""
    id: UUID
    name: str
    meal_type: MealType
    timestamp: datetime
    total_calories: int
    total_protein_g: float
    items_count: int


class SavedFoodCreate(BaseModel):
    """Schema for saving a food for quick access."""
    name: str = Field(..., max_length=200)
    brand: Optional[str] = Field(None, max_length=200)
    source: FoodSource = FoodSource.MANUAL
    calories_per_100g: int = Field(..., ge=0)
    protein_per_100g: float = Field(..., ge=0)
    carbs_per_100g: float = Field(..., ge=0)
    fat_per_100g: float = Field(..., ge=0)
    fiber_per_100g: Optional[float] = Field(None, ge=0)
    default_serving_g: float = Field(default=100.0, ge=0)
    serving_unit: Optional[str] = Field(None, max_length=50)
    barcode: Optional[str] = Field(None, max_length=50)
    off_data: Optional[dict] = None


class SavedFoodResponse(BaseModel):
    """Schema for saved food response."""
    id: UUID
    user_id: UUID
    name: str
    brand: Optional[str] = None
    source: FoodSource
    calories_per_100g: int
    protein_per_100g: float
    carbs_per_100g: float
    fat_per_100g: float
    fiber_per_100g: Optional[float] = None
    default_serving_g: float
    serving_unit: Optional[str] = None
    barcode: Optional[str] = None
    times_used: int
    last_used_at: Optional[datetime] = None
    created_at: datetime

    class Config:
        from_attributes = True


class OpenFoodFactsProduct(BaseModel):
    """Product data from Open Food Facts API."""
    barcode: str
    name: str
    brand: Optional[str] = None
    image_url: Optional[str] = None

    # Per 100g values
    calories_per_100g: Optional[float] = None
    protein_per_100g: Optional[float] = None
    carbs_per_100g: Optional[float] = None
    fat_per_100g: Optional[float] = None
    fiber_per_100g: Optional[float] = None
    sodium_per_100g: Optional[float] = None
    sugar_per_100g: Optional[float] = None
    saturated_fat_per_100g: Optional[float] = None

    # Serving info
    serving_size_g: Optional[float] = None
    serving_description: Optional[str] = None

    # Quality
    nutriscore_grade: Optional[str] = None
    nova_group: Optional[int] = None

    # Raw data
    raw_data: Optional[dict] = None


class DailyNutritionSummary(BaseModel):
    """Daily nutrition summary."""
    date: datetime
    total_calories: int
    total_protein_g: float
    total_carbs_g: float
    total_fat_g: float
    total_fiber_g: Optional[float] = None
    meals_count: int

    # Against targets
    calories_target: Optional[int] = None
    calories_remaining: Optional[int] = None
    protein_target: Optional[float] = None
    protein_remaining: Optional[float] = None


class FoodSearchResult(BaseModel):
    """Search result for foods."""
    id: Optional[UUID] = None  # None for OFF results
    name: str
    brand: Optional[str] = None
    source: str  # "saved", "recent", "off"
    calories_per_100g: Optional[float] = None
    protein_per_100g: Optional[float] = None
    barcode: Optional[str] = None
    image_url: Optional[str] = None
