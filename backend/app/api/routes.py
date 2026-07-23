import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from geoalchemy2.functions import ST_AsGeoJSON, ST_MakePoint, ST_SetSRID
from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models.models import DeviceSession, Exercise, ExerciseStatus, LocationPoint, Participant
from app.schemas.api import DeviceSessionCreate, ExerciseCreate, LocationBatch, ParticipantCreate

router = APIRouter(prefix="/api/v1")


@router.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@router.post("/exercises", status_code=status.HTTP_201_CREATED)
def create_exercise(payload: ExerciseCreate, db: Session = Depends(get_db)):
    exercise = Exercise(name=payload.name, timezone=payload.timezone)
    db.add(exercise)
    db.commit()
    db.refresh(exercise)
    return {"id": exercise.id, "name": exercise.name, "status": exercise.status}


@router.get("/exercises")
def list_exercises(db: Session = Depends(get_db)):
    exercises = db.scalars(select(Exercise).order_by(Exercise.created_at.desc())).all()
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


@router.get("/exercises/{exercise_id}")
def get_exercise(exercise_id: uuid.UUID, db: Session = Depends(get_db)):
    exercise = db.get(Exercise, exercise_id)
    if not exercise:
        raise HTTPException(404, "Exercise not found")
    return {
        "id": exercise.id,
        "name": exercise.name,
        "status": exercise.status,
        "timezone": exercise.timezone,
        "actualStart": exercise.actual_start,
        "createdAt": exercise.created_at,
    }


@router.post("/exercises/{exercise_id}/participants", status_code=status.HTTP_201_CREATED)
def add_participant(exercise_id: uuid.UUID, payload: ParticipantCreate, db: Session = Depends(get_db)):
    exercise = db.get(Exercise, exercise_id)
    if not exercise:
        raise HTTPException(404, "Exercise not found")
    participant = Participant(exercise_id=exercise_id, **payload.model_dump())
    db.add(participant)
    db.commit()
    db.refresh(participant)
    return {
        "id": participant.id,
        "exerciseId": exercise_id,
        "displayName": participant.display_name,
        "callsign": participant.callsign,
        "trackingMode": participant.tracking_mode,
    }


@router.get("/exercises/{exercise_id}/participants")
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
                "trackingMode": p.tracking_mode,
            }
            for p in participants
        ]
    }


@router.post("/exercises/{exercise_id}/device-sessions", status_code=status.HTTP_201_CREATED)
def create_device_session(exercise_id: uuid.UUID, payload: DeviceSessionCreate, db: Session = Depends(get_db)):
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


@router.post("/exercises/{exercise_id}/start")
def start_exercise(exercise_id: uuid.UUID, db: Session = Depends(get_db)):
    exercise = db.get(Exercise, exercise_id)
    if not exercise:
        raise HTTPException(404, "Exercise not found")
    if exercise.status == ExerciseStatus.ACTIVE:
        raise HTTPException(409, "Exercise already active")
    exercise.status = ExerciseStatus.ACTIVE
    exercise.actual_start = datetime.now(timezone.utc)
    db.commit()
    return {"exerciseId": exercise.id, "status": exercise.status, "actualStart": exercise.actual_start}


@router.post("/exercises/{exercise_id}/locations/batch")
def upload_locations(exercise_id: uuid.UUID, payload: LocationBatch, db: Session = Depends(get_db)):
    exercise = db.get(Exercise, exercise_id)
    if not exercise:
        raise HTTPException(404, "Exercise not found")
    if exercise.status != ExerciseStatus.ACTIVE:
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


@router.get("/exercises/{exercise_id}/tracks/{participant_id}")
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


@router.get("/exercises/{exercise_id}/map-bootstrap")
def map_bootstrap(exercise_id: uuid.UUID, db: Session = Depends(get_db)):
    exercise = db.get(Exercise, exercise_id)
    if not exercise:
        raise HTTPException(404, "Exercise not found")

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
        },
        "participants": [
            {
                "id": p.id,
                "displayName": p.display_name,
                "callsign": p.callsign,
                "trackingMode": p.tracking_mode,
                "pointCount": counts.get(p.id, 0),
            }
            for p in participants
        ],
    }
