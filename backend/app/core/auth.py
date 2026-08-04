import uuid

import httpx
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.session import get_db
from app.models.models import AppUser, UserRole

bearer_scheme = HTTPBearer(auto_error=False)


def _auth_headers(access_token: str | None = None, *, admin: bool = False) -> dict[str, str]:
    key = settings.supabase_secret_key if admin else settings.supabase_publishable_key
    if not settings.supabase_url or not key:
        raise HTTPException(503, "Authentication service is not configured")
    headers = {"apikey": key, "Content-Type": "application/json"}
    if access_token:
        headers["Authorization"] = f"Bearer {access_token}"
    return headers


def supabase_request(
    method: str,
    path: str,
    *,
    access_token: str | None = None,
    admin: bool = False,
    json: dict | None = None,
) -> httpx.Response:
    try:
        return httpx.request(
            method,
            f"{settings.supabase_url.rstrip('/')}/auth/v1{path}",
            headers=_auth_headers(access_token, admin=admin),
            json=json,
            timeout=20,
        )
    except httpx.RequestError as error:
        raise HTTPException(503, "Authentication service is unavailable") from error


def sync_user(db: Session, auth_user: dict) -> AppUser:
    try:
        user_id = uuid.UUID(auth_user["id"])
    except (KeyError, TypeError, ValueError) as error:
        raise HTTPException(401, "Invalid authenticated user") from error
    email = (auth_user.get("email") or "").strip().lower()
    if not email:
        raise HTTPException(401, "Authenticated user has no email")
    user = db.get(AppUser, user_id)
    if user is None:
        role = (
            UserRole.ADMIN
            if settings.initial_admin_email and email == settings.initial_admin_email.strip().lower()
            else UserRole.USER
        )
        user = AppUser(id=user_id, email=email, role=role)
        db.add(user)
    elif user.email != email:
        user.email = email
    db.commit()
    db.refresh(user)
    return user


def get_current_user(
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> AppUser:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise HTTPException(401, "Authentication required")
    response = supabase_request("GET", "/user", access_token=credentials.credentials)
    if response.status_code != 200:
        raise HTTPException(401, "Invalid or expired session")
    user = sync_user(db, response.json())
    if not user.is_active:
        raise HTTPException(403, "User is disabled")
    return user


def require_manager(user: AppUser = Depends(get_current_user)) -> AppUser:
    if user.role not in (UserRole.ADMIN, UserRole.MANAGER):
        raise HTTPException(403, "Manager permission required")
    return user


def require_admin(user: AppUser = Depends(get_current_user)) -> AppUser:
    if user.role != UserRole.ADMIN:
        raise HTTPException(403, "Administrator permission required")
    return user


def user_payload(user: AppUser) -> dict:
    return {
        "id": user.id,
        "email": user.email,
        "role": user.role,
        "isActive": user.is_active,
    }
