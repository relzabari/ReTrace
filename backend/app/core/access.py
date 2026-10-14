"""Server-side exercise membership and participant ownership checks."""

import uuid

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models.models import (
    AppUser,
    DeviceSession,
    Exercise,
    ExerciseMember,
    Participant,
    UserRole,
)


def exercise_scope(user: AppUser):
    if user.role == UserRole.ADMIN:
        return True
    return Exercise.id.in_(
        select(ExerciseMember.exercise_id).where(ExerciseMember.user_id == user.id)
    )


def exercise_access(
    db: Session, exercise_id: uuid.UUID, user: AppUser, *, manage: bool = False
) -> Exercise:
    exercise = db.scalar(
        select(Exercise).where(Exercise.id == exercise_id, exercise_scope(user))
    )
    if exercise is None:
        raise HTTPException(404, "Exercise not found")
    if manage and user.role not in (UserRole.ADMIN, UserRole.MANAGER):
        raise HTTPException(403, "Exercise management permission required")
    return exercise


def participant_scope(user: AppUser):
    return (
        True
        if user.role in (UserRole.ADMIN, UserRole.MANAGER)
        else Participant.user_id == user.id
    )


def participant_access(
    db: Session,
    exercise_id: uuid.UUID,
    participant_id: uuid.UUID,
    user: AppUser,
    *,
    write: bool = False
) -> Participant:
    exercise_access(db, exercise_id, user)
    participant = db.get(Participant, participant_id)
    # Even managers must record under their own identity. Administrative ownership
    # assignment is a separate explicit operation.
    if (
        participant is None
        or participant.exercise_id != exercise_id
        or ((write or user.role == UserRole.USER) and participant.user_id != user.id)
    ):
        raise HTTPException(404, "Participant not found in exercise")
    return participant


def session_access(
    db: Session, exercise_id: uuid.UUID, session_id: uuid.UUID, user: AppUser
) -> DeviceSession:
    session = db.get(DeviceSession, session_id)
    if session is None or session.exercise_id != exercise_id:
        raise HTTPException(404, "Device session not found in exercise")
    participant_access(db, exercise_id, session.participant_id, user, write=True)
    return session
