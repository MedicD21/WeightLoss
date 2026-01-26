"""Authentication schemas."""
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, EmailStr, Field


class MagicLinkRequest(BaseModel):
    """Request for magic link authentication."""
    email: EmailStr


class MagicLinkVerify(BaseModel):
    """Verify magic link token."""
    token: str = Field(..., min_length=32)


class AppleSignInRequest(BaseModel):
    """Apple Sign In request."""
    identity_token: str
    authorization_code: str
    user_identifier: str
    email: Optional[EmailStr] = None
    full_name: Optional[str] = None


class TokenResponse(BaseModel):
    """Authentication token response."""
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int  # seconds
    user_id: str


class RefreshTokenRequest(BaseModel):
    """Request to refresh access token."""
    refresh_token: str


class TokenPayload(BaseModel):
    """JWT token payload."""
    sub: str  # user_id
    email: str
    exp: datetime
    iat: datetime
    type: str  # "access" or "refresh"


class AuthStatus(BaseModel):
    """Current authentication status."""
    is_authenticated: bool
    user_id: Optional[str] = None
    email: Optional[str] = None
    token_expires_at: Optional[datetime] = None
