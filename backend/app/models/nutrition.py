"""Nutrition and meal models."""
import enum
import uuid
from datetime import datetime
from typing import Optional, List

from sqlalchemy import Enum, String, Float, Integer, ForeignKey, DateTime, Text, func
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class FoodSource(str, enum.Enum):
    """Source of food item data."""
    MANUAL = "manual"  # Manually entered
    OPEN_FOOD_FACTS = "open_food_facts"  # From OFF API
    BARCODE = "barcode"  # Scanned barcode -> OFF
    VISION = "vision"  # AI vision estimate
    CHAT = "chat"  # Added via chat assistant


class MealType(str, enum.Enum):
    """Type of meal."""
    BREAKFAST = "breakfast"
    LUNCH = "lunch"
    DINNER = "dinner"
    SNACK = "snack"
    OTHER = "other"


class Meal(Base):
    """A meal containing one or more food items."""

    __tablename__ = "meals"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("user_profiles.id", ondelete="CASCADE"), index=True
    )

    # Meal info
    name: Mapped[str] = mapped_column(String(200))
    meal_type: Mapped[MealType] = mapped_column(Enum(MealType), default=MealType.OTHER)
    timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)

    # Aggregated totals (denormalized for quick queries)
    total_calories: Mapped[int] = mapped_column(Integer, default=0)
    total_protein_g: Mapped[float] = mapped_column(Float, default=0.0)
    total_carbs_g: Mapped[float] = mapped_column(Float, default=0.0)
    total_fat_g: Mapped[float] = mapped_column(Float, default=0.0)
    total_fiber_g: Mapped[Optional[float]] = mapped_column(Float, nullable=True)

    # Optional
    notes: Mapped[Optional[str]] = mapped_column(Text, nullable=True)
    photo_url: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)

    # Sync
    is_synced: Mapped[bool] = mapped_column(default=True)
    local_id: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)

    # Relationships
    items: Mapped[List["FoodItem"]] = relationship(
        "FoodItem", back_populates="meal", cascade="all, delete-orphan"
    )

    def recalculate_totals(self):
        """Recalculate total macros from items."""
        self.total_calories = sum(item.calories for item in self.items)
        self.total_protein_g = sum(item.protein_g for item in self.items)
        self.total_carbs_g = sum(item.carbs_g for item in self.items)
        self.total_fat_g = sum(item.fat_g for item in self.items)
        self.total_fiber_g = sum(
            item.fiber_g for item in self.items if item.fiber_g
        ) or None


class FoodItem(Base):
    """Individual food item within a meal."""

    __tablename__ = "food_items"

    meal_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("meals.id", ondelete="CASCADE"), index=True
    )

    # Food info
    name: Mapped[str] = mapped_column(String(200))
    source: Mapped[FoodSource] = mapped_column(Enum(FoodSource))

    # Quantity
    grams: Mapped[float] = mapped_column(Float)
    serving_size: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    serving_unit: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    servings: Mapped[float] = mapped_column(Float, default=1.0)

    # Macros (for the amount consumed)
    calories: Mapped[int] = mapped_column(Integer)
    protein_g: Mapped[float] = mapped_column(Float)
    carbs_g: Mapped[float] = mapped_column(Float)
    fat_g: Mapped[float] = mapped_column(Float)
    fiber_g: Mapped[Optional[float]] = mapped_column(Float, nullable=True)

    # Additional nutrition (optional)
    sodium_mg: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    sugar_g: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    saturated_fat_g: Mapped[Optional[float]] = mapped_column(Float, nullable=True)

    # Barcode/OFF data
    barcode: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)
    off_product_id: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    nutri_score_grade: Mapped[Optional[str]] = mapped_column(String(5), nullable=True)

    # Vision AI metadata
    confidence: Mapped[Optional[float]] = mapped_column(Float, nullable=True)
    portion_description: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)

    # Relationships
    meal: Mapped["Meal"] = relationship("Meal", back_populates="items")


class SavedFood(Base):
    """Saved/favorited foods for quick access."""

    __tablename__ = "saved_foods"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("user_profiles.id", ondelete="CASCADE"), index=True
    )

    # Food info
    name: Mapped[str] = mapped_column(String(200))
    brand: Mapped[Optional[str]] = mapped_column(String(200), nullable=True)
    source: Mapped[FoodSource] = mapped_column(Enum(FoodSource))

    # Per 100g values
    calories_per_100g: Mapped[int] = mapped_column(Integer)
    protein_per_100g: Mapped[float] = mapped_column(Float)
    carbs_per_100g: Mapped[float] = mapped_column(Float)
    fat_per_100g: Mapped[float] = mapped_column(Float)
    fiber_per_100g: Mapped[Optional[float]] = mapped_column(Float, nullable=True)

    # Default serving
    default_serving_g: Mapped[float] = mapped_column(Float, default=100.0)
    serving_unit: Mapped[Optional[str]] = mapped_column(String(50), nullable=True)

    # Barcode
    barcode: Mapped[Optional[str]] = mapped_column(String(50), index=True, nullable=True)

    # Metadata
    times_used: Mapped[int] = mapped_column(Integer, default=0)
    last_used_at: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)

    # Raw OFF data for reference
    off_data: Mapped[Optional[dict]] = mapped_column(JSONB, nullable=True)
