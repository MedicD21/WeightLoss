"""Authentication routes."""
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.base import get_auth_db
from app.models.user import UserProfile
from app.schemas.auth import (
    MagicLinkRequest,
    MagicLinkVerify,
    AppleSignInRequest,
    TokenResponse,
    RefreshTokenRequest,
)
from app.services.auth_service import auth_service
from app.utils.auth import get_current_user

router = APIRouter(prefix="/auth", tags=["Authentication"])


@router.post("/magic-link", status_code=status.HTTP_200_OK)
async def request_magic_link(
    request: MagicLinkRequest,
    db: AsyncSession = Depends(get_auth_db),
):
    """
    Request a magic link for email authentication.

    The link will be sent to the provided email address.
    """
    token = auth_service.create_magic_link_token(request.email)
    magic_link_url = auth_service.get_magic_link_url(token)

    # TODO: Send email with magic link
    # For now, return the link in development
    return {
        "message": "Magic link sent to your email",
        "debug_link": magic_link_url,  # Remove in production
    }


@router.post("/verify", response_model=TokenResponse)
async def verify_magic_link(
    request: MagicLinkVerify,
    db: AsyncSession = Depends(get_auth_db),
):
    """
    Verify a magic link token and return authentication tokens.
    """
    email = auth_service.verify_magic_link_token(request.token)

    if not email:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired magic link",
        )

    user = await auth_service.get_or_create_user(db, email)
    return auth_service.create_token_pair(user.id, user.email)


@router.post("/apple", response_model=TokenResponse)
async def sign_in_with_apple(
    request: AppleSignInRequest,
    db: AsyncSession = Depends(get_auth_db),
):
    """
    Sign in with Apple.

    Validates the Apple identity token and creates/retrieves user.
    """
    # TODO: Validate Apple identity token
    # For MVP, we trust the client-provided data

    user = await auth_service.authenticate_with_apple(
        db,
        apple_user_id=request.user_identifier,
        email=request.email,
        full_name=request.full_name,
    )

    return auth_service.create_token_pair(user.id, user.email)


@router.post("/refresh", response_model=TokenResponse)
async def refresh_token(
    request: RefreshTokenRequest,
    db: AsyncSession = Depends(get_auth_db),
):
    """
    Refresh an access token using a refresh token.
    """
    payload = auth_service.verify_token(request.refresh_token, expected_type="refresh")

    if not payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token",
        )

    from uuid import UUID
    user_id = UUID(payload.sub)

    return auth_service.create_token_pair(user_id, payload.email)


@router.post("/logout")
async def logout():
    """
    Log out the current user.

    Note: With JWT, logout is typically handled client-side by discarding tokens.
    Server-side logout would require a token blacklist (not implemented in MVP).
    """
    return {"message": "Logged out successfully"}


@router.get("/validate")
async def validate_token(
    current_user: UserProfile = Depends(get_current_user),
):
    """
    Validate the current auth token.

    Returns user info if token is valid, 401 if invalid/expired.
    """
    return {
        "valid": True,
        "user_id": str(current_user.id),
        "email": current_user.email,
    }
