"""Tracking routes for weight, water, steps, and progress."""
from datetime import datetime, date, timedelta
from typing import Optional, List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select, and_, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.base import get_db
from app.models.user import UserProfile, MacroTargets
from app.models.tracking import BodyWeightEntry, WaterEntry, StepsDaily
from app.models.nutrition import Meal
from app.models.workout import WorkoutLog
from app.schemas.tracking import (
    BodyWeightCreate,
    BodyWeightResponse,
    WaterCreate,
    WaterResponse,
    StepsDailyResponse,
    DailyWaterSummary,
    WeightTrend,
    ProgressSummary,
    DailySummary,
    ChartData,
    ChartDataPoint,
)
from app.services.auth_service import auth_service
from app.utils.auth import get_current_user

router = APIRouter(prefix="/tracking", tags=["Tracking"])


# Body Weight

@router.get("/weight", response_model=List[BodyWeightResponse])
async def list_weight_entries(
    start_date: Optional[date] = Query(None),
    end_date: Optional[date] = Query(None),
    limit: int = Query(100, ge=1, le=365),
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """List body weight entries."""
    query = select(BodyWeightEntry).where(BodyWeightEntry.user_id == current_user.id)

    if start_date:
        query = query.where(BodyWeightEntry.timestamp >= datetime.combine(start_date, datetime.min.time()))
    if end_date:
        query = query.where(BodyWeightEntry.timestamp <= datetime.combine(end_date, datetime.max.time()))

    query = query.order_by(BodyWeightEntry.timestamp.desc()).limit(limit)

    result = await db.execute(query)
    return result.scalars().all()


@router.post("/weight", response_model=BodyWeightResponse, status_code=status.HTTP_201_CREATED)
async def log_weight(
    data: BodyWeightCreate,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Log a body weight measurement."""
    entry = BodyWeightEntry(
        user_id=current_user.id,
        weight_kg=data.weight_kg,
        timestamp=data.timestamp,
        notes=data.notes,
        body_fat_percent=data.body_fat_percent,
        muscle_mass_kg=data.muscle_mass_kg,
        water_percent=data.water_percent,
        source=data.source,
        local_id=data.local_id,
    )

    db.add(entry)

    # Update user's current weight
    current_user.current_weight_kg = data.weight_kg

    await db.flush()
    await db.refresh(entry)
    await auth_service.sync_user_profile(current_user)

    return entry


@router.delete("/weight/{entry_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_weight_entry(
    entry_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Delete a weight entry."""
    result = await db.execute(
        select(BodyWeightEntry).where(
            and_(BodyWeightEntry.id == entry_id, BodyWeightEntry.user_id == current_user.id)
        )
    )
    entry = result.scalar_one_or_none()

    if not entry:
        raise HTTPException(status_code=404, detail="Weight entry not found")

    await db.delete(entry)


@router.get("/weight/trend", response_model=WeightTrend)
async def get_weight_trend(
    days: int = Query(30, ge=7, le=365),
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Get weight trend analysis for the specified period."""
    start_date = datetime.now() - timedelta(days=days)

    result = await db.execute(
        select(BodyWeightEntry)
        .where(
            and_(
                BodyWeightEntry.user_id == current_user.id,
                BodyWeightEntry.timestamp >= start_date,
            )
        )
        .order_by(BodyWeightEntry.timestamp.asc())
    )
    entries = result.scalars().all()

    if not entries:
        raise HTTPException(status_code=404, detail="No weight data for this period")

    start_weight = entries[0].weight_kg
    current_weight = entries[-1].weight_kg
    change = current_weight - start_weight
    change_percent = (change / start_weight) * 100 if start_weight else 0

    # Determine trend
    if abs(change) < 0.5:
        trend = "maintaining"
    elif change < 0:
        trend = "losing"
    else:
        trend = "gaining"

    # Calculate weekly average change
    weeks = days / 7
    avg_weekly = change / weeks if weeks else 0

    data_points = [
        {"date": e.timestamp.date().isoformat(), "weight": e.weight_kg}
        for e in entries
    ]

    return WeightTrend(
        current_weight=current_weight,
        start_weight=start_weight,
        change=round(change, 2),
        change_percent=round(change_percent, 2),
        period_days=days,
        trend=trend,
        avg_weekly_change=round(avg_weekly, 2),
        data_points=data_points,
    )


# Water

@router.get("/water", response_model=List[WaterResponse])
async def list_water_entries(
    date_filter: Optional[date] = Query(None, description="Filter by date"),
    limit: int = Query(100, ge=1, le=500),
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """List water entries."""
    query = select(WaterEntry).where(WaterEntry.user_id == current_user.id)

    if date_filter:
        start = datetime.combine(date_filter, datetime.min.time())
        end = datetime.combine(date_filter, datetime.max.time())
        query = query.where(and_(WaterEntry.timestamp >= start, WaterEntry.timestamp <= end))

    query = query.order_by(WaterEntry.timestamp.desc()).limit(limit)

    result = await db.execute(query)
    return result.scalars().all()


@router.post("/water", response_model=WaterResponse, status_code=status.HTTP_201_CREATED)
async def log_water(
    data: WaterCreate,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Log water intake."""
    entry = WaterEntry(
        user_id=current_user.id,
        amount_ml=data.amount_ml,
        timestamp=data.timestamp,
        source=data.source,
        local_id=data.local_id,
    )

    db.add(entry)
    await db.flush()
    await db.refresh(entry)

    return entry


@router.delete("/water/{entry_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_water_entry(
    entry_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Delete a water entry."""
    result = await db.execute(
        select(WaterEntry).where(
            and_(WaterEntry.id == entry_id, WaterEntry.user_id == current_user.id)
        )
    )
    entry = result.scalar_one_or_none()

    if not entry:
        raise HTTPException(status_code=404, detail="Water entry not found")

    await db.delete(entry)


@router.get("/water/daily/{date_str}", response_model=DailyWaterSummary)
async def get_daily_water(
    date_str: str,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Get water intake summary for a specific date."""
    try:
        target_date = datetime.strptime(date_str, "%Y-%m-%d").date()
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD")

    start = datetime.combine(target_date, datetime.min.time())
    end = datetime.combine(target_date, datetime.max.time())

    result = await db.execute(
        select(WaterEntry).where(
            and_(
                WaterEntry.user_id == current_user.id,
                WaterEntry.timestamp >= start,
                WaterEntry.timestamp <= end,
            )
        )
    )
    entries = result.scalars().all()

    total_ml = sum(e.amount_ml for e in entries)
    goal_ml = current_user.daily_water_goal_ml

    return DailyWaterSummary(
        date=target_date,
        total_ml=total_ml,
        goal_ml=goal_ml,
        entries_count=len(entries),
        goal_achieved=total_ml >= goal_ml,
        percent_of_goal=round((total_ml / goal_ml) * 100, 1) if goal_ml else 0,
    )


# Steps

@router.get("/steps", response_model=List[StepsDailyResponse])
async def list_steps(
    start_date: Optional[date] = Query(None),
    end_date: Optional[date] = Query(None),
    limit: int = Query(30, ge=1, le=365),
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """List daily step counts."""
    query = select(StepsDaily).where(StepsDaily.user_id == current_user.id)

    if start_date:
        query = query.where(StepsDaily.date >= start_date)
    if end_date:
        query = query.where(StepsDaily.date <= end_date)

    query = query.order_by(StepsDaily.date.desc()).limit(limit)

    result = await db.execute(query)
    return result.scalars().all()


@router.post("/steps/sync", response_model=List[StepsDailyResponse])
async def sync_steps(
    steps_data: List[dict],
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Sync step data from HealthKit."""
    synced = []

    for data in steps_data:
        step_date = datetime.strptime(data["date"], "%Y-%m-%d").date()

        # Check for existing entry
        result = await db.execute(
            select(StepsDaily).where(
                and_(StepsDaily.user_id == current_user.id, StepsDaily.date == step_date)
            )
        )
        existing = result.scalar_one_or_none()

        if existing:
            existing.steps = data["steps"]
            existing.distance_km = data.get("distance_km")
            existing.flights_climbed = data.get("flights_climbed")
            existing.active_energy_kcal = data.get("active_energy_kcal")
            existing.synced_at = datetime.utcnow()
            synced.append(existing)
        else:
            entry = StepsDaily(
                user_id=current_user.id,
                date=step_date,
                steps=data["steps"],
                distance_km=data.get("distance_km"),
                flights_climbed=data.get("flights_climbed"),
                active_energy_kcal=data.get("active_energy_kcal"),
                source="health_kit",
                synced_at=datetime.utcnow(),
            )
            db.add(entry)
            synced.append(entry)

    await db.flush()
    return synced


# Progress and Summary

@router.get("/daily/{date_str}", response_model=DailySummary)
async def get_daily_summary(
    date_str: str,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Get complete daily summary."""
    try:
        target_date = datetime.strptime(date_str, "%Y-%m-%d").date()
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD")

    start = datetime.combine(target_date, datetime.min.time())
    end = datetime.combine(target_date, datetime.max.time())

    # Get targets
    targets_result = await db.execute(
        select(MacroTargets).where(MacroTargets.user_id == current_user.id)
    )
    targets = targets_result.scalar_one_or_none()

    # Get meals
    meals_result = await db.execute(
        select(Meal).where(
            and_(Meal.user_id == current_user.id, Meal.timestamp >= start, Meal.timestamp <= end)
        )
    )
    meals = meals_result.scalars().all()

    # Get water
    water_result = await db.execute(
        select(WaterEntry).where(
            and_(WaterEntry.user_id == current_user.id, WaterEntry.timestamp >= start, WaterEntry.timestamp <= end)
        )
    )
    water_entries = water_result.scalars().all()

    # Get workouts
    workouts_result = await db.execute(
        select(WorkoutLog).where(
            and_(WorkoutLog.user_id == current_user.id, WorkoutLog.start_time >= start, WorkoutLog.start_time <= end)
        )
    )
    workouts = workouts_result.scalars().all()

    # Get steps
    steps_result = await db.execute(
        select(StepsDaily).where(
            and_(StepsDaily.user_id == current_user.id, StepsDaily.date == target_date)
        )
    )
    steps_entry = steps_result.scalar_one_or_none()

    # Get weight
    weight_result = await db.execute(
        select(BodyWeightEntry).where(
            and_(BodyWeightEntry.user_id == current_user.id, BodyWeightEntry.timestamp >= start, BodyWeightEntry.timestamp <= end)
        ).order_by(BodyWeightEntry.timestamp.desc())
    )
    weight_entry = weight_result.scalars().first()

    # Calculate totals
    calories = sum(m.total_calories for m in meals)
    protein = sum(m.total_protein_g for m in meals)
    carbs = sum(m.total_carbs_g for m in meals)
    fat = sum(m.total_fat_g for m in meals)
    water_ml = sum(w.amount_ml for w in water_entries)
    workout_min = sum(w.duration_min for w in workouts)

    return DailySummary(
        date=target_date,
        calories_consumed=calories,
        calories_target=targets.calories if targets else None,
        calories_remaining=(targets.calories - calories) if targets else None,
        protein_g=protein,
        protein_target=targets.protein_g if targets else None,
        carbs_g=carbs,
        carbs_target=targets.carbs_g if targets else None,
        fat_g=fat,
        fat_target=targets.fat_g if targets else None,
        meals_count=len(meals),
        steps=steps_entry.steps if steps_entry else None,
        active_calories=steps_entry.active_energy_kcal if steps_entry else None,
        workouts_count=len(workouts),
        workout_minutes=workout_min,
        water_ml=water_ml,
        water_goal_ml=current_user.daily_water_goal_ml,
        weight_kg=weight_entry.weight_kg if weight_entry else None,
    )


@router.get("/progress", response_model=ProgressSummary)
async def get_progress_summary(
    days: int = Query(30, ge=7, le=365),
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Get progress summary for the specified period."""
    end_date = date.today()
    start_date = end_date - timedelta(days=days)

    start = datetime.combine(start_date, datetime.min.time())
    end = datetime.combine(end_date, datetime.max.time())

    # Get targets
    targets_result = await db.execute(
        select(MacroTargets).where(MacroTargets.user_id == current_user.id)
    )
    targets = targets_result.scalar_one_or_none()

    # Get weight entries
    weight_result = await db.execute(
        select(BodyWeightEntry).where(
            and_(BodyWeightEntry.user_id == current_user.id, BodyWeightEntry.timestamp >= start)
        ).order_by(BodyWeightEntry.timestamp)
    )
    weight_entries = weight_result.scalars().all()

    # Get meals
    meals_result = await db.execute(
        select(Meal).where(
            and_(Meal.user_id == current_user.id, Meal.timestamp >= start, Meal.timestamp <= end)
        )
    )
    meals = meals_result.scalars().all()

    # Get workouts
    workouts_result = await db.execute(
        select(WorkoutLog).where(
            and_(WorkoutLog.user_id == current_user.id, WorkoutLog.start_time >= start, WorkoutLog.start_time <= end)
        )
    )
    workouts = workouts_result.scalars().all()

    # Get steps
    steps_result = await db.execute(
        select(StepsDaily).where(
            and_(StepsDaily.user_id == current_user.id, StepsDaily.date >= start_date, StepsDaily.date <= end_date)
        )
    )
    steps = steps_result.scalars().all()

    # Get water
    water_result = await db.execute(
        select(WaterEntry).where(
            and_(WaterEntry.user_id == current_user.id, WaterEntry.timestamp >= start, WaterEntry.timestamp <= end)
        )
    )
    water_entries = water_result.scalars().all()

    # Calculate stats
    weight_start = weight_entries[0].weight_kg if weight_entries else None
    weight_current = weight_entries[-1].weight_kg if weight_entries else current_user.current_weight_kg

    avg_calories = sum(m.total_calories for m in meals) / days if meals else None
    avg_protein = sum(m.total_protein_g for m in meals) / days if meals else None
    avg_steps = sum(s.steps for s in steps) / len(steps) if steps else None
    avg_water = sum(w.amount_ml for w in water_entries) / days if water_entries else None

    # Days meeting calorie target
    days_on_target = 0
    if targets:
        daily_calories = {}
        for meal in meals:
            meal_date = meal.timestamp.date()
            daily_calories[meal_date] = daily_calories.get(meal_date, 0) + meal.total_calories

        for cal in daily_calories.values():
            # Within 10% of target
            if targets.calories * 0.9 <= cal <= targets.calories * 1.1:
                days_on_target += 1

    return ProgressSummary(
        period_start=start_date,
        period_end=end_date,
        period_days=days,
        weight_current=weight_current,
        weight_start=weight_start,
        weight_change=(weight_current - weight_start) if weight_start and weight_current else None,
        weight_goal=current_user.target_weight_kg,
        weight_to_goal=(weight_current - current_user.target_weight_kg) if weight_current and current_user.target_weight_kg else None,
        avg_daily_calories=round(avg_calories) if avg_calories else None,
        avg_daily_protein_g=round(avg_protein, 1) if avg_protein else None,
        calories_target=targets.calories if targets else None,
        protein_target=targets.protein_g if targets else None,
        calorie_adherence_percent=round((avg_calories / targets.calories) * 100, 1) if avg_calories and targets else None,
        protein_adherence_percent=round((avg_protein / targets.protein_g) * 100, 1) if avg_protein and targets else None,
        days_on_target=days_on_target,
        total_workouts=len(workouts),
        total_workout_minutes=sum(w.duration_min for w in workouts),
        avg_daily_steps=round(avg_steps) if avg_steps else None,
        total_calories_burned=sum(w.calories_burned or 0 for w in workouts),
        avg_daily_water_ml=round(avg_water) if avg_water else None,
        water_goal_ml=current_user.daily_water_goal_ml,
        water_goal_days_hit=sum(1 for w in water_entries if w.amount_ml >= current_user.daily_water_goal_ml),
    )


@router.get("/charts/{metric}", response_model=ChartData)
async def get_chart_data(
    metric: str,
    days: int = Query(30, ge=7, le=365),
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Get chart data for a specific metric."""
    end_date = date.today()
    start_date = end_date - timedelta(days=days)
    start = datetime.combine(start_date, datetime.min.time())
    end = datetime.combine(end_date, datetime.max.time())

    data_points: List[ChartDataPoint] = []
    unit = ""
    target = None

    if metric == "weight":
        result = await db.execute(
            select(BodyWeightEntry).where(
                and_(BodyWeightEntry.user_id == current_user.id, BodyWeightEntry.timestamp >= start)
            ).order_by(BodyWeightEntry.timestamp)
        )
        entries = result.scalars().all()
        unit = "kg"
        data_points = [
            ChartDataPoint(date=e.timestamp.date(), value=e.weight_kg)
            for e in entries
        ]
        target = current_user.target_weight_kg

    elif metric == "calories":
        result = await db.execute(
            select(Meal).where(
                and_(Meal.user_id == current_user.id, Meal.timestamp >= start, Meal.timestamp <= end)
            )
        )
        meals = result.scalars().all()
        unit = "kcal"

        # Group by date
        daily = {}
        for meal in meals:
            d = meal.timestamp.date()
            daily[d] = daily.get(d, 0) + meal.total_calories

        data_points = [ChartDataPoint(date=d, value=v) for d, v in sorted(daily.items())]

        targets_result = await db.execute(
            select(MacroTargets).where(MacroTargets.user_id == current_user.id)
        )
        targets_obj = targets_result.scalar_one_or_none()
        target = targets_obj.calories if targets_obj else None

    elif metric == "steps":
        result = await db.execute(
            select(StepsDaily).where(
                and_(StepsDaily.user_id == current_user.id, StepsDaily.date >= start_date)
            ).order_by(StepsDaily.date)
        )
        entries = result.scalars().all()
        unit = "steps"
        data_points = [ChartDataPoint(date=e.date, value=e.steps) for e in entries]
        target = 10000

    elif metric == "water":
        result = await db.execute(
            select(WaterEntry).where(
                and_(WaterEntry.user_id == current_user.id, WaterEntry.timestamp >= start, WaterEntry.timestamp <= end)
            )
        )
        entries = result.scalars().all()
        unit = "ml"

        # Group by date
        daily = {}
        for entry in entries:
            d = entry.timestamp.date()
            daily[d] = daily.get(d, 0) + entry.amount_ml

        data_points = [ChartDataPoint(date=d, value=v) for d, v in sorted(daily.items())]
        target = current_user.daily_water_goal_ml

    else:
        raise HTTPException(status_code=400, detail=f"Unknown metric: {metric}")

    values = [dp.value for dp in data_points]

    return ChartData(
        metric=metric,
        unit=unit,
        data_points=data_points,
        period_start=start_date,
        period_end=end_date,
        average=round(sum(values) / len(values), 1) if values else None,
        minimum=min(values) if values else None,
        maximum=max(values) if values else None,
        target=target,
    )
