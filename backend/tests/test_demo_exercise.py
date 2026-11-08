from datetime import datetime, timedelta, timezone
import uuid

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api import routes
from app.core.auth import get_current_user
from app.db.session import get_db
from app.models.models import AppUser, UserRole
from app.schemas.api import DemoParticipantCreate, DemoRoutePoint
from app.services.demo_exercise import generate_route_points


def test_route_generation_keeps_endpoints_and_interval():
    start = datetime(2026, 11, 8, 8, 0, tzinfo=timezone.utc)
    participant = DemoParticipantCreate(
        client_key="alpha",
        display_name="Alpha",
        start_time=start,
        end_time=start + timedelta(seconds=25),
        interval_seconds=10,
        route=[
            DemoRoutePoint(latitude=31.95, longitude=35.13),
            DemoRoutePoint(latitude=31.96, longitude=35.14),
        ],
    )

    points = generate_route_points(participant)

    assert [point.captured_at for point in points] == [
        start,
        start + timedelta(seconds=10),
        start + timedelta(seconds=20),
        start + timedelta(seconds=25),
    ]
    assert points[0].latitude == 31.95
    assert points[-1].latitude == 31.96
    assert points[-1].longitude == 35.14


def _payload():
    return {
        "name": "Demo",
        "start_time": "2026-11-08T08:00:00Z",
        "end_time": "2026-11-08T08:10:00Z",
        "participants": [
            {
                "client_key": "alpha",
                "display_name": "Alpha",
                "role": "כיתת כוננות",
                "start_time": "2026-11-08T08:00:00Z",
                "end_time": "2026-11-08T08:10:00Z",
                "interval_seconds": 10,
                "route": [
                    {"latitude": 31.95, "longitude": 35.13},
                    {"latitude": 31.96, "longitude": 35.14},
                ],
            }
        ],
        "events": [],
    }


def test_demo_endpoint_is_admin_only(monkeypatch):
    app = FastAPI()
    app.include_router(routes.router)
    user = AppUser(
        id=uuid.uuid4(), email="user@example.com", role=UserRole.USER, is_active=True
    )
    app.dependency_overrides[get_current_user] = lambda: user
    app.dependency_overrides[get_db] = lambda: object()
    monkeypatch.setattr(routes, "create_demo_exercise", lambda *_: {"id": "demo"})

    response = TestClient(app).post("/api/v1/demo-exercises", json=_payload())

    assert response.status_code == 403


def test_admin_can_submit_complete_demo(monkeypatch):
    app = FastAPI()
    app.include_router(routes.router)
    admin = AppUser(
        id=uuid.uuid4(), email="admin@example.com", role=UserRole.ADMIN, is_active=True
    )
    app.dependency_overrides[get_current_user] = lambda: admin
    app.dependency_overrides[get_db] = lambda: object()
    monkeypatch.setattr(
        routes,
        "create_demo_exercise",
        lambda _db, payload, _user: {
            "id": "demo",
            "participantCount": len(payload.participants),
        },
    )

    response = TestClient(app).post("/api/v1/demo-exercises", json=_payload())

    assert response.status_code == 201
    assert response.json() == {"id": "demo", "participantCount": 1}
