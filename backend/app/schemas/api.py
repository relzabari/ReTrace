import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

ParticipantRole = Literal["רבשץ", "כיתת כוננות", "חמל", "מנהל תרגיל"]
AppUserRole = Literal["ADMIN", "MANAGER", "USER"]


class LoginRequest(BaseModel):
    email: str = Field(min_length=3, max_length=320)
    password: str = Field(min_length=6, max_length=200)


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=10)


class UserCreate(BaseModel):
    email: str = Field(min_length=3, max_length=320)
    password: str = Field(min_length=8, max_length=200)
    role: AppUserRole = "USER"


class UserRoleUpdate(BaseModel):
    role: AppUserRole


class ExerciseUpdate(BaseModel):
    name: str = Field(min_length=1, max_length=200)


class ExerciseCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    timezone: str = "Asia/Jerusalem"


class ParticipantCreate(BaseModel):
    display_name: str
    callsign: str | None = None
    role: ParticipantRole = "כיתת כוננות"
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


class EventCreate(BaseModel):
    device_session_id: uuid.UUID
    occurred_at: datetime
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    description: str = Field(min_length=1, max_length=4000)


class WebEventCreate(BaseModel):
    occurred_at: datetime
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    description: str = Field(min_length=1, max_length=4000)
