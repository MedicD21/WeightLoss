"""API routes."""
from app.routes.auth import router as auth_router
from app.routes.user import router as user_router
from app.routes.nutrition import router as nutrition_router
from app.routes.workout import router as workout_router
from app.routes.tracking import router as tracking_router
from app.routes.ai import router as ai_router

__all__ = [
    "auth_router",
    "user_router",
    "nutrition_router",
    "workout_router",
    "tracking_router",
    "ai_router",
]
