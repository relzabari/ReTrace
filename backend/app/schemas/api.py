import uuid
from datetime import datetime
from pydantic import BaseModel, Field


class ExerciseCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    timezone: str = "Asia/Jerusalem"


class ParticipantCreate(BaseModel):
    display_name: str
    callsign: str | None = None
    tracking_mode: str = "CONTINUOUS_GPS"


class DeviceSessionCreate(BaseModel):
    participant_id: uuid.UUID
    device_id: str
    clock_offset_ms: int = 0


class LocationInput(BaseModel):
    sequence: int = Field(ge=0)
    captured_at: datetime
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    horizontal_accuracy: float | None = Field(default=None, ge=0)
    speed: float | None = None
    heading: float | None = None
    battery_level: int | None = Field(default=None, ge=0, le=100)


class LocationBatch(BaseModel):
    device_session_id: uuid.UUID
    points: list[LocationInput] = Field(min_length=1, max_length=500)
