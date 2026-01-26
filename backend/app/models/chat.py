"""Chat and AI interaction models."""
import enum
import uuid
from datetime import datetime
from typing import Optional, List, Any

from sqlalchemy import Enum, String, ForeignKey, DateTime, Text
from sqlalchemy.dialects.postgresql import UUID, JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class MessageRole(str, enum.Enum):
    """Chat message role."""
    USER = "user"
    ASSISTANT = "assistant"
    SYSTEM = "system"
    TOOL = "tool"


class ChatMessage(Base):
    """Chat message in conversation with AI assistant."""

    __tablename__ = "chat_messages"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("user_profiles.id", ondelete="CASCADE"), index=True
    )

    # Message content
    role: Mapped[MessageRole] = mapped_column(Enum(MessageRole))
    content: Mapped[str] = mapped_column(Text)
    timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True)

    # Tool/function calling
    tool_calls: Mapped[Optional[List[dict]]] = mapped_column(JSONB, nullable=True)
    tool_call_id: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    tool_name: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)

    # Conversation grouping (for context)
    conversation_id: Mapped[Optional[str]] = mapped_column(String(100), index=True, nullable=True)

    # Metadata
    model_used: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)
    tokens_used: Mapped[Optional[int]] = mapped_column(nullable=True)

    # Sync
    is_synced: Mapped[bool] = mapped_column(default=True)
    local_id: Mapped[Optional[str]] = mapped_column(String(100), nullable=True)


class VisionAnalysis(Base):
    """Stored vision analysis results."""

    __tablename__ = "vision_analyses"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("user_profiles.id", ondelete="CASCADE"), index=True
    )

    # Image reference
    image_url: Mapped[Optional[str]] = mapped_column(String(500), nullable=True)
    image_hash: Mapped[Optional[str]] = mapped_column(String(64), nullable=True)

    # Analysis results
    raw_response: Mapped[dict] = mapped_column(JSONB)
    parsed_items: Mapped[List[dict]] = mapped_column(JSONB)  # Structured food items
    totals: Mapped[dict] = mapped_column(JSONB)  # Aggregated totals
    confidence: Mapped[float] = mapped_column()

    # Status
    was_accepted: Mapped[bool] = mapped_column(default=False)
    was_edited: Mapped[bool] = mapped_column(default=False)
    linked_meal_id: Mapped[Optional[uuid.UUID]] = mapped_column(
        UUID(as_uuid=True), ForeignKey("meals.id", ondelete="SET NULL"), nullable=True
    )

    # Model info
    model_used: Mapped[str] = mapped_column(String(100))
    analysis_timestamp: Mapped[datetime] = mapped_column(DateTime(timezone=True))
