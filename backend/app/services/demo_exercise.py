import math
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from geoalchemy2.functions import ST_MakePoint, ST_SetSRID
from sqlalchemy.orm import Session

from app.models.models import (
    AppUser,
    DeviceSession,
    Exercise,
    ExerciseEvent,
    ExerciseMember,
    ExerciseStatus,
    LocationPoint,
    Participant,
)
from app.schemas.api import DemoExerciseCreate, DemoParticipantCreate

MAX_POINTS_PER_PARTICIPANT = 20_000
MAX_TOTAL_POINTS = 100_000


@dataclass(frozen=True)
class GeneratedPoint:
    captured_at: datetime
    latitude: float
    longitude: float


def _distance_meters(a_lat: float, a_lon: float, b_lat: float, b_lon: float) -> float:
    radius = 6_371_000.0
    lat1 = math.radians(a_lat)
    lat2 = math.radians(b_lat)
    d_lat = lat2 - lat1
    d_lon = math.radians(b_lon - a_lon)
    haversine = (
        math.sin(d_lat / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin(d_lon / 2) ** 2
    )
    return radius * 2 * math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine))


def _anchor_times(participant: DemoParticipantCreate) -> list[datetime]:
    explicit = [point.occurred_at for point in participant.route]
    if all(value is not None for value in explicit):
        return [value for value in explicit if value is not None]

    distances = [0.0]
    for previous, current in zip(participant.route, participant.route[1:]):
        distances.append(
            distances[-1]
            + _distance_meters(
                previous.latitude,
                previous.longitude,
                current.latitude,
                current.longitude,
            )
        )
    duration = participant.end_time - participant.start_time
    if distances[-1] == 0:
        step = duration / (len(participant.route) - 1)
        return [participant.start_time + step * index for index in range(len(distances))]
    return [
        participant.start_time + duration * (distance / distances[-1])
        for distance in distances
    ]


def generate_route_points(participant: DemoParticipantCreate) -> list[GeneratedPoint]:
    anchors = _anchor_times(participant)
    duration_seconds = (participant.end_time - participant.start_time).total_seconds()
    estimated_count = math.ceil(duration_seconds / participant.interval_seconds) + 1
    if estimated_count > MAX_POINTS_PER_PARTICIPANT:
        raise ValueError(
            f"Participant {participant.display_name} would create more than "
            f"{MAX_POINTS_PER_PARTICIPANT} points"
        )

    timestamps = []
    current = participant.start_time
    interval = timedelta(seconds=participant.interval_seconds)
    while current < participant.end_time:
        timestamps.append(current)
        current += interval
    timestamps.append(participant.end_time)

    generated: list[GeneratedPoint] = []
    segment_index = 0
    for timestamp in timestamps:
        while (
            segment_index < len(anchors) - 2
            and timestamp > anchors[segment_index + 1]
        ):
            segment_index += 1
        start_time = anchors[segment_index]
        end_time = anchors[segment_index + 1]
        start_point = participant.route[segment_index]
        end_point = participant.route[segment_index + 1]
        segment_duration = (end_time - start_time).total_seconds()
        fraction = (
            0.0
            if segment_duration <= 0
            else max(
                0.0,
                min(1.0, (timestamp - start_time).total_seconds() / segment_duration),
            )
        )
        generated.append(
            GeneratedPoint(
                captured_at=timestamp,
                latitude=start_point.latitude
                + (end_point.latitude - start_point.latitude) * fraction,
                longitude=start_point.longitude
                + (end_point.longitude - start_point.longitude) * fraction,
            )
        )
    return generated


def create_demo_exercise(
    db: Session, payload: DemoExerciseCreate, current_user: AppUser
) -> dict:
    if payload.end_time > datetime.now(timezone.utc) + timedelta(seconds=5):
        raise ValueError("Demo exercise cannot end in the future")

    generated_by_key = {
        participant.client_key: generate_route_points(participant)
        for participant in payload.participants
    }
    total_points = sum(len(points) for points in generated_by_key.values())
    if total_points > MAX_TOTAL_POINTS:
        raise ValueError(
            f"Demo exercise would create more than {MAX_TOTAL_POINTS} location points"
        )

    exercise = Exercise(
        name=payload.name.strip(),
        status=ExerciseStatus.COMPLETED,
        timezone=payload.timezone,
        is_demo=True,
        actual_start=payload.start_time,
        closing_started_at=payload.end_time,
        created_at=payload.start_time,
    )
    db.add(exercise)
    db.flush()
    db.add(ExerciseMember(exercise_id=exercise.id, user_id=current_user.id))

    participants_by_key: dict[str, tuple[Participant, DeviceSession]] = {}
    for participant_payload in payload.participants:
        participant = Participant(
            exercise_id=exercise.id,
            user_id=None,
            display_name=participant_payload.display_name.strip(),
            callsign=(participant_payload.callsign or "").strip() or None,
            role=participant_payload.role,
            tracking_mode="CONTINUOUS_GPS",
        )
        db.add(participant)
        db.flush()
        device_session = DeviceSession(
            exercise_id=exercise.id,
            participant_id=participant.id,
            device_id=f"demo-{uuid.uuid4()}",
            started_at=participant_payload.start_time,
            ended_at=participant_payload.end_time,
        )
        db.add(device_session)
        db.flush()
        participants_by_key[participant_payload.client_key] = (
            participant,
            device_session,
        )
        db.add_all(
            [
                LocationPoint(
                    exercise_id=exercise.id,
                    participant_id=participant.id,
                    device_session_id=device_session.id,
                    sequence_number=index,
                    captured_at=point.captured_at,
                    location=ST_SetSRID(
                        ST_MakePoint(point.longitude, point.latitude), 4326
                    ),
                    horizontal_accuracy=3.0,
                )
                for index, point in enumerate(
                    generated_by_key[participant_payload.client_key]
                )
            ]
        )

    for event_payload in payload.events:
        reporter = participants_by_key.get(
            event_payload.reporter_participant_key or ""
        )
        participant = reporter[0] if reporter else None
        device_session = reporter[1] if reporter else None
        db.add(
            ExerciseEvent(
                exercise_id=exercise.id,
                participant_id=participant.id if participant else None,
                device_session_id=device_session.id if device_session else None,
                occurred_at=event_payload.occurred_at,
                location=ST_SetSRID(
                    ST_MakePoint(event_payload.longitude, event_payload.latitude),
                    4326,
                ),
                reporter_name=(
                    participant.display_name if participant else current_user.email
                ),
                reporter_role=(participant.role if participant else "מנהל תרגיל"),
                description=event_payload.description.strip(),
            )
        )

    db.commit()
    return {
        "id": exercise.id,
        "name": exercise.name,
        "status": exercise.status,
        "isDemo": True,
        "createdAt": exercise.created_at,
        "actualStart": exercise.actual_start,
        "participantCount": len(payload.participants),
        "eventCount": len(payload.events),
        "pointCount": total_points,
    }
