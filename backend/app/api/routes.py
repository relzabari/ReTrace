import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from geoalchemy2.functions import ST_AsGeoJSON, ST_MakePoint, ST_SetSRID
from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.core.auth import get_current_user, require_admin, require_manager
from app.db.session import get_db
from app.models.models import AppUser, DeviceSession, Exercise, ExerciseEvent, ExerciseStatus, LocationPoint, Participant, UserRole
from app.schemas.api import DeviceSessionCreate, EventCreate, ExerciseCreate, ExerciseUpdate, LocationBatch, ParticipantCreate, WebEventCreate

router = APIRouter(prefix="/api/v1")
PARTICIPANT_ROLES = {"רבשץ", "כיתת כוננות", "חמל", "מנהל תרגיל"}
USER_PARTICIPANT_ROLES = {"כיתת כוננות", "חמל"}
CLOSING_GRACE_PERIOD = timedelta(minutes=2)


def maybe_complete_exercise(db: Session, exercise: Exercise) -> bool:
    if exercise.status != ExerciseStatus.ENDING:
        return False
    unfinished_sessions = db.scalar(
        select(func.count(DeviceSession.id)).where(
            DeviceSession.exercise_id == exercise.id,
            DeviceSession.ended_at.is_(None),
        )
    )
    closing_started_at = exercise.closing_started_at or datetime.now(timezone.utc)
    grace_expired = datetime.now(timezone.utc) >= closing_started_at + CLOSING_GRACE_PERIOD
    if unfinished_sessions == 0 or grace_expired:
        exercise.status = ExerciseStatus.COMPLETED
        return True
    return False


def validate_event_time(occurred_at: datetime, exercise_created_at: datetime) -> None:
    if occurred_at.tzinfo is None or occurred_at.utcoffset() is None:
        raise HTTPException(422, "Event time must include a timezone")
    event_time = occurred_at.astimezone(timezone.utc)
    created_at = exercise_created_at.astimezone(timezone.utc)
    now = datetime.now(timezone.utc)
    if event_time < created_at:
        raise HTTPException(422, "Event time cannot be earlier than exercise creation")
    if event_time > now:
        raise HTTPException(422, "Event time cannot be later than the current time")


@router.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@router.post(
    "/exercises",
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(require_manager)],
)
def create_exercise(payload: ExerciseCreate, db: Session = Depends(get_db)):
    exercise = Exercise(name=payload.name, timezone=payload.timezone)
    db.add(exercise)
    db.commit()
    db.refresh(exercise)
    return {
        "id": exercise.id,
        "name": exercise.name,
        "status": exercise.status,
        "createdAt": exercise.created_at,
    }


@router.get("/exercises", dependencies=[Depends(get_current_user)])
def list_exercises(db: Session = Depends(get_db)):
    exercises = db.scalars(select(Exercise).order_by(Exercise.created_at.desc())).all()
    statuses_changed = False
    for exercise in exercises:
        statuses_changed = maybe_complete_exercise(db, exercise) or statuses_changed
    if statuses_changed:
        db.commit()
    return {
        "items": [
            {
                "id": e.id,
                "name": e.name,
                "status": e.status,
                "timezone": e.timezone,
                "actualStart": e.actual_start,
                "createdAt": e.created_at,
            }
            for e in exercises
        ]
    }


@router.get("/exercises/{exercise_id}", dependencies=[Depends(get_current_user)])
def get_exercise(exercise_id: uuid.UUID, db: Session = Depends(get_db)):
    exercise = db.get(Exercise, exercise_id)
    if not exercise:
        raise HTTPException(404, "Exercise not found")
    if maybe_complete_exercise(db, exercise):
        db.commit()
    return {
        "id": exercise.id,
        "name": exercise.name,
        "status": exercise.status,
        "timezone": exercise.timezone,
        "actualStart": exercise.actual_start,
        "createdAt": exercise.created_at,
    }


@router.patch("/exercises/{exercise_id}", dependencies=[Depends(require_manager)])
def update_exercise(
    exercise_id: uuid.UUID,
    payload: ExerciseUpdate,
    db: Session = Depends(get_db),
):
    exercise = db.get(Exercise, exercise_id)
    if not exercise:
        raise HTTPException(404, "Exercise not found")
    exercise.name = payload.name.strip()
    db.commit()
    db.refresh(exercise)
    return {"id": exercise.id, "name": exercise.name, "status": exercise.status}


@router.delete(
    "/exercises/{exercise_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    dependencies=[Depends(require_admin)],
)
def delete_exercise(exercise_id: uuid.UUID, db: Session = Depends(get_db)) -> None:
    exercise = db.get(Exercise, exercise_id)
    if not exercise:
        raise HTTPException(404, "Exercise not found")
    db.delete(exercise)
    db.commit()


@router.post(
    "/exercises/{exercise_id}/participants",
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(get_current_user)],
)
def add_participant(
    exercise_id: uuid.UUID,
    payload: ParticipantCreate,
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    exercise = db.get(Exercise, exercise_id)
    if not exercise:
        raise HTTPException(404, "Exercise not found")
    if exercise.status in (ExerciseStatus.ENDING, ExerciseStatus.COMPLETED):
        raise HTTPException(409, "Exercise is closed")
    if exercise.status == ExerciseStatus.DRAFT and current_user.role == UserRole.USER:
        raise HTTPException(403, "A user can only join an active exercise")
    if payload.role not in PARTICIPANT_ROLES:
        raise HTTPException(422, "Unknown participant role")
    if current_user.role == UserRole.USER and payload.role not in USER_PARTICIPANT_ROLES:
        raise HTTPException(403, "This participant role is not allowed for a USER account")
    participant = Participant(exercise_id=exercise_id, **payload.model_dump())
    db.add(participant)
    db.commit()
    db.refresh(participant)
    return {
        "id": participant.id,
        "exerciseId": exercise_id,
        "displayName": participant.display_name,
        "callsign": participant.callsign,
        "role": participant.role,
        "trackingMode": participant.tracking_mode,
    }


@router.get("/exercises/{exercise_id}/participants", dependencies=[Depends(get_current_user)])
def list_participants(exercise_id: uuid.UUID, db: Session = Depends(get_db)):
    exercise = db.get(Exercise, exercise_id)
    if not exercise:
        raise HTTPException(404, "Exercise not found")
    participants = db.scalars(
        select(Participant).where(Participant.exercise_id == exercise_id).order_by(Participant.display_name)
    ).all()
    return {
        "items": [
            {
                "id": p.id,
                "displayName": p.display_name,
                "callsign": p.callsign,
                "role": p.role,
                "trackingMode": p.tracking_mode,
            }
            for p in participants
        ]
    }


@router.post(
    "/exercises/{exercise_id}/device-sessions",
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(get_current_user)],
)
def create_device_session(
    exercise_id: uuid.UUID,
    payload: DeviceSessionCreate,
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    exercise = db.get(Exercise, exercise_id)
    if not exercise:
        raise HTTPException(404, "Exercise not found")
    if exercise.status in (ExerciseStatus.ENDING, ExerciseStatus.COMPLETED):
        raise HTTPException(409, "Exercise is closed")
    if exercise.status == ExerciseStatus.DRAFT and current_user.role == UserRole.USER:
        raise HTTPException(403, "A user can only join an active exercise")
    participant = db.get(Participant, payload.participant_id)
    if not participant or participant.exercise_id != exercise_id:
        raise HTTPException(404, "Participant not found in exercise")
    session = DeviceSession(
        exercise_id=exercise_id,
        participant_id=payload.participant_id,
        device_id=payload.device_id,
        clock_offset_ms=payload.clock_offset_ms,
    )
    db.add(session)
    db.commit()
    db.refresh(session)
    return {
        "deviceSessionId": session.id,
        "exerciseId": exercise_id,
        "participantId": session.participant_id,
    }


@router.post("/exercises/{exercise_id}/start", dependencies=[Depends(require_manager)])
def start_exercise(exercise_id: uuid.UUID, db: Session = Depends(get_db)):
    exercise = db.get(Exercise, exercise_id)
    if not exercise:
        raise HTTPException(404, "Exercise not found")
    if exercise.status != ExerciseStatus.DRAFT:
        raise HTTPException(409, "Only a draft exercise can be started")
    exercise.status = ExerciseStatus.ACTIVE
    exercise.actual_start = datetime.now(timezone.utc)
    db.commit()
    return {"exerciseId": exercise.id, "status": exercise.status, "actualStart": exercise.actual_start}


@router.post("/exercises/{exercise_id}/close", dependencies=[Depends(require_manager)])
def close_exercise(exercise_id: uuid.UUID, db: Session = Depends(get_db)):
    exercise = db.get(Exercise, exercise_id)
    if not exercise:
        raise HTTPException(404, "Exercise not found")
    if exercise.status != ExerciseStatus.ACTIVE:
        raise HTTPException(409, "Only an active exercise can be closed")
    exercise.status = ExerciseStatus.ENDING
    exercise.closing_started_at = datetime.now(timezone.utc)
    maybe_complete_exercise(db, exercise)
    db.commit()
    return {"exerciseId": exercise.id, "status": exercise.status}


@router.post(
    "/exercises/{exercise_id}/device-sessions/{device_session_id}/finish",
    dependencies=[Depends(get_current_user)],
)
def finish_device_session(
    exercise_id: uuid.UUID,
    device_session_id: uuid.UUID,
    db: Session = Depends(get_db),
):
    exercise = db.get(Exercise, exercise_id)
    if not exercise:
        raise HTTPException(404, "Exercise not found")
    device_session = db.get(DeviceSession, device_session_id)
    if not device_session or device_session.exercise_id != exercise_id:
        raise HTTPException(404, "Device session not found in exercise")
    if exercise.status not in (ExerciseStatus.ENDING, ExerciseStatus.COMPLETED):
        raise HTTPException(409, "Exercise is not closing")
    if device_session.ended_at is None:
        device_session.ended_at = datetime.now(timezone.utc)
    maybe_complete_exercise(db, exercise)
    db.commit()
    return {"exerciseId": exercise.id, "status": exercise.status}


@router.post("/exercises/{exercise_id}/locations/batch", dependencies=[Depends(get_current_user)])
def upload_locations(exercise_id: uuid.UUID, payload: LocationBatch, db: Session = Depends(get_db)):
    exercise = db.get(Exercise, exercise_id)
    if not exercise:
        raise HTTPException(404, "Exercise not found")
    if maybe_complete_exercise(db, exercise):
        db.commit()
    if exercise.status not in (ExerciseStatus.ACTIVE, ExerciseStatus.ENDING):
        raise HTTPException(409, "Exercise is not active")

    device_session = db.get(DeviceSession, payload.device_session_id)
    if not device_session or device_session.exercise_id != exercise_id:
        raise HTTPException(404, "Device session not found in exercise")

    rows = []
    for p in payload.points:
        rows.append(
            {
                "exercise_id": exercise_id,
                "participant_id": device_session.participant_id,
                "device_session_id": device_session.id,
                "sequence_number": p.sequence,
                "captured_at": p.captured_at,
                "location": ST_SetSRID(ST_MakePoint(p.longitude, p.latitude), 4326),
                "horizontal_accuracy": p.horizontal_accuracy,
                "speed": p.speed,
                "heading": p.heading,
                "battery_level": p.battery_level,
            }
        )

    stmt = (
        insert(LocationPoint)
        .values(rows)
        .on_conflict_do_nothing(constraint="uq_device_sequence")
        .returning(LocationPoint.sequence_number)
    )
    accepted_sequences = list(db.scalars(stmt))
    db.commit()

    return {
        "accepted": len(accepted_sequences),
        "duplicates": len(payload.points) - len(accepted_sequences),
        "highestAcceptedSequence": max((p.sequence for p in payload.points), default=None),
        "serverTime": datetime.now(timezone.utc),
    }


@router.post(
    "/exercises/{exercise_id}/events",
    status_code=status.HTTP_201_CREATED,
    dependencies=[Depends(get_current_user)],
)
def create_event(exercise_id: uuid.UUID, payload: EventCreate, db: Session = Depends(get_db)):
    exercise = db.get(Exercise, exercise_id)
    if not exercise:
        raise HTTPException(404, "Exercise not found")
    if exercise.status != ExerciseStatus.ACTIVE:
        raise HTTPException(409, "Exercise is not active")
    validate_event_time(payload.occurred_at, exercise.created_at)

    device_session = db.get(DeviceSession, payload.device_session_id)
    if not device_session or device_session.exercise_id != exercise_id:
        raise HTTPException(404, "Device session not found in exercise")
    participant = db.get(Participant, device_session.participant_id)
    if not participant:
        raise HTTPException(404, "Participant not found in exercise")

    event = ExerciseEvent(
        exercise_id=exercise_id,
        participant_id=participant.id,
        device_session_id=device_session.id,
        occurred_at=payload.occurred_at,
        location=ST_SetSRID(ST_MakePoint(payload.longitude, payload.latitude), 4326),
        reporter_name=participant.display_name,
        reporter_role=participant.role,
        description=payload.description.strip(),
    )
    db.add(event)
    db.commit()
    db.refresh(event)
    return {
        "id": event.id,
        "exerciseId": exercise_id,
        "occurredAt": event.occurred_at,
        "latitude": payload.latitude,
        "longitude": payload.longitude,
        "reporterName": event.reporter_name,
        "reporterRole": event.reporter_role,
        "description": event.description,
    }


@router.post(
    "/exercises/{exercise_id}/events/web",
    status_code=status.HTTP_201_CREATED,
)
def create_web_event(
    exercise_id: uuid.UUID,
    payload: WebEventCreate,
    current_user: AppUser = Depends(require_manager),
    db: Session = Depends(get_db),
):
    description = payload.description.strip()
    if not description:
        raise HTTPException(422, "Event description cannot be blank")
    exercise = db.get(Exercise, exercise_id)
    if not exercise:
        raise HTTPException(404, "Exercise not found")
    if exercise.status != ExerciseStatus.ACTIVE:
        raise HTTPException(409, "Exercise is not active")
    validate_event_time(payload.occurred_at, exercise.created_at)
    event = ExerciseEvent(
        exercise_id=exercise_id,
        participant_id=None,
        device_session_id=None,
        occurred_at=payload.occurred_at,
        location=ST_SetSRID(ST_MakePoint(payload.longitude, payload.latitude), 4326),
        reporter_name=current_user.email,
        reporter_role=current_user.role.value,
        description=description,
    )
    db.add(event)
    db.commit()
    db.refresh(event)
    return {
        "id": event.id,
        "exerciseId": exercise_id,
        "participantId": None,
        "occurredAt": event.occurred_at,
        "latitude": payload.latitude,
        "longitude": payload.longitude,
        "reporterName": event.reporter_name,
        "reporterRole": event.reporter_role,
        "description": event.description,
    }


@router.get("/exercises/{exercise_id}/events", dependencies=[Depends(get_current_user)])
def list_events(exercise_id: uuid.UUID, db: Session = Depends(get_db)):
    exercise = db.get(Exercise, exercise_id)
    if not exercise:
        raise HTTPException(404, "Exercise not found")

    rows = db.execute(
        select(
            ExerciseEvent.id,
            ExerciseEvent.participant_id,
            ExerciseEvent.occurred_at,
            ExerciseEvent.reporter_name,
            ExerciseEvent.reporter_role,
            ExerciseEvent.description,
            ST_AsGeoJSON(ExerciseEvent.location).label("geojson"),
        )
        .where(ExerciseEvent.exercise_id == exercise_id)
        .order_by(ExerciseEvent.occurred_at)
    ).all()

    import json

    items = []
    for row in rows:
        geometry = json.loads(row.geojson)
        longitude, latitude = geometry["coordinates"][:2]
        items.append(
            {
                "id": row.id,
                "participantId": row.participant_id,
                "occurredAt": row.occurred_at,
                "latitude": latitude,
                "longitude": longitude,
                "reporterName": row.reporter_name,
                "reporterRole": row.reporter_role,
                "description": row.description,
            }
        )
    return {"items": items}


@router.get(
    "/exercises/{exercise_id}/tracks/{participant_id}",
    dependencies=[Depends(get_current_user)],
)
def get_track(exercise_id: uuid.UUID, participant_id: uuid.UUID, db: Session = Depends(get_db)):
    participant = db.get(Participant, participant_id)
    if not participant or participant.exercise_id != exercise_id:
        raise HTTPException(404, "Participant not found in exercise")

    rows = db.execute(
        select(
            LocationPoint.sequence_number,
            LocationPoint.captured_at,
            LocationPoint.horizontal_accuracy,
            LocationPoint.speed,
            LocationPoint.heading,
            ST_AsGeoJSON(LocationPoint.location).label("geojson"),
        )
        .where(LocationPoint.exercise_id == exercise_id, LocationPoint.participant_id == participant_id)
        .order_by(LocationPoint.captured_at)
    ).all()

    import json

    points = []
    for row in rows:
        geometry = json.loads(row.geojson)
        longitude, latitude = geometry["coordinates"][:2]
        points.append(
            {
                "sequence": row.sequence_number,
                "capturedAt": row.captured_at,
                "latitude": latitude,
                "longitude": longitude,
                "accuracy": row.horizontal_accuracy,
                "speed": row.speed,
                "heading": row.heading,
            }
        )

    return {
        "participantId": participant_id,
        "displayName": participant.display_name,
        "count": len(points),
        "points": points,
    }


@router.get("/exercises/{exercise_id}/map-bootstrap", dependencies=[Depends(get_current_user)])
def map_bootstrap(exercise_id: uuid.UUID, db: Session = Depends(get_db)):
    exercise = db.get(Exercise, exercise_id)
    if not exercise:
        raise HTTPException(404, "Exercise not found")
    if maybe_complete_exercise(db, exercise):
        db.commit()

    participants = db.scalars(
        select(Participant).where(Participant.exercise_id == exercise_id).order_by(Participant.display_name)
    ).all()

    counts = dict(
        db.execute(
            select(LocationPoint.participant_id, func.count(LocationPoint.id))
            .where(LocationPoint.exercise_id == exercise_id)
            .group_by(LocationPoint.participant_id)
        ).all()
    )

    return {
        "exercise": {
            "id": exercise.id,
            "name": exercise.name,
            "status": exercise.status,
            "actualStart": exercise.actual_start,
            "createdAt": exercise.created_at,
        },
        "participants": [
            {
                "id": p.id,
                "displayName": p.display_name,
                "callsign": p.callsign,
                "role": p.role,
                "trackingMode": p.tracking_mode,
                "pointCount": counts.get(p.id, 0),
            }
            for p in participants
        ],
    }
