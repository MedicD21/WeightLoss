"""Workout planning and logging routes."""
from datetime import datetime, date
from typing import Optional, List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select, and_
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.base import get_db
from app.models.user import UserProfile
from app.models.workout import WorkoutPlan, WorkoutExercise, WorkoutLog, WorkoutSetLog
from app.schemas.workout import (
    WorkoutPlanCreate,
    WorkoutPlanUpdate,
    WorkoutPlanResponse,
    WorkoutPlanSummary,
    WorkoutLogCreate,
    WorkoutLogUpdate,
    WorkoutLogResponse,
    WorkoutLogSummary,
    WorkoutExerciseCreate,
    WeeklyWorkoutStats,
)
from app.utils.auth import get_current_user

router = APIRouter(prefix="/workouts", tags=["Workouts"])


# Workout Plans

@router.get("/plans", response_model=List[WorkoutPlanSummary])
async def list_workout_plans(
    active_only: bool = Query(True),
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """List user's workout plans."""
    query = select(WorkoutPlan).where(WorkoutPlan.user_id == current_user.id)

    if active_only:
        query = query.where(WorkoutPlan.is_active == True)

    query = query.order_by(WorkoutPlan.order_index).options(selectinload(WorkoutPlan.exercises))

    result = await db.execute(query)
    plans = result.scalars().all()

    return [
        WorkoutPlanSummary(
            id=p.id,
            name=p.name,
            workout_type=p.workout_type,
            exercise_count=len(p.exercises),
            estimated_duration_min=p.estimated_duration_min,
            scheduled_days=p.scheduled_days,
            is_active=p.is_active,
        )
        for p in plans
    ]


@router.get("/plans/{plan_id}", response_model=WorkoutPlanResponse)
async def get_workout_plan(
    plan_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Get a specific workout plan."""
    result = await db.execute(
        select(WorkoutPlan)
        .where(and_(WorkoutPlan.id == plan_id, WorkoutPlan.user_id == current_user.id))
        .options(selectinload(WorkoutPlan.exercises))
    )
    plan = result.scalar_one_or_none()

    if not plan:
        raise HTTPException(status_code=404, detail="Workout plan not found")

    return plan


@router.post("/plans", response_model=WorkoutPlanResponse, status_code=status.HTTP_201_CREATED)
async def create_workout_plan(
    plan_data: WorkoutPlanCreate,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Create a new workout plan."""
    plan = WorkoutPlan(
        user_id=current_user.id,
        name=plan_data.name,
        description=plan_data.description,
        workout_type=plan_data.workout_type,
        scheduled_days=plan_data.scheduled_days,
        estimated_duration_min=plan_data.estimated_duration_min,
        is_active=plan_data.is_active,
    )

    # Add exercises
    for i, ex_data in enumerate(plan_data.exercises):
        exercise = WorkoutExercise(
            name=ex_data.name,
            muscle_group=ex_data.muscle_group,
            equipment=ex_data.equipment,
            notes=ex_data.notes,
            sets=ex_data.sets,
            reps_min=ex_data.reps_min,
            reps_max=ex_data.reps_max,
            duration_sec=ex_data.duration_sec,
            rest_sec=ex_data.rest_sec,
            superset_group=ex_data.superset_group,
            order_index=ex_data.order_index or i,
        )
        plan.exercises.append(exercise)

    db.add(plan)
    await db.flush()
    await db.refresh(plan)

    return plan


@router.put("/plans/{plan_id}", response_model=WorkoutPlanResponse)
async def update_workout_plan(
    plan_id: UUID,
    updates: WorkoutPlanUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Update a workout plan."""
    result = await db.execute(
        select(WorkoutPlan)
        .where(and_(WorkoutPlan.id == plan_id, WorkoutPlan.user_id == current_user.id))
        .options(selectinload(WorkoutPlan.exercises))
    )
    plan = result.scalar_one_or_none()

    if not plan:
        raise HTTPException(status_code=404, detail="Workout plan not found")

    update_data = updates.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(plan, field, value)

    await db.flush()
    await db.refresh(plan)

    return plan


@router.delete("/plans/{plan_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_workout_plan(
    plan_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Delete a workout plan."""
    result = await db.execute(
        select(WorkoutPlan).where(and_(WorkoutPlan.id == plan_id, WorkoutPlan.user_id == current_user.id))
    )
    plan = result.scalar_one_or_none()

    if not plan:
        raise HTTPException(status_code=404, detail="Workout plan not found")

    await db.delete(plan)


# Workout Logs

@router.get("/logs", response_model=List[WorkoutLogSummary])
async def list_workout_logs(
    start_date: Optional[date] = Query(None),
    end_date: Optional[date] = Query(None),
    workout_type: Optional[str] = Query(None),
    limit: int = Query(50, ge=1, le=100),
    offset: int = Query(0, ge=0),
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """List workout logs with optional filtering."""
    query = select(WorkoutLog).where(WorkoutLog.user_id == current_user.id)

    if start_date:
        query = query.where(WorkoutLog.start_time >= datetime.combine(start_date, datetime.min.time()))
    if end_date:
        query = query.where(WorkoutLog.start_time <= datetime.combine(end_date, datetime.max.time()))
    if workout_type:
        query = query.where(WorkoutLog.workout_type == workout_type)

    query = query.order_by(WorkoutLog.start_time.desc()).offset(offset).limit(limit)
    query = query.options(selectinload(WorkoutLog.sets))

    result = await db.execute(query)
    logs = result.scalars().all()

    return [
        WorkoutLogSummary(
            id=log.id,
            name=log.name,
            workout_type=log.workout_type,
            start_time=log.start_time,
            duration_min=log.duration_min,
            calories_burned=log.calories_burned,
            sets_count=len(log.sets),
            source=log.source,
        )
        for log in logs
    ]


@router.get("/logs/{log_id}", response_model=WorkoutLogResponse)
async def get_workout_log(
    log_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Get a specific workout log."""
    result = await db.execute(
        select(WorkoutLog)
        .where(and_(WorkoutLog.id == log_id, WorkoutLog.user_id == current_user.id))
        .options(selectinload(WorkoutLog.sets))
    )
    log = result.scalar_one_or_none()

    if not log:
        raise HTTPException(status_code=404, detail="Workout log not found")

    return log


@router.post("/logs", response_model=WorkoutLogResponse, status_code=status.HTTP_201_CREATED)
async def create_workout_log(
    log_data: WorkoutLogCreate,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Log a completed workout."""
    # Check for duplicate HealthKit ID
    if log_data.health_kit_id:
        existing = await db.execute(
            select(WorkoutLog).where(WorkoutLog.health_kit_id == log_data.health_kit_id)
        )
        if existing.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Workout already logged from HealthKit",
            )

    log = WorkoutLog(
        user_id=current_user.id,
        plan_id=log_data.plan_id,
        name=log_data.name,
        workout_type=log_data.workout_type,
        source=log_data.source,
        start_time=log_data.start_time,
        end_time=log_data.end_time,
        duration_min=log_data.duration_min,
        calories_burned=log_data.calories_burned,
        avg_heart_rate=log_data.avg_heart_rate,
        max_heart_rate=log_data.max_heart_rate,
        distance_km=log_data.distance_km,
        notes=log_data.notes,
        rating=log_data.rating,
        health_kit_id=log_data.health_kit_id,
        local_id=log_data.local_id,
    )

    # Add set logs
    for i, set_data in enumerate(log_data.sets):
        set_log = WorkoutSetLog(
            exercise_name=set_data.exercise_name,
            set_number=set_data.set_number,
            reps=set_data.reps,
            weight_kg=set_data.weight_kg,
            duration_sec=set_data.duration_sec,
            distance_m=set_data.distance_m,
            completed=set_data.completed,
            is_warmup=set_data.is_warmup,
            is_dropset=set_data.is_dropset,
            rpe=set_data.rpe,
            notes=set_data.notes,
            order_index=set_data.order_index or i,
        )
        log.sets.append(set_log)

    db.add(log)
    await db.flush()
    await db.refresh(log)

    return log


@router.put("/logs/{log_id}", response_model=WorkoutLogResponse)
async def update_workout_log(
    log_id: UUID,
    updates: WorkoutLogUpdate,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Update a workout log."""
    result = await db.execute(
        select(WorkoutLog)
        .where(and_(WorkoutLog.id == log_id, WorkoutLog.user_id == current_user.id))
        .options(selectinload(WorkoutLog.sets))
    )
    log = result.scalar_one_or_none()

    if not log:
        raise HTTPException(status_code=404, detail="Workout log not found")

    update_data = updates.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(log, field, value)

    await db.flush()
    await db.refresh(log)

    return log


@router.delete("/logs/{log_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_workout_log(
    log_id: UUID,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Delete a workout log."""
    result = await db.execute(
        select(WorkoutLog).where(and_(WorkoutLog.id == log_id, WorkoutLog.user_id == current_user.id))
    )
    log = result.scalar_one_or_none()

    if not log:
        raise HTTPException(status_code=404, detail="Workout log not found")

    await db.delete(log)


@router.get("/stats/weekly", response_model=WeeklyWorkoutStats)
async def get_weekly_stats(
    week_offset: int = Query(0, ge=0, le=52, description="Weeks ago (0 = current)"),
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Get workout statistics for a specific week."""
    today = date.today()
    week_start = today - timedelta(days=today.weekday() + (week_offset * 7))
    week_end = week_start + timedelta(days=6)

    result = await db.execute(
        select(WorkoutLog).where(
            and_(
                WorkoutLog.user_id == current_user.id,
                WorkoutLog.start_time >= datetime.combine(week_start, datetime.min.time()),
                WorkoutLog.start_time <= datetime.combine(week_end, datetime.max.time()),
            )
        )
    )
    logs = result.scalars().all()

    total_duration = sum(log.duration_min for log in logs)
    total_calories = sum(log.calories_burned or 0 for log in logs)

    workout_types: dict[str, int] = {}
    for log in logs:
        wt = log.workout_type.value
        workout_types[wt] = workout_types.get(wt, 0) + 1

    return WeeklyWorkoutStats(
        week_start=datetime.combine(week_start, datetime.min.time()),
        total_workouts=len(logs),
        total_duration_min=total_duration,
        total_calories_burned=total_calories if total_calories else None,
        workout_types=workout_types,
        avg_workout_duration=total_duration / len(logs) if logs else None,
    )
