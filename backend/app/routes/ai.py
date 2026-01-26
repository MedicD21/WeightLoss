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
from app.models.workout import WorkoutLog, WorkoutType, LogSource
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
        conversation_history = [
            {"role": m.role.value, "content": m.content}
            for m in messages
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

    response.tool_results = tool_results if tool_results else None
    response.created_entries = created_entries if created_entries else None

    return response


async def _execute_tool(
    db: AsyncSession,
    user: UserProfile,
    tool_call: ToolCall,
) -> ToolResult:
    """Execute a tool call and return the result."""
    try:
        if tool_call.name == "add_meal":
            return await _add_meal(db, user, tool_call.arguments)

        elif tool_call.name == "add_workout":
            return await _add_workout(db, user, tool_call.arguments)

        elif tool_call.name == "add_water":
            return await _add_water(db, user, tool_call.arguments)

        elif tool_call.name == "add_weight":
            return await _add_weight(db, user, tool_call.arguments)

        elif tool_call.name == "set_goal":
            return await _set_goal(db, user, tool_call.arguments)

        elif tool_call.name == "search_food":
            return await _search_food(db, user, tool_call.arguments)

        elif tool_call.name == "get_daily_summary":
            return await _get_daily_summary(db, user, tool_call.arguments)

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


async def _add_meal(db: AsyncSession, user: UserProfile, args: dict) -> ToolResult:
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
        tool_call_id="add_meal",
        result={
            "meal_id": str(meal.id),
            "name": meal.name,
            "total_calories": meal.total_calories,
            "total_protein_g": meal.total_protein_g,
        },
        success=True,
    )


async def _add_workout(db: AsyncSession, user: UserProfile, args: dict) -> ToolResult:
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
        tool_call_id="add_workout",
        result={
            "workout_id": str(log.id),
            "name": log.name,
            "duration_min": log.duration_min,
        },
        success=True,
    )


async def _add_water(db: AsyncSession, user: UserProfile, args: dict) -> ToolResult:
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
        tool_call_id="add_water",
        result={
            "entry_id": str(entry.id),
            "amount_ml": entry.amount_ml,
        },
        success=True,
    )


async def _add_weight(db: AsyncSession, user: UserProfile, args: dict) -> ToolResult:
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

    return ToolResult(
        tool_call_id="add_weight",
        result={
            "entry_id": str(entry.id),
            "weight_kg": entry.weight_kg,
        },
        success=True,
    )


async def _set_goal(db: AsyncSession, user: UserProfile, args: dict) -> ToolResult:
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

    return ToolResult(
        tool_call_id="set_goal",
        result={
            "goal_type": user.goal_type.value,
            "activity_level": user.activity_level.value,
        },
        success=True,
    )


async def _search_food(db: AsyncSession, user: UserProfile, args: dict) -> ToolResult:
    """Search food via tool call."""
    if args.get("barcode"):
        product = await off_client.get_product_by_barcode(args["barcode"])
        if product:
            return ToolResult(
                tool_call_id="search_food",
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
            tool_call_id="search_food",
            result=None,
            success=False,
            error="Product not found",
        )

    if args.get("query"):
        products = await off_client.search_products(args["query"], page_size=5)
        return ToolResult(
            tool_call_id="search_food",
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
        tool_call_id="search_food",
        result=None,
        success=False,
        error="No query or barcode provided",
    )


async def _get_daily_summary(db: AsyncSession, user: UserProfile, args: dict) -> ToolResult:
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
        tool_call_id="get_daily_summary",
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
