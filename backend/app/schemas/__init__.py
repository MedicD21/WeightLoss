"""Pydantic schemas for API validation."""
from app.schemas.user import (
    UserCreate,
    UserUpdate,
    UserResponse,
    MacroTargetsResponse,
    MacroTargetsCalculateRequest,
)
from app.schemas.nutrition import (
    FoodItemCreate,
    FoodItemResponse,
    MealCreate,
    MealUpdate,
    MealResponse,
    SavedFoodCreate,
    SavedFoodResponse,
    OpenFoodFactsProduct,
)
from app.schemas.workout import (
    WorkoutExerciseCreate,
    WorkoutPlanCreate,
    WorkoutPlanResponse,
    WorkoutSetLogCreate,
    WorkoutLogCreate,
    WorkoutLogResponse,
)
from app.schemas.tracking import (
    BodyWeightCreate,
    BodyWeightResponse,
    WaterCreate,
    WaterResponse,
    StepsDailyResponse,
    ProgressSummary,
)
from app.schemas.chat import (
    ChatMessageCreate,
    ChatMessageResponse,
    ChatRequest,
    ChatResponse,
    VisionAnalyzeRequest,
    VisionAnalyzeResponse,
    ToolCall,
)
from app.schemas.auth import (
    MagicLinkRequest,
    MagicLinkVerify,
    AppleSignInRequest,
    TokenResponse,
    RefreshTokenRequest,
)

__all__ = [
    # User
    "UserCreate",
    "UserUpdate",
    "UserResponse",
    "MacroTargetsResponse",
    "MacroTargetsCalculateRequest",
    # Nutrition
    "FoodItemCreate",
    "FoodItemResponse",
    "MealCreate",
    "MealUpdate",
    "MealResponse",
    "SavedFoodCreate",
    "SavedFoodResponse",
    "OpenFoodFactsProduct",
    # Workout
    "WorkoutExerciseCreate",
    "WorkoutPlanCreate",
    "WorkoutPlanResponse",
    "WorkoutSetLogCreate",
    "WorkoutLogCreate",
    "WorkoutLogResponse",
    # Tracking
    "BodyWeightCreate",
    "BodyWeightResponse",
    "WaterCreate",
    "WaterResponse",
    "StepsDailyResponse",
    "ProgressSummary",
    # Chat
    "ChatMessageCreate",
    "ChatMessageResponse",
    "ChatRequest",
    "ChatResponse",
    "VisionAnalyzeRequest",
    "VisionAnalyzeResponse",
    "ToolCall",
    # Auth
    "MagicLinkRequest",
    "MagicLinkVerify",
    "AppleSignInRequest",
    "TokenResponse",
    "RefreshTokenRequest",
]
