"""Nutrition and meal routes."""
from datetime import datetime, date, timedelta
from typing import Optional, List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select, func, and_
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.base import get_db
from app.models.user import UserProfile, MacroTargets
from app.models.nutrition import Meal, FoodItem, SavedFood, FoodSource
from app.schemas.nutrition import (
    MealCreate,
    MealUpdate,
    MealResponse,
    MealSummary,
    FoodItemCreate,
    SavedFoodCreate,
    SavedFoodResponse,
    OpenFoodFactsProduct,
    DailyNutritionSummary,
    FoodSearchResult,
)
from app.services.open_food_facts import off_client, OpenFoodFactsClient
from app.utils.auth import get_current_user

router = APIRouter(prefix="/nutrition", tags=["Nutrition"])


@router.get("/meals", response_model=List[MealSummary])
async def list_meals(
    start_date: Optional[date] = Query(None),
    end_date: Optional[date] = Query(None),
    meal_type: Optional[str] = Query(None),
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """List meals with optional date filtering."""
    query = select(Meal).where(Meal.user_id == current_user.id)

    if start_date:
        query = query.where(Meal.timestamp >= datetime.combine(start_date, datetime.min.time()))
    if end_date:
        query = query.where(Meal.timestamp <= datetime.combine(end_date, datetime.max.time()))
    if meal_type:
        query = query.where(Meal.meal_type == meal_type)

    query = query.order_by(Meal.timestamp.desc()).offset(offset).limit(limit)
    query = query.options(selectinload(Meal.items))

    result = await db.execute(query)
    meals = result.scalars().all()

    return [
        MealSummary(
            id=m.id,
            name=m.name,
            meal_type=m.meal_type,
            timestamp=m.timestamp,
            total_calories=m.total_calories,
            total_protein_g=m.total_protein_g,
            items_count=len(m.items),
        )
        for m in meals
    ]


@router.get("/meals/{meal_id}", response_model=MealResponse)
async def get_meal(
    meal_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Get a specific meal by ID."""
    result = await db.execute(
        select(Meal)
        .where(and_(Meal.id == meal_id, Meal.user_id == current_user.id))
        .options(selectinload(Meal.items))
    )
    meal = result.scalar_one_or_none()

    if not meal:
        raise HTTPException(status_code=404, detail="Meal not found")

    return meal


@router.post("/meals", response_model=MealResponse, status_code=status.HTTP_201_CREATED)
async def create_meal(
    meal_data: MealCreate,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Create a new meal with food items."""
    meal = Meal(
        user_id=current_user.id,
        name=meal_data.name,
        meal_type=meal_data.meal_type,
        timestamp=meal_data.timestamp,
        notes=meal_data.notes,
        photo_url=meal_data.photo_url,
        local_id=meal_data.local_id,
    )

    # Add food items
    for item_data in meal_data.items:
        item = FoodItem(
            name=item_data.name,
            source=item_data.source,
            grams=item_data.grams,
            serving_size=item_data.serving_size,
            serving_unit=item_data.serving_unit,
            servings=item_data.servings,
            calories=item_data.calories,
            protein_g=item_data.protein_g,
            carbs_g=item_data.carbs_g,
            fat_g=item_data.fat_g,
            fiber_g=item_data.fiber_g,
            sodium_mg=item_data.sodium_mg,
            sugar_g=item_data.sugar_g,
            saturated_fat_g=item_data.saturated_fat_g,
            barcode=item_data.barcode,
            off_product_id=item_data.off_product_id,
            confidence=item_data.confidence,
            portion_description=item_data.portion_description,
        )
        meal.items.append(item)

    # Calculate totals
    meal.recalculate_totals()

    db.add(meal)
    await db.flush()
    await db.refresh(meal)

    return meal


@router.put("/meals/{meal_id}", response_model=MealResponse)
async def update_meal(
    meal_id: UUID,
    updates: MealUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Update a meal."""
    result = await db.execute(
        select(Meal)
        .where(and_(Meal.id == meal_id, Meal.user_id == current_user.id))
        .options(selectinload(Meal.items))
    )
    meal = result.scalar_one_or_none()

    if not meal:
        raise HTTPException(status_code=404, detail="Meal not found")

    update_data = updates.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(meal, field, value)

    await db.flush()
    await db.refresh(meal)

    return meal


@router.delete("/meals/{meal_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_meal(
    meal_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Delete a meal."""
    result = await db.execute(
        select(Meal).where(and_(Meal.id == meal_id, Meal.user_id == current_user.id))
    )
    meal = result.scalar_one_or_none()

    if not meal:
        raise HTTPException(status_code=404, detail="Meal not found")

    await db.delete(meal)


@router.post("/meals/{meal_id}/items", response_model=MealResponse)
async def add_food_item(
    meal_id: UUID,
    item_data: FoodItemCreate,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Add a food item to an existing meal."""
    result = await db.execute(
        select(Meal)
        .where(and_(Meal.id == meal_id, Meal.user_id == current_user.id))
        .options(selectinload(Meal.items))
    )
    meal = result.scalar_one_or_none()

    if not meal:
        raise HTTPException(status_code=404, detail="Meal not found")

    item = FoodItem(
        meal_id=meal.id,
        name=item_data.name,
        source=item_data.source,
        grams=item_data.grams,
        calories=item_data.calories,
        protein_g=item_data.protein_g,
        carbs_g=item_data.carbs_g,
        fat_g=item_data.fat_g,
        fiber_g=item_data.fiber_g,
        barcode=item_data.barcode,
    )
    db.add(item)

    # Recalculate totals
    meal.items.append(item)
    meal.recalculate_totals()

    await db.flush()
    await db.refresh(meal)

    return meal


# Food search and lookup

@router.get("/foods/search", response_model=List[FoodSearchResult])
async def search_foods(
    query: str = Query(..., min_length=2),
    limit: int = Query(20, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Search for foods in saved foods, recent foods, and Open Food Facts."""
    results: List[FoodSearchResult] = []

    # Search saved foods
    saved_query = select(SavedFood).where(
        and_(
            SavedFood.user_id == current_user.id,
            SavedFood.name.ilike(f"%{query}%")
        )
    ).limit(10)
    saved_result = await db.execute(saved_query)
    saved_foods = saved_result.scalars().all()

    for food in saved_foods:
        results.append(FoodSearchResult(
            id=food.id,
            name=food.name,
            brand=food.brand,
            source="saved",
            calories_per_100g=food.calories_per_100g,
            protein_per_100g=food.protein_per_100g,
            barcode=food.barcode,
        ))

    # Search Open Food Facts
    if len(results) < limit:
        off_products = await off_client.search_products(query, page_size=limit - len(results))
        for product in off_products:
            results.append(FoodSearchResult(
                name=product.name,
                brand=product.brand,
                source="off",
                calories_per_100g=product.calories_per_100g,
                protein_per_100g=product.protein_per_100g,
                barcode=product.barcode,
                image_url=product.image_url,
            ))

    return results[:limit]


@router.get("/foods/barcode/{barcode}", response_model=OpenFoodFactsProduct)
async def lookup_barcode(
    barcode: str,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Look up a product by barcode."""
    # Check saved foods first
    result = await db.execute(
        select(SavedFood).where(
            and_(SavedFood.user_id == current_user.id, SavedFood.barcode == barcode)
        )
    )
    saved = result.scalar_one_or_none()

    if saved and saved.off_data:
        return OpenFoodFactsProduct(
            barcode=barcode,
            name=saved.name,
            brand=saved.brand,
            calories_per_100g=saved.calories_per_100g,
            protein_per_100g=saved.protein_per_100g,
            carbs_per_100g=saved.carbs_per_100g,
            fat_per_100g=saved.fat_per_100g,
            fiber_per_100g=saved.fiber_per_100g,
            serving_size_g=saved.default_serving_g,
            raw_data=saved.off_data,
        )

    # Fetch from Open Food Facts
    product = await off_client.get_product_by_barcode(barcode)

    if not product:
        raise HTTPException(status_code=404, detail="Product not found")

    return product


# Saved foods

@router.get("/foods/saved", response_model=List[SavedFoodResponse])
async def list_saved_foods(
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """List user's saved foods."""
    result = await db.execute(
        select(SavedFood)
        .where(SavedFood.user_id == current_user.id)
        .order_by(SavedFood.times_used.desc())
        .offset(offset)
        .limit(limit)
    )
    return result.scalars().all()


@router.post("/foods/saved", response_model=SavedFoodResponse, status_code=status.HTTP_201_CREATED)
async def save_food(
    food_data: SavedFoodCreate,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Save a food for quick access."""
    food = SavedFood(
        user_id=current_user.id,
        name=food_data.name,
        brand=food_data.brand,
        source=food_data.source,
        calories_per_100g=food_data.calories_per_100g,
        protein_per_100g=food_data.protein_per_100g,
        carbs_per_100g=food_data.carbs_per_100g,
        fat_per_100g=food_data.fat_per_100g,
        fiber_per_100g=food_data.fiber_per_100g,
        default_serving_g=food_data.default_serving_g,
        serving_unit=food_data.serving_unit,
        barcode=food_data.barcode,
        off_data=food_data.off_data,
    )

    db.add(food)
    await db.flush()
    await db.refresh(food)

    return food


# Daily summary

@router.get("/daily/{date_str}", response_model=DailyNutritionSummary)
async def get_daily_nutrition(
    date_str: str,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Get nutrition summary for a specific date."""
    try:
        target_date = datetime.strptime(date_str, "%Y-%m-%d").date()
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD")

    start = datetime.combine(target_date, datetime.min.time())
    end = datetime.combine(target_date, datetime.max.time())

    result = await db.execute(
        select(Meal)
        .where(and_(
            Meal.user_id == current_user.id,
            Meal.timestamp >= start,
            Meal.timestamp <= end,
        ))
    )
    meals = result.scalars().all()

    total_calories = sum(m.total_calories for m in meals)
    total_protein = sum(m.total_protein_g for m in meals)
    total_carbs = sum(m.total_carbs_g for m in meals)
    total_fat = sum(m.total_fat_g for m in meals)
    total_fiber = sum(m.total_fiber_g or 0 for m in meals)

    # Get targets
    targets_result = await db.execute(
        select(MacroTargets).where(MacroTargets.user_id == current_user.id)
    )
    targets = targets_result.scalar_one_or_none()

    return DailyNutritionSummary(
        date=start,
        total_calories=total_calories,
        total_protein_g=total_protein,
        total_carbs_g=total_carbs,
        total_fat_g=total_fat,
        total_fiber_g=total_fiber if total_fiber else None,
        meals_count=len(meals),
        calories_target=targets.calories if targets else None,
        calories_remaining=(targets.calories - total_calories) if targets else None,
        protein_target=targets.protein_g if targets else None,
        protein_remaining=(targets.protein_g - total_protein) if targets else None,
    )
