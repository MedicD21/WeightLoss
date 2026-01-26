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
            "name": "add_water",
            "description": "Log water intake. Use when user mentions drinking water.",
            "parameters": {
                "type": "object",
                "properties": {
                    "amount_ml": {
                        "type": "integer",
                        "description": "Amount of water in milliliters (e.g., 250 for a glass, 500 for a bottle)"
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
    }
]

SYSTEM_PROMPT = """You are Logged, a friendly and knowledgeable fitness assistant. You help users track their nutrition, workouts, water intake, and body weight.

Key behaviors:
1. Be concise and helpful. Don't be overly chatty.
2. When users mention food they've eaten, use the add_meal tool to log it. Estimate portions and macros based on common values.
3. When users mention exercise, use the add_workout tool.
4. When users mention drinking water, use the add_water tool. A glass is ~250ml, a bottle ~500ml.
5. When users mention their weight, use the add_weight tool.
6. If asked about nutrition for a food, use search_food to look it up.
7. Provide encouragement but be realistic about health and fitness.
8. If you're unsure about exact nutritional values, make reasonable estimates based on typical values and mention they are estimates.
9. Convert units as needed (user may say lbs for weight, cups for water, etc.)

Common food estimates (per typical serving):
- Eggs: 1 large = 72 cal, 6g protein, 0.5g carbs, 5g fat
- Toast/bread slice: 80 cal, 3g protein, 15g carbs, 1g fat
- Chicken breast (100g): 165 cal, 31g protein, 0g carbs, 3.6g fat
- Rice (1 cup cooked): 200 cal, 4g protein, 45g carbs, 0.5g fat
- Apple: 95 cal, 0.5g protein, 25g carbs, 0.3g fat
- Banana: 105 cal, 1.3g protein, 27g carbs, 0.4g fat

Always confirm what you've logged with a brief summary."""


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
