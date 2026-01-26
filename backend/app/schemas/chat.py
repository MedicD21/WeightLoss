"""Chat and AI schemas."""
from datetime import datetime
from typing import Optional, List, Any
from uuid import UUID

from pydantic import BaseModel, Field, ConfigDict

from app.models.chat import MessageRole


class ToolCall(BaseModel):
    """Tool/function call from AI."""
    id: str
    name: str
    arguments: dict[str, Any]


class ToolResult(BaseModel):
    """Result of a tool call."""
    tool_call_id: str
    result: Any
    success: bool = True
    error: Optional[str] = None


class ChatMessageBase(BaseModel):
    """Base schema for chat message."""
    role: MessageRole
    content: str
    timestamp: datetime


class ChatMessageCreate(ChatMessageBase):
    """Schema for creating a chat message."""
    tool_calls: Optional[List[ToolCall]] = None
    tool_call_id: Optional[str] = None
    tool_name: Optional[str] = None
    conversation_id: Optional[str] = None
    local_id: Optional[str] = Field(None, max_length=100)


class ChatMessageResponse(ChatMessageBase):
    """Schema for chat message response."""
    id: UUID
    user_id: UUID
    tool_calls: Optional[List[dict]] = None
    tool_call_id: Optional[str] = None
    tool_name: Optional[str] = None
    conversation_id: Optional[str] = None
    model_used: Optional[str] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True, protected_namespaces=())


class ChatRequest(BaseModel):
    """Request to chat with AI assistant."""
    message: str = Field(..., min_length=1, max_length=4000)
    conversation_id: Optional[str] = None
    include_context: bool = True  # Include recent history


class ChatResponse(BaseModel):
    """Response from AI assistant."""
    message: str
    role: MessageRole = MessageRole.ASSISTANT
    tool_calls: Optional[List[ToolCall]] = None
    tool_results: Optional[List[ToolResult]] = None
    conversation_id: str
    model_used: str
    tokens_used: Optional[int] = None

    # If tools modified data
    created_entries: Optional[List[dict]] = None
    confirmation_required: Optional[dict] = None

    model_config = ConfigDict(protected_namespaces=())


class PendingAction(BaseModel):
    """Action pending user confirmation."""
    action_type: str  # "add_meal", "add_workout", etc.
    description: str
    data: dict
    confidence: float


class VisionFoodItem(BaseModel):
    """Food item identified by vision AI."""
    name: str
    portion_description: str
    grams_estimate: float
    calories: int
    protein_g: float
    carbs_g: float
    fat_g: float
    confidence: float = Field(..., ge=0, le=1)


class VisionAnalyzeRequest(BaseModel):
    """Request to analyze food image."""
    image_base64: str = Field(..., description="Base64 encoded image")
    prompt: Optional[str] = None  # Additional context from user


class VisionAnalyzeResponse(BaseModel):
    """Response from vision analysis."""
    items: List[VisionFoodItem]
    totals: dict  # {calories, protein_g, carbs_g, fat_g}
    confidence: float = Field(..., ge=0, le=1)
    description: str
    disclaimer: str = "These are AI estimates. Actual values may vary. Please review and adjust."
    model_used: str

    model_config = ConfigDict(protected_namespaces=())


class ConversationHistory(BaseModel):
    """Chat conversation history."""
    conversation_id: str
    messages: List[ChatMessageResponse]
    started_at: datetime
    last_message_at: datetime
    message_count: int


# Tool schemas for the AI assistant

class AddMealToolInput(BaseModel):
    """Input for add_meal tool."""
    name: str
    meal_type: Optional[str] = "other"
    items: List[dict]  # [{name, grams, calories, protein_g, carbs_g, fat_g}]
    timestamp: Optional[datetime] = None


class AddWorkoutToolInput(BaseModel):
    """Input for add_workout tool."""
    name: str
    workout_type: str
    duration_min: int
    exercises: Optional[List[dict]] = None  # [{name, sets, reps, weight_kg}]
    calories_burned: Optional[int] = None
    timestamp: Optional[datetime] = None


class AddWaterToolInput(BaseModel):
    """Input for add_water tool."""
    amount_ml: int
    timestamp: Optional[datetime] = None


class AddWeightToolInput(BaseModel):
    """Input for add_weight tool."""
    weight_kg: float
    timestamp: Optional[datetime] = None
    notes: Optional[str] = None


class SetGoalToolInput(BaseModel):
    """Input for set_goal tool."""
    goal_type: Optional[str] = None  # "cut", "maintain", "bulk"
    goal_rate_kg_per_week: Optional[float] = None
    activity_level: Optional[str] = None
    target_weight_kg: Optional[float] = None


class SearchFoodToolInput(BaseModel):
    """Input for search_food tool."""
    query: Optional[str] = None
    barcode: Optional[str] = None
