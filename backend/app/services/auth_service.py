"""Authentication service for JWT and magic link authentication."""
import secrets
import logging
from datetime import datetime, timedelta, timezone
from typing import Optional
from uuid import UUID

import jwt
from passlib.context import CryptContext
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models.user import UserProfile
from app.schemas.auth import TokenResponse, TokenPayload

logger = logging.getLogger(__name__)
settings = get_settings()

# Password hashing (for future use if needed)
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# In-memory magic link storage (use Redis in production)
# Format: {token: {email: str, expires: datetime}}
_magic_links: dict[str, dict] = {}


class AuthService:
    """Service for handling authentication."""

    def __init__(self):
        """Initialize auth service."""
        self.secret_key = settings.jwt_secret_key
        self.algorithm = settings.jwt_algorithm
        self.access_token_expire = timedelta(minutes=settings.jwt_access_token_expire_minutes)
        self.refresh_token_expire = timedelta(days=settings.jwt_refresh_token_expire_days)
        self.magic_link_expire = timedelta(minutes=settings.magic_link_expire_minutes)

    def create_access_token(
        self,
        user_id: UUID,
        email: str,
        expires_delta: Optional[timedelta] = None,
    ) -> str:
        """
        Create a JWT access token.

        Args:
            user_id: User's UUID
            email: User's email
            expires_delta: Optional custom expiration time

        Returns:
            Encoded JWT token
        """
        expire = datetime.now(timezone.utc) + (expires_delta or self.access_token_expire)

        payload = {
            "sub": str(user_id),
            "email": email,
            "exp": expire,
            "iat": datetime.now(timezone.utc),
            "type": "access",
        }

        return jwt.encode(payload, self.secret_key, algorithm=self.algorithm)

    def create_refresh_token(
        self,
        user_id: UUID,
        email: str,
    ) -> str:
        """
        Create a JWT refresh token.

        Args:
            user_id: User's UUID
            email: User's email

        Returns:
            Encoded JWT token
        """
        expire = datetime.now(timezone.utc) + self.refresh_token_expire

        payload = {
            "sub": str(user_id),
            "email": email,
            "exp": expire,
            "iat": datetime.now(timezone.utc),
            "type": "refresh",
        }

        return jwt.encode(payload, self.secret_key, algorithm=self.algorithm)

    def create_token_pair(
        self,
        user_id: UUID,
        email: str,
    ) -> TokenResponse:
        """
        Create both access and refresh tokens.

        Args:
            user_id: User's UUID
            email: User's email

        Returns:
            TokenResponse with both tokens
        """
        access_token = self.create_access_token(user_id, email)
        refresh_token = self.create_refresh_token(user_id, email)

        return TokenResponse(
            access_token=access_token,
            refresh_token=refresh_token,
            expires_in=int(self.access_token_expire.total_seconds()),
            user_id=str(user_id),
        )

    def verify_token(self, token: str, expected_type: str = "access") -> Optional[TokenPayload]:
        """
        Verify and decode a JWT token.

        Args:
            token: The JWT token to verify
            expected_type: Expected token type ("access" or "refresh")

        Returns:
            Decoded token payload or None if invalid
        """
        try:
            payload = jwt.decode(
                token,
                self.secret_key,
                algorithms=[self.algorithm],
            )

            if payload.get("type") != expected_type:
                logger.warning(f"Token type mismatch: expected {expected_type}")
                return None

            return TokenPayload(
                sub=payload["sub"],
                email=payload["email"],
                exp=datetime.fromtimestamp(payload["exp"], tz=timezone.utc),
                iat=datetime.fromtimestamp(payload["iat"], tz=timezone.utc),
                type=payload["type"],
            )

        except jwt.ExpiredSignatureError:
            logger.warning("Token expired")
            return None
        except jwt.InvalidTokenError as e:
            logger.warning(f"Invalid token: {e}")
            return None

    def create_magic_link_token(self, email: str) -> str:
        """
        Create a magic link token for email authentication.

        Args:
            email: User's email address

        Returns:
            Magic link token
        """
        token = secrets.token_urlsafe(32)
        expires = datetime.now(timezone.utc) + self.magic_link_expire

        _magic_links[token] = {
            "email": email.lower(),
            "expires": expires,
        }

        # Clean up expired tokens
        self._cleanup_expired_magic_links()

        return token

    def verify_magic_link_token(self, token: str) -> Optional[str]:
        """
        Verify a magic link token and return the associated email.

        Args:
            token: The magic link token

        Returns:
            Email address if valid, None otherwise
        """
        link_data = _magic_links.get(token)

        if not link_data:
            return None

        if datetime.now(timezone.utc) > link_data["expires"]:
            del _magic_links[token]
            return None

        email = link_data["email"]
        del _magic_links[token]  # One-time use

        return email

    def get_magic_link_url(self, token: str) -> str:
        """
        Get the full magic link URL.

        Args:
            token: The magic link token

        Returns:
            Full URL for the magic link
        """
        return f"{settings.magic_link_base_url}?token={token}"

    def _cleanup_expired_magic_links(self):
        """Remove expired magic link tokens."""
        now = datetime.now(timezone.utc)
        expired = [
            token for token, data in _magic_links.items()
            if now > data["expires"]
        ]
        for token in expired:
            del _magic_links[token]

    async def get_or_create_user(
        self,
        db: AsyncSession,
        email: str,
    ) -> UserProfile:
        """
        Get existing user or create new one.

        Args:
            db: Database session
            email: User's email

        Returns:
            UserProfile instance
        """
        email = email.lower()

        # Try to find existing user
        result = await db.execute(
            select(UserProfile).where(UserProfile.email == email)
        )
        user = result.scalar_one_or_none()

        if user:
            return user

        # Create new user
        user = UserProfile(
            email=email,
            is_verified=True,  # Verified via magic link
        )
        db.add(user)
        await db.flush()

        return user

    async def authenticate_with_apple(
        self,
        db: AsyncSession,
        apple_user_id: str,
        email: Optional[str],
        full_name: Optional[str],
    ) -> UserProfile:
        """
        Authenticate with Apple Sign In.

        Args:
            db: Database session
            apple_user_id: Apple's user identifier
            email: User's email (may be private relay)
            full_name: User's full name (only provided on first sign in)

        Returns:
            UserProfile instance
        """
        # Try to find by Apple ID
        result = await db.execute(
            select(UserProfile).where(UserProfile.apple_user_id == apple_user_id)
        )
        user = result.scalar_one_or_none()

        if user:
            return user

        # Try to find by email if provided
        if email:
            result = await db.execute(
                select(UserProfile).where(UserProfile.email == email.lower())
            )
            user = result.scalar_one_or_none()

            if user:
                # Link Apple ID to existing account
                user.apple_user_id = apple_user_id
                await db.flush()
                return user

        # Create new user
        user = UserProfile(
            email=email.lower() if email else f"{apple_user_id}@privaterelay.appleid.com",
            apple_user_id=apple_user_id,
            display_name=full_name,
            is_verified=True,
        )
        db.add(user)
        await db.flush()

        return user


# Singleton instance
auth_service = AuthService()
