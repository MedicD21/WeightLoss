"""User and profile routes."""
from datetime import datetime
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.base import get_db
from app.models.user import UserProfile, MacroTargets
from app.schemas.user import (
    UserUpdate,
    UserResponse,
    MacroTargetsResponse,
    MacroTargetsCalculateRequest,
    MacroTargetsPreview,
    ProfileCompleteness,
)
from app.services.macro_calculator import MacroCalculator
from app.services.auth_service import auth_service
from app.utils.auth import get_current_user

router = APIRouter(prefix="/user", tags=["User"])


@router.get("/profile", response_model=UserResponse)
async def get_profile(
    current_user: UserProfile = Depends(get_current_user),
):
    """Get the current user's profile."""
    return current_user


@router.put("/profile", response_model=UserResponse)
async def update_profile(
    updates: UserUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Update the current user's profile."""
    update_data = updates.model_dump(exclude_unset=True)

    for field, value in update_data.items():
        setattr(current_user, field, value)

    await db.flush()
    await db.refresh(current_user)
    await auth_service.sync_user_profile(current_user)

    return current_user


@router.get("/profile/completeness", response_model=ProfileCompleteness)
async def get_profile_completeness(
    current_user: UserProfile = Depends(get_current_user),
):
    """Check if the user's profile is complete enough to calculate macros."""
    required_fields = ["sex", "birth_date", "height_cm", "current_weight_kg"]
    missing = []

    for field in required_fields:
        if getattr(current_user, field) is None:
            missing.append(field)

    is_complete = len(missing) == 0
    completion_percent = int(((len(required_fields) - len(missing)) / len(required_fields)) * 100)

    return ProfileCompleteness(
        is_complete=is_complete,
        missing_fields=missing,
        completion_percent=completion_percent,
    )


@router.get("/targets", response_model=Optional[MacroTargetsResponse])
async def get_macro_targets(
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Get the user's current macro targets."""
    result = await db.execute(
        select(MacroTargets).where(MacroTargets.user_id == current_user.id)
    )
    targets = result.scalar_one_or_none()

    if not targets:
        return None

    return targets


@router.post("/targets/calculate", response_model=MacroTargetsResponse)
async def calculate_macro_targets(
    request: MacroTargetsCalculateRequest,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """
    Calculate and save macro targets based on user profile and goals.

    Uses Mifflin-St Jeor equation for BMR calculation.
    """
    # Get values from request or fall back to profile
    sex = request.sex or current_user.sex
    age = request.age or current_user.age
    height_cm = request.height_cm or current_user.height_cm
    weight_kg = request.weight_kg or current_user.current_weight_kg
    activity_level = request.activity_level or current_user.activity_level
    goal_type = request.goal_type or current_user.goal_type
    goal_rate = request.goal_rate_kg_per_week or current_user.goal_rate_kg_per_week
    protein_per_kg = request.protein_per_kg or current_user.protein_per_kg

    # Validate required fields
    if not all([sex, age, height_cm, weight_kg]):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Missing required fields: sex, age, height_cm, or weight_kg",
        )

    # Calculate macros
    calculator = MacroCalculator(protein_per_kg=protein_per_kg)
    result = calculator.calculate_macros(
        sex=sex,
        weight_kg=weight_kg,
        height_cm=height_cm,
        age=age,
        activity_level=activity_level,
        goal_type=goal_type,
        goal_rate_kg_per_week=goal_rate,
    )

    # Update or create macro targets
    existing = await db.execute(
        select(MacroTargets).where(MacroTargets.user_id == current_user.id)
    )
    targets = existing.scalar_one_or_none()

    if targets:
        targets.calories = result.calories
        targets.protein_g = result.protein_g
        targets.carbs_g = result.carbs_g
        targets.fat_g = result.fat_g
        targets.fiber_g = result.fiber_g
        targets.bmr = result.bmr
        targets.tdee = result.tdee
        targets.calculated_at = datetime.utcnow()
    else:
        targets = MacroTargets(
            user_id=current_user.id,
            calories=result.calories,
            protein_g=result.protein_g,
            carbs_g=result.carbs_g,
            fat_g=result.fat_g,
            fiber_g=result.fiber_g,
            bmr=result.bmr,
            tdee=result.tdee,
        )
        db.add(targets)

    await db.flush()
    await db.refresh(targets)

    return targets


@router.post("/targets/preview", response_model=MacroTargetsPreview)
async def preview_macro_targets(
    request: MacroTargetsCalculateRequest,
    current_user: UserProfile = Depends(get_current_user),
):
    """
    Preview macro targets without saving.

    Useful for showing users what their targets would be with different settings.
    """
    # Get values from request or fall back to profile
    sex = request.sex or current_user.sex
    age = request.age or current_user.age
    height_cm = request.height_cm or current_user.height_cm
    weight_kg = request.weight_kg or current_user.current_weight_kg
    activity_level = request.activity_level or current_user.activity_level
    goal_type = request.goal_type or current_user.goal_type
    goal_rate = request.goal_rate_kg_per_week or current_user.goal_rate_kg_per_week
    protein_per_kg = request.protein_per_kg or current_user.protein_per_kg

    # Validate required fields
    if not all([sex, age, height_cm, weight_kg]):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Missing required fields: sex, age, height_cm, or weight_kg",
        )

    # Calculate macros
    calculator = MacroCalculator(protein_per_kg=protein_per_kg)
    result = calculator.calculate_macros(
        sex=sex,
        weight_kg=weight_kg,
        height_cm=height_cm,
        age=age,
        activity_level=activity_level,
        goal_type=goal_type,
        goal_rate_kg_per_week=goal_rate,
    )

    return MacroTargetsPreview(
        calories=result.calories,
        protein_g=result.protein_g,
        carbs_g=result.carbs_g,
        fat_g=result.fat_g,
        fiber_g=result.fiber_g,
        bmr=result.bmr,
        tdee=result.tdee,
        deficit_or_surplus=result.deficit_or_surplus,
    )
