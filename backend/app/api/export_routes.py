import json
import secrets
import uuid
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, Depends, Header, HTTPException, status
from fastapi.responses import FileResponse
from geoalchemy2.functions import ST_AsGeoJSON
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.auth import get_current_user
from app.db.session import get_db
from app.models.models import (
    AppUser,
    Exercise,
    ExerciseEvent,
    LocationPoint,
    Participant,
    VideoExportJob,
    VideoExportStatus,
)
from app.schemas.api import VideoExportCreate

router = APIRouter(prefix="/api/v1")
TRACK_COLORS = ["#2563eb", "#16a34a", "#9333ea", "#ea580c", "#0891b2", "#4d7c0f", "#ca8a04", "#475569"]
MAX_VIDEO_SECONDS = 3600


def _job_payload(job: VideoExportJob) -> dict:
    return {
        "id": job.id,
        "exerciseId": job.exercise_id,
        "status": job.status,
        "progress": job.progress,
        "fileName": job.file_name,
        "fileSize": job.file_size,
        "error": job.error_message,
        "expiresAt": job.expires_at,
        "createdAt": job.created_at,
        "downloadUrl": f"/api/v1/exports/{job.id}/download" if job.status == VideoExportStatus.READY else None,
    }


def _utc_timestamp(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    if value.tzinfo is None or value.utcoffset() is None:
        raise HTTPException(422, "Export time range must include a timezone")
    return value.astimezone(timezone.utc)


def _build_render_data(db: Session, exercise: Exercise, config: dict) -> dict:
    participant_ids = [uuid.UUID(str(value)) for value in config["participant_ids"]]
    participants = db.scalars(
        select(Participant)
        .where(Participant.exercise_id == exercise.id, Participant.id.in_(participant_ids))
        .order_by(Participant.display_name)
    ).all()
    start_time = datetime.fromisoformat(config["start_time"]) if config.get("start_time") else None
    end_time = datetime.fromisoformat(config["end_time"]) if config.get("end_time") else None

    tracks = []
    for index, participant in enumerate(participants):
        query = select(
            LocationPoint.captured_at,
            ST_AsGeoJSON(LocationPoint.location).label("geojson"),
        ).where(
            LocationPoint.exercise_id == exercise.id,
            LocationPoint.participant_id == participant.id,
        )
        if start_time:
            query = query.where(LocationPoint.captured_at >= start_time)
        if end_time:
            query = query.where(LocationPoint.captured_at <= end_time)
        rows = db.execute(query.order_by(LocationPoint.captured_at)).all()
        points = []
        for row in rows:
            longitude, latitude = json.loads(row.geojson)["coordinates"][:2]
            points.append({"timestamp": row.captured_at.isoformat(), "latitude": latitude, "longitude": longitude})
        if points:
            tracks.append(
                {
                    "participantId": str(participant.id),
                    "displayName": participant.display_name,
                    "color": TRACK_COLORS[index % len(TRACK_COLORS)],
                    "points": points,
                }
            )

    events = []
    if config.get("show_events"):
        query = select(
            ExerciseEvent.id,
            ExerciseEvent.occurred_at,
            ExerciseEvent.reporter_name,
            ExerciseEvent.reporter_role,
            ExerciseEvent.description,
            ST_AsGeoJSON(ExerciseEvent.location).label("geojson"),
        ).where(ExerciseEvent.exercise_id == exercise.id)
        if start_time:
            query = query.where(ExerciseEvent.occurred_at >= start_time)
        if end_time:
            query = query.where(ExerciseEvent.occurred_at <= end_time)
        for row in db.execute(query.order_by(ExerciseEvent.occurred_at)).all():
            longitude, latitude = json.loads(row.geojson)["coordinates"][:2]
            events.append(
                {
                    "id": str(row.id),
                    "timestamp": row.occurred_at.isoformat(),
                    "latitude": latitude,
                    "longitude": longitude,
                    "reporterName": row.reporter_name,
                    "reporterRole": row.reporter_role,
                    "description": row.description,
                }
            )
    return {
        "exercise": {"id": str(exercise.id), "name": exercise.name},
        "config": config,
        "tracks": tracks,
        "events": events,
    }


@router.post("/exercises/{exercise_id}/export-data")
def browser_video_export_data(
    exercise_id: uuid.UUID,
    payload: VideoExportCreate,
    _: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    exercise = db.get(Exercise, exercise_id)
    if not exercise:
        raise HTTPException(404, "Exercise not found")
    participant_ids = list(dict.fromkeys(payload.participant_ids))
    participant_count = db.scalar(
        select(func.count(Participant.id)).where(
            Participant.exercise_id == exercise_id,
            Participant.id.in_(participant_ids),
        )
    ) or 0
    if participant_count != len(participant_ids):
        raise HTTPException(422, "One or more participants do not belong to this exercise")
    config = payload.model_dump(mode="json")
    config["participant_ids"] = [str(value) for value in participant_ids]
    return _build_render_data(db, exercise, config)


@router.post("/exercises/{exercise_id}/exports", status_code=status.HTTP_202_ACCEPTED)
def create_video_export(
    exercise_id: uuid.UUID,
    payload: VideoExportCreate,
    current_user: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    raise HTTPException(
        status_code=status.HTTP_410_GONE,
        detail="Server-side video export is disabled; refresh the page to use local browser export",
    )


def _legacy_create_video_export(
    exercise_id: uuid.UUID,
    payload: VideoExportCreate,
    current_user: AppUser,
    db: Session,
):
    exercise = db.get(Exercise, exercise_id)
    if not exercise:
        raise HTTPException(404, "Exercise not found")

    participant_ids = list(dict.fromkeys(payload.participant_ids))
    participants = db.scalars(
        select(Participant).where(
            Participant.exercise_id == exercise_id,
            Participant.id.in_(participant_ids),
        )
    ).all()
    if len(participants) != len(participant_ids):
        raise HTTPException(422, "One or more participants do not belong to this exercise")

    start_time = _utc_timestamp(payload.start_time)
    end_time = _utc_timestamp(payload.end_time)
    if start_time and end_time and start_time >= end_time:
        raise HTTPException(422, "Export end time must be later than start time")

    point_query = select(func.count(LocationPoint.id)).where(
        LocationPoint.exercise_id == exercise_id,
        LocationPoint.participant_id.in_(participant_ids),
    )
    if start_time:
        point_query = point_query.where(LocationPoint.captured_at >= start_time)
    if end_time:
        point_query = point_query.where(LocationPoint.captured_at <= end_time)
    point_count = db.scalar(point_query) or 0
    if point_count == 0:
        raise HTTPException(422, "The selected participants have no points in the requested time range")

    event_count = 0
    if payload.show_events:
        event_query = select(func.count(ExerciseEvent.id)).where(ExerciseEvent.exercise_id == exercise_id)
        if start_time:
            event_query = event_query.where(ExerciseEvent.occurred_at >= start_time)
        if end_time:
            event_query = event_query.where(ExerciseEvent.occurred_at <= end_time)
        event_count = db.scalar(event_query) or 0
    estimated_seconds = (point_count + event_count) / payload.points_per_second
    if estimated_seconds > MAX_VIDEO_SECONDS:
        raise HTTPException(422, "The requested video is longer than one hour; increase the playback speed or shorten the range")

    config = payload.model_dump(mode="json")
    config["participant_ids"] = [str(item) for item in participant_ids]
    job = VideoExportJob(
        exercise_id=exercise_id,
        requested_by=current_user.id,
        config=config,
        render_token=secrets.token_urlsafe(32),
    )
    db.add(job)
    db.commit()
    db.refresh(job)

    from app.services.video_export import enqueue_video_export

    enqueue_video_export(job.id)
    return _job_payload(job)


@router.get("/exports/{job_id}")
def get_video_export(
    job_id: uuid.UUID,
    _: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    job = db.get(VideoExportJob, job_id)
    if not job:
        raise HTTPException(404, "Video export not found")
    return _job_payload(job)


@router.get("/exercises/{exercise_id}/exports")
def list_video_exports(
    exercise_id: uuid.UUID,
    _: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if not db.get(Exercise, exercise_id):
        raise HTTPException(404, "Exercise not found")
    jobs = db.scalars(
        select(VideoExportJob)
        .where(VideoExportJob.exercise_id == exercise_id)
        .order_by(VideoExportJob.created_at.desc())
        .limit(10)
    ).all()
    return {"items": [_job_payload(job) for job in jobs]}


@router.get("/exports/{job_id}/download")
def download_video_export(
    job_id: uuid.UUID,
    _: AppUser = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    job = db.get(VideoExportJob, job_id)
    if not job:
        raise HTTPException(404, "Video export not found")
    if job.status != VideoExportStatus.READY or not job.output_path:
        raise HTTPException(409, "Video export is not ready")
    if job.expires_at and job.expires_at <= datetime.now(timezone.utc):
        raise HTTPException(410, "Video export has expired")
    path = Path(job.output_path)
    if not path.is_file():
        raise HTTPException(410, "Video export file is no longer available")
    return FileResponse(path, media_type="video/mp4", filename=job.file_name or "ReTrace-export.mp4")


@router.get("/exports/{job_id}/render-data")
def video_export_render_data(
    job_id: uuid.UUID,
    x_export_token: str = Header(min_length=20),
    db: Session = Depends(get_db),
):
    job = db.get(VideoExportJob, job_id)
    if not job or not secrets.compare_digest(job.render_token, x_export_token):
        raise HTTPException(404, "Video export not found")
    if job.status != VideoExportStatus.PROCESSING:
        raise HTTPException(409, "Video export is not being rendered")
    exercise = db.get(Exercise, job.exercise_id)
    if not exercise:
        raise HTTPException(404, "Exercise not found")

    return _build_render_data(db, exercise, job.config)
