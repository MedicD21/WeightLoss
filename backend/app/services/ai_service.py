"""AI service for chat assistant and vision analysis."""
import json
import logging
from datetime import datetime
from typing import Optional, Any
from uuid import UUID

from anthropic import AsyncAnthropic
from openai import AsyncOpenAI

from app.config import get_settings
from app.schemas.chat import (
    ToolCall,
    ToolResult,
    VisionFoodItem,
    VisionAnalyzeResponse,
    ChatResponse,
)

logger = logging.getLogger(__name__)
settings = get_settings()


# Tool definitions for the chat assistant
ASSISTANT_TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "add_meal",
            "description": "Log a meal with one or more food items. Use this when the user wants to track food they've eaten.",
            "parameters": {
                "type": "object",
                "properties": {
                    "name": {
                        "type": "string",
                        "description": "Name of the meal (e.g., 'Breakfast', 'Lunch', 'Chicken salad')"
                    },
                    "meal_type": {
                        "type": "string",
                        "enum": ["breakfast", "lunch", "dinner", "snack", "other"],
                        "description": "Type of meal"
                    },
                    "items": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "name": {"type": "string", "description": "Food item name"},
                                "grams": {"type": "number", "description": "Amount in grams"},
                                "calories": {"type": "integer", "description": "Calories"},
                                "protein_g": {"type": "number", "description": "Protein in grams"},
                                "carbs_g": {"type": "number", "description": "Carbohydrates in grams"},
                                "fat_g": {"type": "number", "description": "Fat in grams"}
                            },
                            "required": ["name", "grams", "calories", "protein_g", "carbs_g", "fat_g"]
                        },
                        "description": "List of food items in the meal"
                    },
                    "timestamp": {
                        "type": "string",
                        "description": "ISO timestamp for the meal (optional, defaults to now)"
                    }
                },
                "required": ["name", "items"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "add_workout",
            "description": "Log a workout session. Use this when the user wants to track exercise.",
            "parameters": {
                "type": "object",
                "properties": {
                    "name": {
                        "type": "string",
                        "description": "Name of the workout"
                    },
                    "workout_type": {
                        "type": "string",
                        "enum": ["strength", "cardio", "hiit", "flexibility", "walking", "running", "cycling", "swimming", "sports", "other"],
                        "description": "Type of workout"
                    },
                    "duration_min": {
                        "type": "integer",
                        "description": "Duration in minutes"
                    },
                    "exercises": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "name": {"type": "string"},
                                "sets": {"type": "integer"},
                                "reps": {"type": "integer"},
                                "weight_kg": {"type": "number"}
                            }
                        },
                        "description": "Optional list of exercises with sets/reps"
                    },
                    "calories_burned": {
                        "type": "integer",
                        "description": "Estimated calories burned (optional)"
                    },
                    "timestamp": {
                        "type": "string",
                        "description": "ISO timestamp (optional)"
                    }
                },
                "required": ["name", "workout_type", "duration_min"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "add_workout_plan",
            "description": "Create a workout plan or routine. Use this when the user asks for a plan or schedule.",
            "parameters": {
                "type": "object",
                "properties": {
                    "name": {
                        "type": "string",
                        "description": "Name of the plan (e.g., 'Push/Pull/Legs', 'Beginner Full Body')"
                    },
                    "description": {
                        "type": "string",
                        "description": "Optional plan description"
                    },
                    "workout_type": {
                        "type": "string",
                        "enum": ["strength", "cardio", "hiit", "flexibility", "walking", "running", "cycling", "swimming", "sports", "other"],
                        "description": "Primary type for the plan"
                    },
                    "scheduled_days": {
                        "type": "array",
                        "items": {"type": "integer", "minimum": 0, "maximum": 6},
                        "description": "Optional scheduled days (0=Mon ... 6=Sun)"
                    },
                    "estimated_duration_min": {
                        "type": "integer",
                        "description": "Estimated duration in minutes"
                    },
                    "is_active": {
                        "type": "boolean",
                        "description": "Whether the plan should be active"
                    },
                    "exercises": {
                        "type": "array",
                        "items": {
                            "type": "object",
                            "properties": {
                                "name": {"type": "string"},
                                "muscle_group": {
                                    "type": "string",
                                    "enum": ["chest", "back", "shoulders", "biceps", "triceps", "forearms", "core", "quads", "hamstrings", "glutes", "calves", "full_body", "cardio"]
                                },
                                "equipment": {"type": "string"},
                                "notes": {"type": "string"},
                                "sets": {"type": "integer"},
                                "reps_min": {"type": "integer"},
                                "reps_max": {"type": "integer"},
                                "duration_sec": {"type": "integer"},
                                "rest_sec": {"type": "integer"},
                                "superset_group": {"type": "integer"},
                                "order_index": {"type": "integer"}
                            },
                            "required": ["name"]
                        },
                        "description": "Optional list of exercises in the plan"
                    }
                },
                "required": ["name", "workout_type"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "add_water",
            "description": "Log water intake in oz. ALWAYS convert user's oz to ml before calling (1oz = 30ml). Use when user mentions drinking water.",
            "parameters": {
                "type": "object",
                "properties": {
                    "amount_ml": {
                        "type": "integer",
                        "description": "Amount of water in ml (convert from oz: 1oz = 30ml, 8oz = 240ml, 16oz = 480ml, 20oz = 600ml, 32oz = 960ml)"
                    },
                    "timestamp": {
                        "type": "string",
                        "description": "ISO timestamp (optional)"
                    }
                },
                "required": ["amount_ml"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "add_weight",
            "description": "Log body weight measurement.",
            "parameters": {
                "type": "object",
                "properties": {
                    "weight_kg": {
                        "type": "number",
                        "description": "Body weight in kilograms"
                    },
                    "timestamp": {
                        "type": "string",
                        "description": "ISO timestamp (optional)"
                    },
                    "notes": {
                        "type": "string",
                        "description": "Optional notes"
                    }
                },
                "required": ["weight_kg"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "set_goal",
            "description": "Update user's fitness goals and recalculate macro targets.",
            "parameters": {
                "type": "object",
                "properties": {
                    "goal_type": {
                        "type": "string",
                        "enum": ["cut", "maintain", "bulk"],
                        "description": "Fitness goal type"
                    },
                    "goal_rate_kg_per_week": {
                        "type": "number",
                        "description": "Rate of weight change per week in kg (0-1.0)"
                    },
                    "activity_level": {
                        "type": "string",
                        "enum": ["sedentary", "light", "moderate", "active", "very_active"],
                        "description": "Activity level"
                    },
                    "target_weight_kg": {
                        "type": "number",
                        "description": "Target weight in kg"
                    }
                }
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "set_custom_macros",
            "description": "Set custom macro targets when the user provides exact calorie/macro goals.",
            "parameters": {
                "type": "object",
                "properties": {
                    "calories": {"type": "integer", "description": "Daily calorie target"},
                    "protein_g": {"type": "number", "description": "Protein target in grams"},
                    "carbs_g": {"type": "number", "description": "Carbs target in grams"},
                    "fat_g": {"type": "number", "description": "Fat target in grams"},
                    "fiber_g": {"type": "number", "description": "Optional fiber target in grams"}
                },
                "required": ["calories", "protein_g", "carbs_g", "fat_g"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "search_food",
            "description": "Search for food nutrition information by name or barcode.",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {
                        "type": "string",
                        "description": "Food name to search for"
                    },
                    "barcode": {
                        "type": "string",
                        "description": "Product barcode to look up"
                    }
                }
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_daily_summary",
            "description": "Get today's nutrition and activity summary.",
            "parameters": {
                "type": "object",
                "properties": {
                    "date": {
                        "type": "string",
                        "description": "Date in YYYY-MM-DD format (optional, defaults to today)"
                    }
                }
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "save_favorite_food",
            "description": "Save a food to favorites for quick logging later.",
            "parameters": {
                "type": "object",
                "properties": {
                    "name": {"type": "string", "description": "Food name"},
                    "brand": {"type": "string", "description": "Brand name (optional)"},
                    "calories_per_100g": {"type": "integer", "description": "Calories per 100g"},
                    "protein_per_100g": {"type": "number", "description": "Protein in grams per 100g"},
                    "carbs_per_100g": {"type": "number", "description": "Carbs in grams per 100g"},
                    "fat_per_100g": {"type": "number", "description": "Fat in grams per 100g"},
                    "default_serving_g": {"type": "number", "description": "Default serving size in grams"}
                },
                "required": ["name", "calories_per_100g", "protein_per_100g", "carbs_per_100g", "fat_per_100g"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_favorite_foods",
            "description": "Get user's saved favorite foods.",
            "parameters": {
                "type": "object",
                "properties": {}
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "update_meal",
            "description": "Update an existing meal entry.",
            "parameters": {
                "type": "object",
                "properties": {
                    "meal_id": {"type": "string", "description": "ID of the meal to update"},
                    "name": {"type": "string", "description": "New meal name (optional)"},
                    "meal_type": {
                        "type": "string",
                        "enum": ["breakfast", "lunch", "dinner", "snack", "other"],
                        "description": "New meal type (optional)"
                    }
                },
                "required": ["meal_id"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "delete_meal",
            "description": "Delete a meal entry.",
            "parameters": {
                "type": "object",
                "properties": {
                    "meal_id": {"type": "string", "description": "ID of the meal to delete"}
                },
                "required": ["meal_id"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "update_workout",
            "description": "Update an existing workout entry.",
            "parameters": {
                "type": "object",
                "properties": {
                    "workout_id": {"type": "string", "description": "ID of the workout to update"},
                    "name": {"type": "string", "description": "New workout name (optional)"},
                    "duration_min": {"type": "integer", "description": "New duration in minutes (optional)"}
                },
                "required": ["workout_id"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "delete_workout",
            "description": "Delete a workout entry.",
            "parameters": {
                "type": "object",
                "properties": {
                    "workout_id": {"type": "string", "description": "ID of the workout to delete"}
                },
                "required": ["workout_id"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "update_workout_plan",
            "description": "Update an existing workout plan.",
            "parameters": {
                "type": "object",
                "properties": {
                    "plan_id": {"type": "string", "description": "ID of the plan to update"},
                    "name": {"type": "string", "description": "New plan name (optional)"},
                    "is_active": {"type": "boolean", "description": "Whether plan is active (optional)"}
                },
                "required": ["plan_id"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "delete_workout_plan",
            "description": "Delete a workout plan.",
            "parameters": {
                "type": "object",
                "properties": {
                    "plan_id": {"type": "string", "description": "ID of the plan to delete"}
                },
                "required": ["plan_id"]
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "get_weekly_summary",
            "description": "Get weekly nutrition and activity summary.",
            "parameters": {
                "type": "object",
                "properties": {
                    "week_offset": {
                        "type": "integer",
                        "description": "Weeks ago (0 = this week, 1 = last week, etc.)",
                        "default": 0
                    }
                }
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "add_body_measurements",
            "description": "Log body composition measurements like body fat percentage, muscle mass.",
            "parameters": {
                "type": "object",
                "properties": {
                    "body_fat_percent": {"type": "number", "description": "Body fat percentage"},
                    "muscle_mass_kg": {"type": "number", "description": "Muscle mass in kg"},
                    "water_percent": {"type": "number", "description": "Body water percentage"}
                }
            }
        }
    },
    {
        "type": "function",
        "function": {
            "name": "update_profile",
            "description": "Update user profile information.",
            "parameters": {
                "type": "object",
                "properties": {
                    "display_name": {"type": "string", "description": "Display name"},
                    "height_cm": {"type": "number", "description": "Height in cm"},
                    "date_of_birth": {"type": "string", "description": "Date of birth YYYY-MM-DD"}
                }
            }
        }
    }
]

SYSTEM_PROMPT = """You are Terry, a friendly and knowledgeable fitness assistant for the Logged app. You help users manage all aspects of their fitness journey.

Core capabilities:
1. **Nutrition Tracking**: Log meals, search food database, save favorites, update/delete entries
2. **Workout Tracking**: Log workouts, create workout plans, update/delete entries
3. **Body Metrics**: Track weight, body fat %, muscle mass, water %
4. **Goals & Progress**: Set goals, customize macros, view daily/weekly summaries
5. **Water & Hydration**: Track water intake (ALWAYS use oz/fluid ounces)
6. **Profile Management**: Update user info and preferences

Key behaviors:
- **CRITICAL - Context Awareness**: Pay close attention to conversation flow. If you just asked about water intake and user responds with a number + oz/ml, they are CLEARLY answering about water. Immediately use add_water tool.
- **Imperial Units (REQUIRED)**: ALWAYS use oz for water, lbs for weight. Water conversions: 1 glass = 8oz, 1 bottle = 16-20oz, 1 large bottle = 32oz. Convert to ml for API: multiply oz by 30.
- Be concise, friendly, and proactive. After completing a task, suggest related actions.
- If user requests something outside your capabilities, politely inform them.
- if user ask you to "Be a hard ass", then give them the buisness no bullshit talk. Do not stop until the user says "Okay Terrance".
- When users mention food, log it with add_meal. Estimate portions and macros when needed.
- When users mention exercise, log it with add_workout or create a plan with add_workout_plan.
- When users want to save frequently eaten foods, use save_favorite_food.
- When users want to edit or remove entries, use update/delete tools.
- When users ask about progress, use get_daily_summary or get_weekly_summary.
- If users mention body composition (fat %, muscle mass), use add_body_measurements.
- Make reasonable estimates and mention when values are estimated.
- After completing tasks, suggest 2-3 helpful follow-up actions as quick suggestions.
- **Remember previous messages**: You have conversation history. If you asked a question, the user's next response is likely the answer.

Common food estimates (per typical serving):
- Eggs: 1 large = 72 cal, 6g protein, 0.5g carbs, 5g fat
- Toast/bread: 80 cal, 3g protein, 15g carbs, 1g fat
- Chicken breast (100g): 165 cal, 31g protein, 0g carbs, 3.6g fat
- Rice (1 cup cooked): 200 cal, 4g protein, 45g carbs, 0.5g fat
- Apple: 95 cal, 0.5g protein, 25g carbs, 0.3g fat
- Banana: 105 cal, 1.3g protein, 27g carbs, 0.4g fat

Always confirm actions with a brief summary and offer helpful next steps."""


class AIService:
    """AI service for chat and vision analysis."""

    def __init__(self):
        """Initialize the AI service."""
        self.openai_client = AsyncOpenAI(
            api_key=settings.openai_api_key,
            base_url=settings.openai_base_url,
        ) if settings.openai_api_key else None
        self.anthropic_client = AsyncAnthropic(
            api_key=settings.anthropic_api_key,
        ) if settings.anthropic_api_key else None

    def _select_provider(self) -> Optional[str]:
        """Select the active AI provider based on config and available keys."""
        preferred = settings.ai_provider.lower().strip()

        if preferred == "anthropic" and self.anthropic_client:
            return "anthropic"
        if preferred == "openai" and self.openai_client:
            return "openai"

        if self.anthropic_client:
            return "anthropic"
        if self.openai_client:
            return "openai"

        return None

    def _build_anthropic_tools(self) -> list[dict]:
        """Convert OpenAI-style tool definitions to Anthropic tool schema."""
        tools = []
        for tool in ASSISTANT_TOOLS:
            function = tool.get("function", {})
            tools.append(
                {
                    "name": function.get("name", ""),
                    "description": function.get("description", ""),
                    "input_schema": function.get("parameters", {"type": "object", "properties": {}}),
                }
            )
        return tools

    async def chat(
        self,
        user_message: str,
        conversation_history: Optional[list[dict]] = None,
        user_context: Optional[dict] = None,
        conversation_id: Optional[str] = None,
    ) -> ChatResponse:
        """
        Process a chat message and return response with any tool calls.

        Args:
            user_message: The user's message
            conversation_history: Previous messages in the conversation
            user_context: User profile and current stats for context

        Returns:
            ChatResponse with message and any tool calls
        """
        conversation_id = conversation_id or str(datetime.now().timestamp())
        provider = self._select_provider()
        if not provider:
            return ChatResponse(
                message="AI service is not configured. Please set ANTHROPIC_API_KEY or OPENAI_API_KEY.",
                conversation_id=conversation_id,
                model_used="none",
            )

        # Build messages
        messages = [{"role": "system", "content": SYSTEM_PROMPT}]

        # Add user context if available
        if user_context:
            context_msg = self._build_context_message(user_context)
            messages.append({"role": "system", "content": context_msg})

        # Add conversation history
        if conversation_history:
            messages.extend(conversation_history[-10:])  # Last 10 messages

        # Add current message
        messages.append({"role": "user", "content": user_message})

        try:
            if provider == "anthropic":
                system_prompt = SYSTEM_PROMPT
                if user_context:
                    system_prompt = f"{SYSTEM_PROMPT}\n\n{self._build_context_message(user_context)}"

                anthropic_messages = []
                if conversation_history:
                    anthropic_messages.extend(conversation_history[-10:])
                anthropic_messages.append({"role": "user", "content": user_message})

                response = await self.anthropic_client.messages.create(
                    model=settings.claude_model,
                    messages=anthropic_messages,
                    system=system_prompt,
                    tools=self._build_anthropic_tools(),
                    tool_choice={"type": "auto"},
                    temperature=0.7,
                    max_tokens=settings.claude_max_tokens,
                )

                content_blocks = response.content or []
                message_text = "\n".join(
                    block.text for block in content_blocks
                    if block.type == "text" and block.text
                ).strip()

                tool_calls = [
                    ToolCall(
                        id=block.id,
                        name=block.name,
                        arguments=block.input,
                    )
                    for block in content_blocks
                    if block.type == "tool_use"
                ]

                # If only tools and no text, provide a default message
                if not message_text and tool_calls:
                    message_text = "I've processed your request."

                usage = response.usage
                tokens_used = None
                if usage and hasattr(usage, "input_tokens") and hasattr(usage, "output_tokens"):
                    tokens_used = usage.input_tokens + usage.output_tokens

                return ChatResponse(
                    message=message_text,
                    tool_calls=tool_calls or None,
                    conversation_id=conversation_id,
                    model_used=settings.claude_model,
                    tokens_used=tokens_used,
                )

            response = await self.openai_client.chat.completions.create(
                model=settings.openai_model,
                messages=messages,
                tools=ASSISTANT_TOOLS,
                tool_choice="auto",
                temperature=0.7,
                max_tokens=1000,
            )

            message = response.choices[0].message
            tool_calls = None

            if message.tool_calls:
                tool_calls = [
                    ToolCall(
                        id=tc.id,
                        name=tc.function.name,
                        arguments=json.loads(tc.function.arguments),
                    )
                    for tc in message.tool_calls
                ]

            return ChatResponse(
                message=message.content or "",
                tool_calls=tool_calls,
                conversation_id=conversation_id,
                model_used=settings.openai_model,
                tokens_used=response.usage.total_tokens if response.usage else None,
            )

        except Exception as e:
            logger.error(f"Chat error: {e}")
            return ChatResponse(
                message=f"Sorry, I encountered an error: {str(e)}",
                conversation_id=conversation_id,
                model_used=settings.openai_model,
            )

    async def analyze_food_image(
        self,
        image_base64: str,
        additional_context: Optional[str] = None,
    ) -> VisionAnalyzeResponse:
        """
        Analyze a food image and estimate nutritional content.

        Args:
            image_base64: Base64 encoded image
            additional_context: Optional user-provided context

        Returns:
            VisionAnalyzeResponse with estimated items and totals
        """
        provider = self._select_provider()
        if not provider:
            return VisionAnalyzeResponse(
                items=[],
                totals={"calories": 0, "protein_g": 0, "carbs_g": 0, "fat_g": 0},
                confidence=0,
                description="AI service is not configured.",
                model_used="none",
            )

        prompt = """Analyze this food image and estimate the nutritional content.

For each food item visible, provide:
1. Name of the food
2. Estimated portion size description
3. Estimated weight in grams
4. Estimated calories
5. Estimated protein (g), carbs (g), and fat (g)
6. Your confidence level (0-1)

Respond in JSON format:
{
    "items": [
        {
            "name": "food name",
            "portion_description": "e.g., '1 medium plate', '2 slices'",
            "grams_estimate": 150,
            "calories": 250,
            "protein_g": 20,
            "carbs_g": 30,
            "fat_g": 10,
            "confidence": 0.8
        }
    ],
    "description": "Brief description of what you see",
    "overall_confidence": 0.75
}

Be realistic with estimates. If you're uncertain, use lower confidence scores."""

        if additional_context:
            prompt += f"\n\nUser context: {additional_context}"

        try:
            if provider == "anthropic":
                response = await self.anthropic_client.messages.create(
                    model=settings.claude_vision_model,
                    messages=[
                        {
                            "role": "user",
                            "content": [
                                {"type": "text", "text": prompt},
                                {
                                    "type": "image",
                                    "source": {
                                        "type": "base64",
                                        "media_type": "image/jpeg",
                                        "data": image_base64,
                                    },
                                },
                            ],
                        }
                    ],
                    max_tokens=settings.claude_max_tokens,
                    temperature=0.3,
                )
                content_blocks = response.content or []
                content = "\n".join(
                    block.text for block in content_blocks
                    if block.type == "text" and block.text
                )
            else:
                response = await self.openai_client.chat.completions.create(
                    model=settings.openai_vision_model,
                    messages=[
                        {
                            "role": "user",
                            "content": [
                                {"type": "text", "text": prompt},
                                {
                                    "type": "image_url",
                                    "image_url": {
                                        "url": f"data:image/jpeg;base64,{image_base64}",
                                        "detail": "high",
                                    },
                                },
                            ],
                        }
                    ],
                    max_tokens=1500,
                    temperature=0.3,
                )
                content = response.choices[0].message.content
            # Parse JSON from response
            try:
                # Find JSON in response
                json_start = content.find("{")
                json_end = content.rfind("}") + 1
                if json_start >= 0 and json_end > json_start:
                    data = json.loads(content[json_start:json_end])
                else:
                    raise ValueError("No JSON found in response")

                items = [
                    VisionFoodItem(
                        name=item["name"],
                        portion_description=item.get("portion_description", ""),
                        grams_estimate=item.get("grams_estimate", 100),
                        calories=item.get("calories", 0),
                        protein_g=item.get("protein_g", 0),
                        carbs_g=item.get("carbs_g", 0),
                        fat_g=item.get("fat_g", 0),
                        confidence=item.get("confidence", 0.5),
                    )
                    for item in data.get("items", [])
                ]

                totals = {
                    "calories": sum(i.calories for i in items),
                    "protein_g": sum(i.protein_g for i in items),
                    "carbs_g": sum(i.carbs_g for i in items),
                    "fat_g": sum(i.fat_g for i in items),
                }

                return VisionAnalyzeResponse(
                    items=items,
                    totals=totals,
                    confidence=data.get("overall_confidence", 0.5),
                    description=data.get("description", "Food image analyzed"),
                    model_used=(
                        settings.claude_vision_model if provider == "anthropic"
                        else settings.openai_vision_model
                    ),
                )

            except (json.JSONDecodeError, KeyError) as e:
                logger.error(f"Failed to parse vision response: {e}")
                return VisionAnalyzeResponse(
                    items=[],
                    totals={"calories": 0, "protein_g": 0, "carbs_g": 0, "fat_g": 0},
                    confidence=0,
                    description=f"Failed to parse response: {content[:200]}",
                    model_used=(
                        settings.claude_vision_model if provider == "anthropic"
                        else settings.openai_vision_model
                    ),
                )

        except Exception as e:
            logger.error(f"Vision analysis error: {e}")
            return VisionAnalyzeResponse(
                items=[],
                totals={"calories": 0, "protein_g": 0, "carbs_g": 0, "fat_g": 0},
                confidence=0,
                description=f"Error analyzing image: {str(e)}",
                model_used=(
                    settings.claude_vision_model if provider == "anthropic"
                    else settings.openai_vision_model
                ),
            )

    def _build_context_message(self, user_context: dict) -> str:
        """Build a context message with user info."""
        parts = ["Current user context:"]

        if "name" in user_context:
            parts.append(f"- Name: {user_context['name']}")
        if "goal_type" in user_context:
            parts.append(f"- Goal: {user_context['goal_type']}")
        if "calories_target" in user_context:
            parts.append(f"- Daily calorie target: {user_context['calories_target']} kcal")
        if "protein_target" in user_context:
            parts.append(f"- Daily protein target: {user_context['protein_target']}g")
        if "calories_consumed_today" in user_context:
            parts.append(f"- Calories consumed today: {user_context['calories_consumed_today']} kcal")
        if "water_today_ml" in user_context:
            parts.append(f"- Water today: {user_context['water_today_ml']}ml")

        return "\n".join(parts)


# Singleton instance
ai_service = AIService()
