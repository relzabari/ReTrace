import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, model_validator

ParticipantRole = Literal["רבשץ", "כיתת כוננות", "חמל", "מנהל תרגיל"]
AppUserRole = Literal["ADMIN", "MANAGER", "USER"]


def _is_aware(value: datetime) -> bool:
    return value.tzinfo is not None and value.utcoffset() is not None


class LoginRequest(BaseModel):
    email: str = Field(min_length=3, max_length=320)
    password: str = Field(min_length=6, max_length=200)


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=10)


class PasswordResetRequest(BaseModel):
    email: str = Field(min_length=3, max_length=320)


class PasswordResetConfirm(BaseModel):
    access_token: str = Field(min_length=20)
    password: str = Field(min_length=8, max_length=200)


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


class ExerciseAccessGrant(BaseModel):
    email: str = Field(min_length=3, max_length=320)
    participant_id: uuid.UUID | None = None


class DemoRoutePoint(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    occurred_at: datetime | None = None


class DemoParticipantCreate(BaseModel):
    client_key: str = Field(min_length=1, max_length=80)
    display_name: str = Field(min_length=1, max_length=120)
    callsign: str | None = Field(default=None, max_length=120)
    role: ParticipantRole = "כיתת כוננות"
    start_time: datetime
    end_time: datetime
    interval_seconds: int = Field(default=10, ge=1, le=300)
    route: list[DemoRoutePoint] = Field(min_length=2, max_length=500)

    @model_validator(mode="after")
    def validate_times(self):
        if not _is_aware(self.start_time) or not _is_aware(self.end_time):
            raise ValueError("Participant times must include a timezone")
        if self.end_time <= self.start_time:
            raise ValueError("Participant end time must be later than start time")
        timed = [point.occurred_at is not None for point in self.route]
        if any(timed) and not all(timed):
            raise ValueError("Either all route points need times or none of them")
        if all(timed):
            times = [point.occurred_at for point in self.route]
            if any(not _is_aware(value) for value in times):
                raise ValueError("Route point times must include a timezone")
            if times != sorted(times):
                raise ValueError("Route point times must be ordered")
            if times[0] < self.start_time or times[-1] > self.end_time:
                raise ValueError("Route point times must be inside participant time range")
        return self


class DemoEventCreate(BaseModel):
    description: str = Field(min_length=1, max_length=4000)
    occurred_at: datetime
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    reporter_participant_key: str | None = Field(default=None, max_length=80)


class DemoExerciseCreate(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    timezone: str = Field(default="Asia/Jerusalem", min_length=1, max_length=64)
    start_time: datetime
    end_time: datetime
    participants: list[DemoParticipantCreate] = Field(min_length=1, max_length=100)
    events: list[DemoEventCreate] = Field(default_factory=list, max_length=500)

    @model_validator(mode="after")
    def validate_exercise(self):
        if not _is_aware(self.start_time) or not _is_aware(self.end_time):
            raise ValueError("Exercise times must include a timezone")
        if self.end_time <= self.start_time:
            raise ValueError("Exercise end time must be later than start time")
        keys = [participant.client_key for participant in self.participants]
        if len(keys) != len(set(keys)):
            raise ValueError("Participant client keys must be unique")
        known_keys = set(keys)
        for participant in self.participants:
            if participant.start_time < self.start_time or participant.end_time > self.end_time:
                raise ValueError("Participant times must be inside exercise time range")
        for event in self.events:
            if not _is_aware(event.occurred_at):
                raise ValueError("Event times must include a timezone")
            if event.occurred_at < self.start_time or event.occurred_at > self.end_time:
                raise ValueError("Event times must be inside exercise time range")
            if event.reporter_participant_key and event.reporter_participant_key not in known_keys:
                raise ValueError("Unknown event reporter participant key")
        return self


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


class VideoExportCreate(BaseModel):
    participant_ids: list[uuid.UUID] = Field(min_length=1, max_length=100)
    map_style: Literal["map", "satellite", "hybrid"] = "map"
    show_events: bool = True
    trail_enabled: bool = False
    trail_length: Literal[10, 30, 50, 100] = 30
    show_participant_names: bool = False
    points_per_second: int = Field(default=10, ge=1, le=100)
    quality: Literal["720p", "1080p"] = "720p"
    start_time: datetime | None = None
    end_time: datetime | None = None
    show_header: bool = True
