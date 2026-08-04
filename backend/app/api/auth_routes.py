import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.auth import (
    get_current_user,
    require_admin,
    supabase_request,
    sync_user,
    user_payload,
)
from app.db.session import get_db
from app.models.models import AppUser, UserRole
from app.schemas.api import LoginRequest, RefreshRequest, UserCreate, UserRoleUpdate

router = APIRouter(prefix="/api/v1")


def _session_payload(auth_payload: dict, profile: AppUser) -> dict:
    return {
        "accessToken": auth_payload["access_token"],
        "refreshToken": auth_payload["refresh_token"],
        "expiresIn": auth_payload.get("expires_in"),
        "tokenType": auth_payload.get("token_type", "bearer"),
        "user": user_payload(profile),
    }


@router.post("/auth/login")
def login(payload: LoginRequest, db: Session = Depends(get_db)):
    response = supabase_request(
        "POST",
        "/token?grant_type=password",
        json={"email": payload.email.strip().lower(), "password": payload.password},
    )
    if response.status_code != 200:
        raise HTTPException(401, "Invalid email or password")
    auth_payload = response.json()
    profile = sync_user(db, auth_payload["user"])
    if not profile.is_active:
        raise HTTPException(403, "User is disabled")
    return _session_payload(auth_payload, profile)


@router.post("/auth/refresh")
def refresh_session(payload: RefreshRequest, db: Session = Depends(get_db)):
    response = supabase_request(
        "POST",
        "/token?grant_type=refresh_token",
        json={"refresh_token": payload.refresh_token},
    )
    if response.status_code != 200:
        raise HTTPException(401, "Invalid or expired refresh token")
    auth_payload = response.json()
    profile = sync_user(db, auth_payload["user"])
    if not profile.is_active:
        raise HTTPException(403, "User is disabled")
    return _session_payload(auth_payload, profile)


@router.get("/auth/me")
def me(user: AppUser = Depends(get_current_user)):
    return user_payload(user)


@router.get("/users")
def list_users(
    _: AppUser = Depends(require_admin),
    db: Session = Depends(get_db),
):
    users = db.scalars(select(AppUser).order_by(AppUser.email)).all()
    return {"items": [user_payload(user) for user in users]}


@router.post("/users", status_code=status.HTTP_201_CREATED)
def create_user(
    payload: UserCreate,
    _: AppUser = Depends(require_admin),
    db: Session = Depends(get_db),
):
    email = payload.email.strip().lower()
    response = supabase_request(
        "POST",
        "/admin/users",
        admin=True,
        json={"email": email, "password": payload.password, "email_confirm": True},
    )
    if response.status_code not in (200, 201):
        detail = response.json().get("msg", "Could not create user")
        raise HTTPException(response.status_code, detail)
    auth_response = response.json()
    auth_user = auth_response.get("user", auth_response)
    profile = AppUser(
        id=uuid.UUID(auth_user["id"]),
        email=email,
        role=UserRole(payload.role),
    )
    db.add(profile)
    db.commit()
    db.refresh(profile)
    return user_payload(profile)


@router.patch("/users/{user_id}/role")
def update_user_role(
    user_id: uuid.UUID,
    payload: UserRoleUpdate,
    current_user: AppUser = Depends(require_admin),
    db: Session = Depends(get_db),
):
    user = db.get(AppUser, user_id)
    if not user:
        raise HTTPException(404, "User not found")
    new_role = UserRole(payload.role)
    if user.id == current_user.id and user.role == UserRole.ADMIN and new_role != UserRole.ADMIN:
        admin_count = db.scalar(select(func.count()).select_from(AppUser).where(AppUser.role == UserRole.ADMIN))
        if admin_count <= 1:
            raise HTTPException(409, "The last administrator cannot be demoted")
    user.role = new_role
    db.commit()
    db.refresh(user)
    return user_payload(user)


@router.delete("/users/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_user(
    user_id: uuid.UUID,
    current_user: AppUser = Depends(require_admin),
    db: Session = Depends(get_db),
):
    if user_id == current_user.id:
        raise HTTPException(409, "You cannot delete your own user")
    user = db.get(AppUser, user_id)
    if not user:
        raise HTTPException(404, "User not found")
    response = supabase_request("DELETE", f"/admin/users/{user_id}", admin=True)
    if response.status_code not in (200, 204):
        raise HTTPException(502, "Could not delete authentication user")
    db.delete(user)
    db.commit()
