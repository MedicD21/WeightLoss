"""AI routes for chat assistant and vision analysis."""
import json
from datetime import datetime
from typing import Optional, List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select, and_
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.base import get_db
from app.models.user import UserProfile, MacroTargets
from app.models.nutrition import Meal, FoodItem, FoodSource, MealType
from app.models.workout import WorkoutLog, WorkoutType, LogSource, WorkoutPlan, WorkoutExercise, MuscleGroup
from app.models.tracking import BodyWeightEntry, WaterEntry
from app.models.chat import ChatMessage, MessageRole, VisionAnalysis
from app.schemas.chat import (
    ChatRequest,
    ChatResponse,
    ChatMessageResponse,
    VisionAnalyzeRequest,
    VisionAnalyzeResponse,
    ConversationHistory,
    ToolCall,
    ToolResult,
)
from app.services.ai_service import ai_service
from app.services.auth_service import auth_service
from app.services.open_food_facts import off_client
from app.utils.auth import get_current_user

router = APIRouter(prefix="/ai", tags=["AI"])


@router.post("/chat", response_model=ChatResponse)
async def chat_with_assistant(
    request: ChatRequest,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """
    Chat with the AI assistant.

    The assistant can help with:
    - Logging meals, workouts, water, and weight
    - Searching for food nutrition info
    - Answering fitness and nutrition questions
    - Updating goals
    """
    # Get conversation history if requested
    conversation_history = []
    if request.include_context and request.conversation_id:
        result = await db.execute(
            select(ChatMessage)
            .where(
                and_(
                    ChatMessage.user_id == current_user.id,
                    ChatMessage.conversation_id == request.conversation_id,
                )
            )
            .order_by(ChatMessage.timestamp)
            .limit(20)
        )
        messages = result.scalars().all()
        # Only include user and assistant messages with non-empty content
        conversation_history = [
            {"role": m.role.value, "content": m.content}
            for m in messages
            if m.role in (MessageRole.USER, MessageRole.ASSISTANT) and m.content and m.content.strip()
        ]

    # Build user context
    targets_result = await db.execute(
        select(MacroTargets).where(MacroTargets.user_id == current_user.id)
    )
    targets = targets_result.scalar_one_or_none()

    # Get today's totals
    today_start = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
    meals_result = await db.execute(
        select(Meal).where(
            and_(Meal.user_id == current_user.id, Meal.timestamp >= today_start)
        )
    )
    today_meals = meals_result.scalars().all()
    calories_today = sum(m.total_calories for m in today_meals)

    water_result = await db.execute(
        select(WaterEntry).where(
            and_(WaterEntry.user_id == current_user.id, WaterEntry.timestamp >= today_start)
        )
    )
    water_today = sum(w.amount_ml for w in water_result.scalars().all())

    user_context = {
        "name": current_user.display_name or "User",
        "goal_type": current_user.goal_type.value if current_user.goal_type else None,
        "calories_target": targets.calories if targets else None,
        "protein_target": targets.protein_g if targets else None,
        "calories_consumed_today": calories_today,
        "water_today_ml": water_today,
    }

    # Get AI response
    response = await ai_service.chat(
        user_message=request.message,
        conversation_history=conversation_history,
        user_context=user_context,
        conversation_id=request.conversation_id,
    )

    # Save user message
    user_msg = ChatMessage(
        user_id=current_user.id,
        role=MessageRole.USER,
        content=request.message,
        timestamp=datetime.utcnow(),
        conversation_id=response.conversation_id,
    )
    db.add(user_msg)

    # Process tool calls if any
    created_entries = []
    tool_results = []

    if response.tool_calls:
        for tool_call in response.tool_calls:
            result = await _execute_tool(
                db, current_user, tool_call
            )
            tool_results.append(result)
            if result.success and result.result:
                created_entries.append({
                    "type": tool_call.name,
                    "data": result.result,
                })

    # Save assistant message
    assistant_msg = ChatMessage(
        user_id=current_user.id,
        role=MessageRole.ASSISTANT,
        content=response.message,
        timestamp=datetime.utcnow(),
        conversation_id=response.conversation_id,
        tool_calls=[tc.model_dump() for tc in response.tool_calls] if response.tool_calls else None,
        model_used=response.model_used,
        tokens_used=response.tokens_used,
    )
    db.add(assistant_msg)

    await db.flush()

    # Create new response with tool results and created entries
    return ChatResponse(
        message=response.message,
        role=response.role,
        tool_calls=response.tool_calls,
        tool_results=tool_results if tool_results else None,
        conversation_id=response.conversation_id,
        model_used=response.model_used,
        tokens_used=response.tokens_used,
        created_entries=created_entries if created_entries else None,
    )


async def _execute_tool(
    db: AsyncSession,
    user: UserProfile,
    tool_call: ToolCall,
) -> ToolResult:
    """Execute a tool call and return the result."""
    try:
        if tool_call.name == "add_meal":
            return await _add_meal(db, user, tool_call.arguments, tool_call.id)

        elif tool_call.name == "add_workout":
            return await _add_workout(db, user, tool_call.arguments, tool_call.id)

        elif tool_call.name == "add_workout_plan":
            return await _add_workout_plan(db, user, tool_call.arguments, tool_call.id)

        elif tool_call.name == "add_water":
            return await _add_water(db, user, tool_call.arguments, tool_call.id)

        elif tool_call.name == "add_weight":
            return await _add_weight(db, user, tool_call.arguments, tool_call.id)

        elif tool_call.name == "set_goal":
            return await _set_goal(db, user, tool_call.arguments, tool_call.id)

        elif tool_call.name == "set_custom_macros":
            return await _set_custom_macros(db, user, tool_call.arguments, tool_call.id)

        elif tool_call.name == "search_food":
            return await _search_food(db, user, tool_call.arguments, tool_call.id)

        elif tool_call.name == "get_daily_summary":
            return await _get_daily_summary(db, user, tool_call.arguments, tool_call.id)

        elif tool_call.name == "save_favorite_food":
            return await _save_favorite_food(db, user, tool_call.arguments, tool_call.id)

        elif tool_call.name == "get_favorite_foods":
            return await _get_favorite_foods(db, user, tool_call.arguments, tool_call.id)

        elif tool_call.name == "update_meal":
            return await _update_meal(db, user, tool_call.arguments, tool_call.id)

        elif tool_call.name == "delete_meal":
            return await _delete_meal(db, user, tool_call.arguments, tool_call.id)

        elif tool_call.name == "update_workout":
            return await _update_workout(db, user, tool_call.arguments, tool_call.id)

        elif tool_call.name == "delete_workout":
            return await _delete_workout(db, user, tool_call.arguments, tool_call.id)

        elif tool_call.name == "update_workout_plan":
            return await _update_workout_plan(db, user, tool_call.arguments, tool_call.id)

        elif tool_call.name == "delete_workout_plan":
            return await _delete_workout_plan(db, user, tool_call.arguments, tool_call.id)

        elif tool_call.name == "get_weekly_summary":
            return await _get_weekly_summary(db, user, tool_call.arguments, tool_call.id)

        elif tool_call.name == "add_body_measurements":
            return await _add_body_measurements(db, user, tool_call.arguments, tool_call.id)

        elif tool_call.name == "update_profile":
            return await _update_profile(db, user, tool_call.arguments, tool_call.id)

        else:
            return ToolResult(
                tool_call_id=tool_call.id,
                result=None,
                success=False,
                error=f"Unknown tool: {tool_call.name}",
            )

    except Exception as e:
        return ToolResult(
            tool_call_id=tool_call.id,
            result=None,
            success=False,
            error=str(e),
        )


async def _add_meal(
    db: AsyncSession,
    user: UserProfile,
    args: dict,
    tool_call_id: str,
) -> ToolResult:
    """Add a meal via tool call."""
    timestamp = datetime.fromisoformat(args["timestamp"]) if args.get("timestamp") else datetime.utcnow()
    meal_type = MealType(args.get("meal_type", "other"))

    meal = Meal(
        user_id=user.id,
        name=args["name"],
        meal_type=meal_type,
        timestamp=timestamp,
    )

    for item_data in args.get("items", []):
        item = FoodItem(
            name=item_data["name"],
            source=FoodSource.CHAT,
            grams=item_data.get("grams", 100),
            calories=item_data["calories"],
            protein_g=item_data["protein_g"],
            carbs_g=item_data["carbs_g"],
            fat_g=item_data["fat_g"],
        )
        meal.items.append(item)

    meal.recalculate_totals()
    db.add(meal)
    await db.flush()

    return ToolResult(
        tool_call_id=tool_call_id,
        result={
            "meal_id": str(meal.id),
            "name": meal.name,
            "total_calories": meal.total_calories,
            "total_protein_g": meal.total_protein_g,
        },
        success=True,
    )


async def _add_workout(
    db: AsyncSession,
    user: UserProfile,
    args: dict,
    tool_call_id: str,
) -> ToolResult:
    """Add a workout via tool call."""
    timestamp = datetime.fromisoformat(args["timestamp"]) if args.get("timestamp") else datetime.utcnow()
    workout_type = WorkoutType(args.get("workout_type", "other"))

    log = WorkoutLog(
        user_id=user.id,
        name=args["name"],
        workout_type=workout_type,
        source=LogSource.CHAT,
        start_time=timestamp,
        duration_min=args["duration_min"],
        calories_burned=args.get("calories_burned"),
    )

    db.add(log)
    await db.flush()

    return ToolResult(
        tool_call_id=tool_call_id,
        result={
            "workout_id": str(log.id),
            "name": log.name,
            "duration_min": log.duration_min,
        },
        success=True,
    )


async def _add_workout_plan(
    db: AsyncSession,
    user: UserProfile,
    args: dict,
    tool_call_id: str,
) -> ToolResult:
    """Add a workout plan via tool call."""
    workout_type_value = args.get("workout_type", "other")
    try:
        workout_type = WorkoutType(workout_type_value)
    except ValueError:
        workout_type = WorkoutType.OTHER

    plan = WorkoutPlan(
        user_id=user.id,
        name=args["name"],
        description=args.get("description"),
        workout_type=workout_type,
        scheduled_days=args.get("scheduled_days"),
        estimated_duration_min=args.get("estimated_duration_min"),
        is_active=args.get("is_active", True),
    )

    for i, ex_data in enumerate(args.get("exercises", [])):
        muscle_group = None
        if ex_data.get("muscle_group"):
            try:
                muscle_group = MuscleGroup(ex_data["muscle_group"])
            except ValueError:
                muscle_group = None

        exercise = WorkoutExercise(
            name=ex_data["name"],
            muscle_group=muscle_group,
            equipment=ex_data.get("equipment"),
            notes=ex_data.get("notes"),
            sets=ex_data.get("sets", 3),
            reps_min=ex_data.get("reps_min"),
            reps_max=ex_data.get("reps_max"),
            duration_sec=ex_data.get("duration_sec"),
            rest_sec=ex_data.get("rest_sec", 60),
            superset_group=ex_data.get("superset_group"),
            order_index=ex_data.get("order_index", i),
        )
        plan.exercises.append(exercise)

    db.add(plan)
    await db.flush()

    return ToolResult(
        tool_call_id=tool_call_id,
        result={
            "plan_id": str(plan.id),
            "name": plan.name,
            "workout_type": plan.workout_type.value,
            "exercise_count": len(plan.exercises),
            "scheduled_days": plan.scheduled_days,
            "estimated_duration_min": plan.estimated_duration_min,
            "description": plan.description,
            "is_active": plan.is_active,
            "exercises": [
                {
                    "id": str(ex.id),
                    "name": ex.name,
                    "muscle_group": ex.muscle_group.value if ex.muscle_group else None,
                    "equipment": ex.equipment,
                    "notes": ex.notes,
                    "sets": ex.sets,
                    "reps_min": ex.reps_min,
                    "reps_max": ex.reps_max,
                    "duration_sec": ex.duration_sec,
                    "rest_sec": ex.rest_sec,
                    "superset_group": ex.superset_group,
                    "order_index": ex.order_index,
                }
                for ex in plan.exercises
            ],
        },
        success=True,
    )


async def _add_water(
    db: AsyncSession,
    user: UserProfile,
    args: dict,
    tool_call_id: str,
) -> ToolResult:
    """Add water intake via tool call."""
    timestamp = datetime.fromisoformat(args["timestamp"]) if args.get("timestamp") else datetime.utcnow()

    entry = WaterEntry(
        user_id=user.id,
        amount_ml=args["amount_ml"],
        timestamp=timestamp,
        source="chat",
    )

    db.add(entry)
    await db.flush()

    return ToolResult(
        tool_call_id=tool_call_id,
        result={
            "entry_id": str(entry.id),
            "amount_ml": entry.amount_ml,
        },
        success=True,
    )


async def _add_weight(
    db: AsyncSession,
    user: UserProfile,
    args: dict,
    tool_call_id: str,
) -> ToolResult:
    """Add weight entry via tool call."""
    timestamp = datetime.fromisoformat(args["timestamp"]) if args.get("timestamp") else datetime.utcnow()

    entry = BodyWeightEntry(
        user_id=user.id,
        weight_kg=args["weight_kg"],
        timestamp=timestamp,
        notes=args.get("notes"),
        source="chat",
    )

    db.add(entry)

    # Update user's current weight
    user.current_weight_kg = args["weight_kg"]

    await db.flush()
    await auth_service.sync_user_profile(user)

    return ToolResult(
        tool_call_id=tool_call_id,
        result={
            "entry_id": str(entry.id),
            "weight_kg": entry.weight_kg,
        },
        success=True,
    )


async def _set_goal(
    db: AsyncSession,
    user: UserProfile,
    args: dict,
    tool_call_id: str,
) -> ToolResult:
    """Update user goals via tool call."""
    from app.models.user import GoalType, ActivityLevel
    from app.services.macro_calculator import MacroCalculator

    if "goal_type" in args:
        user.goal_type = GoalType(args["goal_type"])
    if "goal_rate_kg_per_week" in args:
        user.goal_rate_kg_per_week = args["goal_rate_kg_per_week"]
    if "activity_level" in args:
        user.activity_level = ActivityLevel(args["activity_level"])
    if "target_weight_kg" in args:
        user.target_weight_kg = args["target_weight_kg"]

    # Recalculate macros if we have enough info
    if user.sex and user.age and user.height_cm and user.current_weight_kg:
        calculator = MacroCalculator()
        result = calculator.calculate_macros(
            sex=user.sex,
            weight_kg=user.current_weight_kg,
            height_cm=user.height_cm,
            age=user.age,
            activity_level=user.activity_level,
            goal_type=user.goal_type,
            goal_rate_kg_per_week=user.goal_rate_kg_per_week,
        )

        # Update or create targets
        targets_result = await db.execute(
            select(MacroTargets).where(MacroTargets.user_id == user.id)
        )
        targets = targets_result.scalar_one_or_none()

        if targets:
            targets.calories = result.calories
            targets.protein_g = result.protein_g
            targets.carbs_g = result.carbs_g
            targets.fat_g = result.fat_g
        else:
            targets = MacroTargets(
                user_id=user.id,
                calories=result.calories,
                protein_g=result.protein_g,
                carbs_g=result.carbs_g,
                fat_g=result.fat_g,
            )
            db.add(targets)

    await db.flush()
    await auth_service.sync_user_profile(user)

    return ToolResult(
        tool_call_id=tool_call_id,
        result={
            "goal_type": user.goal_type.value,
            "activity_level": user.activity_level.value,
        },
        success=True,
    )


async def _set_custom_macros(
    db: AsyncSession,
    user: UserProfile,
    args: dict,
    tool_call_id: str,
) -> ToolResult:
    """Set custom macro targets via tool call."""
    targets_result = await db.execute(
        select(MacroTargets).where(MacroTargets.user_id == user.id)
    )
    targets = targets_result.scalar_one_or_none()

    if targets:
        targets.calories = args["calories"]
        targets.protein_g = args["protein_g"]
        targets.carbs_g = args["carbs_g"]
        targets.fat_g = args["fat_g"]
        targets.fiber_g = args.get("fiber_g")
        targets.bmr = None
        targets.tdee = None
        targets.calculated_at = datetime.utcnow()
    else:
        targets = MacroTargets(
            user_id=user.id,
            calories=args["calories"],
            protein_g=args["protein_g"],
            carbs_g=args["carbs_g"],
            fat_g=args["fat_g"],
            fiber_g=args.get("fiber_g"),
            bmr=None,
            tdee=None,
        )
        db.add(targets)

    await db.flush()

    return ToolResult(
        tool_call_id=tool_call_id,
        result={
            "calories": targets.calories,
            "protein_g": targets.protein_g,
            "carbs_g": targets.carbs_g,
            "fat_g": targets.fat_g,
            "fiber_g": targets.fiber_g,
        },
        success=True,
    )


async def _search_food(
    db: AsyncSession,
    user: UserProfile,
    args: dict,
    tool_call_id: str,
) -> ToolResult:
    """Search food via tool call."""
    if args.get("barcode"):
        product = await off_client.get_product_by_barcode(args["barcode"])
        if product:
            return ToolResult(
                tool_call_id=tool_call_id,
                result={
                    "name": product.name,
                    "brand": product.brand,
                    "calories_per_100g": product.calories_per_100g,
                    "protein_per_100g": product.protein_per_100g,
                    "carbs_per_100g": product.carbs_per_100g,
                    "fat_per_100g": product.fat_per_100g,
                },
                success=True,
            )
        return ToolResult(
            tool_call_id=tool_call_id,
            result=None,
            success=False,
            error="Product not found",
        )

    if args.get("query"):
        products = await off_client.search_products(args["query"], page_size=5)
        return ToolResult(
            tool_call_id=tool_call_id,
            result=[
                {
                    "name": p.name,
                    "brand": p.brand,
                    "calories_per_100g": p.calories_per_100g,
                }
                for p in products
            ],
            success=True,
        )

    return ToolResult(
        tool_call_id=tool_call_id,
        result=None,
        success=False,
        error="No query or barcode provided",
    )


async def _get_daily_summary(
    db: AsyncSession,
    user: UserProfile,
    args: dict,
    tool_call_id: str,
) -> ToolResult:
    """Get daily summary via tool call."""
    from app.models.nutrition import Meal

    date_str = args.get("date", datetime.now().strftime("%Y-%m-%d"))
    target_date = datetime.strptime(date_str, "%Y-%m-%d")
    start = target_date.replace(hour=0, minute=0, second=0)
    end = target_date.replace(hour=23, minute=59, second=59)

    meals_result = await db.execute(
        select(Meal).where(
            and_(Meal.user_id == user.id, Meal.timestamp >= start, Meal.timestamp <= end)
        )
    )
    meals = meals_result.scalars().all()

    water_result = await db.execute(
        select(WaterEntry).where(
            and_(WaterEntry.user_id == user.id, WaterEntry.timestamp >= start, WaterEntry.timestamp <= end)
        )
    )
    water = sum(w.amount_ml for w in water_result.scalars().all())

    return ToolResult(
        tool_call_id=tool_call_id,
        result={
            "date": date_str,
            "calories": sum(m.total_calories for m in meals),
            "protein_g": sum(m.total_protein_g for m in meals),
            "carbs_g": sum(m.total_carbs_g for m in meals),
            "fat_g": sum(m.total_fat_g for m in meals),
            "meals_count": len(meals),
            "water_ml": water,
        },
        success=True,
    )


async def _save_favorite_food(
    db: AsyncSession,
    user: UserProfile,
    args: dict,
    tool_call_id: str,
) -> ToolResult:
    """Save a favorite food via tool call."""
    from app.models.nutrition import SavedFood

    food = SavedFood(
        user_id=user.id,
        name=args["name"],
        brand=args.get("brand"),
        source=FoodSource.MANUAL,
        calories_per_100g=args["calories_per_100g"],
        protein_per_100g=args["protein_per_100g"],
        carbs_per_100g=args["carbs_per_100g"],
        fat_per_100g=args["fat_per_100g"],
        default_serving_g=args.get("default_serving_g", 100),
    )
    db.add(food)
    await db.flush()

    return ToolResult(
        tool_call_id=tool_call_id,
        result={
            "food_id": str(food.id),
            "name": food.name,
            "message": f"Saved {food.name} to your favorites!"
        },
        success=True,
    )


async def _get_favorite_foods(
    db: AsyncSession,
    user: UserProfile,
    args: dict,
    tool_call_id: str,
) -> ToolResult:
    """Get favorite foods via tool call."""
    from app.models.nutrition import SavedFood

    result = await db.execute(
        select(SavedFood).where(SavedFood.user_id == user.id).order_by(SavedFood.name)
    )
    foods = result.scalars().all()

    return ToolResult(
        tool_call_id=tool_call_id,
        result={
            "foods": [
                {
                    "id": str(f.id),
                    "name": f.name,
                    "brand": f.brand,
                    "calories_per_100g": f.calories_per_100g,
                    "protein_per_100g": f.protein_per_100g,
                }
                for f in foods
            ]
        },
        success=True,
    )


async def _update_meal(
    db: AsyncSession,
    user: UserProfile,
    args: dict,
    tool_call_id: str,
) -> ToolResult:
    """Update a meal via tool call."""
    meal_id = UUID(args["meal_id"])
    result = await db.execute(
        select(Meal).where(and_(Meal.id == meal_id, Meal.user_id == user.id))
    )
    meal = result.scalar_one_or_none()

    if not meal:
        return ToolResult(
            tool_call_id=tool_call_id,
            result=None,
            success=False,
            error="Meal not found",
        )

    if "name" in args:
        meal.name = args["name"]
    if "meal_type" in args:
        meal.meal_type = MealType(args["meal_type"])

    await db.flush()

    return ToolResult(
        tool_call_id=tool_call_id,
        result={"meal_id": str(meal.id), "name": meal.name, "message": "Meal updated!"},
        success=True,
    )


async def _delete_meal(
    db: AsyncSession,
    user: UserProfile,
    args: dict,
    tool_call_id: str,
) -> ToolResult:
    """Delete a meal via tool call."""
    meal_id = UUID(args["meal_id"])
    result = await db.execute(
        select(Meal).where(and_(Meal.id == meal_id, Meal.user_id == user.id))
    )
    meal = result.scalar_one_or_none()

    if not meal:
        return ToolResult(
            tool_call_id=tool_call_id,
            result=None,
            success=False,
            error="Meal not found",
        )

    meal_name = meal.name
    await db.delete(meal)
    await db.flush()

    return ToolResult(
        tool_call_id=tool_call_id,
        result={"message": f"Deleted {meal_name}"},
        success=True,
    )


async def _update_workout(
    db: AsyncSession,
    user: UserProfile,
    args: dict,
    tool_call_id: str,
) -> ToolResult:
    """Update a workout via tool call."""
    workout_id = UUID(args["workout_id"])
    result = await db.execute(
        select(WorkoutLog).where(and_(WorkoutLog.id == workout_id, WorkoutLog.user_id == user.id))
    )
    workout = result.scalar_one_or_none()

    if not workout:
        return ToolResult(
            tool_call_id=tool_call_id,
            result=None,
            success=False,
            error="Workout not found",
        )

    if "name" in args:
        workout.name = args["name"]
    if "duration_min" in args:
        workout.duration_min = args["duration_min"]

    await db.flush()

    return ToolResult(
        tool_call_id=tool_call_id,
        result={"workout_id": str(workout.id), "name": workout.name, "message": "Workout updated!"},
        success=True,
    )


async def _delete_workout(
    db: AsyncSession,
    user: UserProfile,
    args: dict,
    tool_call_id: str,
) -> ToolResult:
    """Delete a workout via tool call."""
    workout_id = UUID(args["workout_id"])
    result = await db.execute(
        select(WorkoutLog).where(and_(WorkoutLog.id == workout_id, WorkoutLog.user_id == user.id))
    )
    workout = result.scalar_one_or_none()

    if not workout:
        return ToolResult(
            tool_call_id=tool_call_id,
            result=None,
            success=False,
            error="Workout not found",
        )

    workout_name = workout.name
    await db.delete(workout)
    await db.flush()

    return ToolResult(
        tool_call_id=tool_call_id,
        result={"message": f"Deleted {workout_name}"},
        success=True,
    )


async def _update_workout_plan(
    db: AsyncSession,
    user: UserProfile,
    args: dict,
    tool_call_id: str,
) -> ToolResult:
    """Update a workout plan via tool call."""
    plan_id = UUID(args["plan_id"])
    result = await db.execute(
        select(WorkoutPlan).where(and_(WorkoutPlan.id == plan_id, WorkoutPlan.user_id == user.id))
    )
    plan = result.scalar_one_or_none()

    if not plan:
        return ToolResult(
            tool_call_id=tool_call_id,
            result=None,
            success=False,
            error="Plan not found",
        )

    if "name" in args:
        plan.name = args["name"]
    if "is_active" in args:
        plan.is_active = args["is_active"]

    await db.flush()

    return ToolResult(
        tool_call_id=tool_call_id,
        result={"plan_id": str(plan.id), "name": plan.name, "message": "Plan updated!"},
        success=True,
    )


async def _delete_workout_plan(
    db: AsyncSession,
    user: UserProfile,
    args: dict,
    tool_call_id: str,
) -> ToolResult:
    """Delete a workout plan via tool call."""
    plan_id = UUID(args["plan_id"])
    result = await db.execute(
        select(WorkoutPlan).where(and_(WorkoutPlan.id == plan_id, WorkoutPlan.user_id == user.id))
    )
    plan = result.scalar_one_or_none()

    if not plan:
        return ToolResult(
            tool_call_id=tool_call_id,
            result=None,
            success=False,
            error="Plan not found",
        )

    plan_name = plan.name
    await db.delete(plan)
    await db.flush()

    return ToolResult(
        tool_call_id=tool_call_id,
        result={"message": f"Deleted {plan_name}"},
        success=True,
    )


async def _get_weekly_summary(
    db: AsyncSession,
    user: UserProfile,
    args: dict,
    tool_call_id: str,
) -> ToolResult:
    """Get weekly summary via tool call."""
    from datetime import timedelta

    week_offset = args.get("week_offset", 0)
    today = datetime.now()
    week_start = today - timedelta(days=today.weekday() + week_offset * 7)
    week_end = week_start + timedelta(days=7)

    meals_result = await db.execute(
        select(Meal).where(
            and_(Meal.user_id == user.id, Meal.timestamp >= week_start, Meal.timestamp < week_end)
        )
    )
    meals = meals_result.scalars().all()

    workouts_result = await db.execute(
        select(WorkoutLog).where(
            and_(WorkoutLog.user_id == user.id, WorkoutLog.start_time >= week_start, WorkoutLog.start_time < week_end)
        )
    )
    workouts = workouts_result.scalars().all()

    total_calories = sum(m.total_calories for m in meals)
    total_protein = sum(m.total_protein_g for m in meals)
    days_with_data = 7

    return ToolResult(
        tool_call_id=tool_call_id,
        result={
            "week_start": week_start.strftime("%Y-%m-%d"),
            "week_end": week_end.strftime("%Y-%m-%d"),
            "avg_calories_per_day": round(total_calories / days_with_data) if days_with_data > 0 else 0,
            "avg_protein_per_day": round(total_protein / days_with_data, 1) if days_with_data > 0 else 0,
            "total_workouts": len(workouts),
            "total_workout_minutes": sum(w.duration_min for w in workouts if w.duration_min),
        },
        success=True,
    )


async def _add_body_measurements(
    db: AsyncSession,
    user: UserProfile,
    args: dict,
    tool_call_id: str,
) -> ToolResult:
    """Add body measurements via tool call."""
    # Find the most recent weight entry or create a new one
    result = await db.execute(
        select(BodyWeightEntry)
        .where(BodyWeightEntry.user_id == user.id)
        .order_by(BodyWeightEntry.timestamp.desc())
        .limit(1)
    )
    entry = result.scalar_one_or_none()

    # If no recent entry or last entry is > 1 day old, create new
    if not entry or (datetime.utcnow() - entry.timestamp).days > 0:
        entry = BodyWeightEntry(
            user_id=user.id,
            weight_kg=user.current_weight_kg or 70,
            timestamp=datetime.utcnow(),
            source="chat",
        )
        db.add(entry)

    if "body_fat_percent" in args:
        entry.body_fat_percent = args["body_fat_percent"]
    if "muscle_mass_kg" in args:
        entry.muscle_mass_kg = args["muscle_mass_kg"]
    if "water_percent" in args:
        entry.water_percent = args["water_percent"]

    await db.flush()

    return ToolResult(
        tool_call_id=tool_call_id,
        result={
            "entry_id": str(entry.id),
            "body_fat_percent": entry.body_fat_percent,
            "muscle_mass_kg": entry.muscle_mass_kg,
            "water_percent": entry.water_percent,
            "message": "Body measurements logged!"
        },
        success=True,
    )


async def _update_profile(
    db: AsyncSession,
    user: UserProfile,
    args: dict,
    tool_call_id: str,
) -> ToolResult:
    """Update user profile via tool call."""
    if "display_name" in args:
        user.display_name = args["display_name"]
    if "height_cm" in args:
        user.height_cm = args["height_cm"]
    if "date_of_birth" in args:
        user.date_of_birth = datetime.strptime(args["date_of_birth"], "%Y-%m-%d").date()

    await db.flush()

    return ToolResult(
        tool_call_id=tool_call_id,
        result={"message": "Profile updated!", "display_name": user.display_name},
        success=True,
    )


@router.post("/vision/analyze", response_model=VisionAnalyzeResponse)
async def analyze_food_image(
    request: VisionAnalyzeRequest,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """
    Analyze a food image and estimate nutritional content.

    Returns structured estimates of calories and macros for visible food items.
    These are AI estimates and may not be accurate.
    """
    response = await ai_service.analyze_food_image(
        image_base64=request.image_base64,
        additional_context=request.prompt,
    )

    # Save analysis for later reference
    analysis = VisionAnalysis(
        user_id=current_user.id,
        raw_response={"description": response.description},
        parsed_items=[item.model_dump() for item in response.items],
        totals=response.totals,
        confidence=response.confidence,
        model_used=response.model_used,
        analysis_timestamp=datetime.utcnow(),
    )
    db.add(analysis)
    await db.flush()

    return response


@router.get("/chat/history", response_model=List[ChatMessageResponse])
async def get_chat_history(
    conversation_id: Optional[str] = None,
    limit: int = 50,
    db: AsyncSession = Depends(get_db),
    current_user: UserProfile = Depends(get_current_user),
):
    """Get chat message history."""
    query = select(ChatMessage).where(ChatMessage.user_id == current_user.id)

    if conversation_id:
        query = query.where(ChatMessage.conversation_id == conversation_id)

    query = query.order_by(ChatMessage.timestamp.desc()).limit(limit)

    result = await db.execute(query)
    messages = result.scalars().all()

    return list(reversed(messages))
