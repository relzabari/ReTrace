"""HTTP authorization regressions using SQLite; spatial functions are stubbed.

Run: PYTHONPATH=backend pytest backend/tests/test_access.py
These tests do not validate PostGIS or the PostgreSQL startup migration.
"""

import json
import uuid
from datetime import datetime, timezone

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from geoalchemy2 import Geography
from sqlalchemy import create_engine, event, text
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateTable
from sqlalchemy.pool import StaticPool

from app.api import routes, export_routes
from app.core.auth import get_current_user
from app.db.session import Base, get_db
from app.models.models import (
    AppUser,
    DeviceSession,
    Exercise,
    ExerciseEvent,
    ExerciseMember,
    ExerciseStatus,
    Participant,
    UserRole,
    VideoExportJob,
    VideoExportStatus,
)


@compiles(Geography, "sqlite")
def sqlite_geography(type_, compiler, **kw):
    return "TEXT"


@pytest.fixture
def env():
    engine = create_engine(
        "sqlite://", poolclass=StaticPool, connect_args={"check_same_thread": False}
    )

    @event.listens_for(engine, "connect")
    def spatial_stubs(connection, _):
        connection.execute("PRAGMA foreign_keys=ON")
        connection.create_function("AsGeoJSON", 1, lambda value: value)

    # Raw DDL skips GeoAlchemy's spatial extension initialization hooks.
    with engine.begin() as connection:
        for table in Base.metadata.sorted_tables:
            connection.execute(CreateTable(table))
    db = Session(engine, expire_on_commit=False)
    users = {
        name: AppUser(
            id=uuid.uuid4(), email=name + "@example.com", role=role, is_active=True
        )
        for name, role in [
            ("alice", UserRole.USER),
            ("bob", UserRole.USER),
            ("manager", UserRole.MANAGER),
            ("outsider", UserRole.MANAGER),
            ("admin", UserRole.ADMIN),
        ]
    }
    db.add_all(users.values())
    db.flush()
    exercises = [
        Exercise(id=uuid.uuid4(), name=name, status=ExerciseStatus.ACTIVE)
        for name in ["assigned", "other", "legacy"]
    ]
    db.add_all(exercises)
    db.flush()
    for name in ["alice", "bob", "manager"]:
        db.add(ExerciseMember(exercise_id=exercises[0].id, user_id=users[name].id))
    db.add(ExerciseMember(exercise_id=exercises[1].id, user_id=users["outsider"].id))
    participants = {
        name: Participant(
            id=uuid.uuid4(),
            exercise_id=exercises[0].id,
            user_id=users[name].id if name in users else None,
            display_name=name,
            role="כיתת כוננות",
        )
        for name in ["alice", "bob", "legacy"]
    }
    db.add_all(participants.values())
    db.flush()
    sessions = {
        name: DeviceSession(
            id=uuid.uuid4(),
            exercise_id=exercises[0].id,
            participant_id=p.id,
            device_id=name,
        )
        for name, p in participants.items()
    }
    db.add_all(sessions.values())
    db.flush()
    for index, (name, p) in enumerate(participants.items()):
        params = {
            "e": exercises[0].id.hex,
            "p": p.id.hex,
            "s": sessions[name].id.hex,
            "geo": json.dumps({"type": "Point", "coordinates": [35 + index, 32]}),
            "name": name,
            "point_id": index + 1,
        }
        db.execute(
            text(
                "INSERT INTO location_points (id,exercise_id,participant_id,device_session_id,sequence_number,captured_at,location) VALUES (:point_id,:e,:p,:s,1,'2026-10-14 10:00:00',:geo)"
            ),
            params,
        )
        db.execute(
            text(
                "INSERT INTO exercise_events (id,exercise_id,participant_id,device_session_id,occurred_at,location,reporter_name,reporter_role,description) VALUES (:p,:e,:p,:s,'2026-10-14 10:00:00',:geo,:name,'כיתת כוננות',:name)"
            ),
            params,
        )
    db.execute(
        text(
            "INSERT INTO exercise_events (id,exercise_id,occurred_at,location,reporter_name,reporter_role,description) VALUES (:id,:e,'2026-10-14 10:00:00',:geo,'manager@example.com','MANAGER','command room')"
        ),
        {
            "id": uuid.uuid4().hex,
            "e": exercises[0].id.hex,
            "geo": json.dumps({"type": "Point", "coordinates": [35, 32]}),
        },
    )
    job = VideoExportJob(
        id=uuid.uuid4(),
        exercise_id=exercises[0].id,
        requested_by=users["alice"].id,
        config={},
        render_token="x" * 40,
        status=VideoExportStatus.READY,
    )
    db.add(job)
    db.commit()
    app = FastAPI()
    app.include_router(routes.router)
    app.include_router(export_routes.router)
    active = {"user": users["alice"]}
    app.dependency_overrides[get_current_user] = lambda: active["user"]
    app.dependency_overrides[get_db] = lambda: db
    with TestClient(app) as client:
        yield client, db, active, users, exercises, participants, sessions, job
    db.close()
    engine.dispose()


def test_lists_and_tracks_only_own_data(env):
    client, _, _, _, exercises, p, _, _ = env
    e = str(exercises[0].id)
    assert [x["id"] for x in client.get("/api/v1/exercises").json()["items"]] == [e]
    assert [
        x["displayName"]
        for x in client.get(f"/api/v1/exercises/{e}/participants").json()["items"]
    ] == ["alice"]
    bootstrap = client.get(f"/api/v1/exercises/{e}/map-bootstrap").json()
    assert (
        len(bootstrap["participants"]) == 1
        and bootstrap["participants"][0]["pointCount"] == 1
    )
    assert (
        client.get(f'/api/v1/exercises/{e}/tracks/{p["alice"].id}').json()["count"] == 1
    )
    for name in ["bob", "legacy"]:
        assert (
            client.get(f"/api/v1/exercises/{e}/tracks/{p[name].id}").status_code == 404
        )
    assert [
        x["description"]
        for x in client.get(f"/api/v1/exercises/{e}/events").json()["items"]
    ] == ["alice"]


@pytest.mark.parametrize(
    "suffix", ["", "/participants", "/events", "/map-bootstrap", "/exports", "/access"]
)
def test_foreign_exercise_is_hidden(env, suffix):
    client, _, _, _, exercises, *_ = env
    assert client.get(f"/api/v1/exercises/{exercises[1].id}{suffix}").status_code in [
        403,
        404,
    ]


def test_identity_cannot_be_chosen_by_request(env):
    client, db, _, users, exercises, p, _, _ = env
    e = str(exercises[0].id)
    created = client.post(
        f"/api/v1/exercises/{e}/participants",
        json={"display_name": "new", "user_id": str(users["bob"].id)},
    )
    assert created.status_code == 201
    assert (
        db.get(Participant, uuid.UUID(created.json()["id"])).user_id
        == users["alice"].id
    )
    for name in ["bob", "legacy"]:
        assert (
            client.post(
                f"/api/v1/exercises/{e}/device-sessions",
                json={"participant_id": str(p[name].id), "device_id": "test"},
            ).status_code
            == 404
        )
    assert (
        client.post(
            f"/api/v1/exercises/{e}/device-sessions",
            json={"participant_id": str(p["alice"].id), "device_id": "test"},
        ).status_code
        == 201
    )


@pytest.mark.parametrize("action", ["locations/batch", "events"])
def test_cannot_write_another_session(env, action):
    client, _, _, _, exercises, _, sessions, _ = env
    e = str(exercises[0].id)
    body = {"device_session_id": str(sessions["bob"].id)}
    if action == "locations/batch":
        body["points"] = [
            {
                "sequence": 2,
                "captured_at": datetime.now(timezone.utc).isoformat(),
                "latitude": 32,
                "longitude": 35,
            }
        ]
    else:
        body.update(
            occurred_at=datetime.now(timezone.utc).isoformat(),
            latitude=32,
            longitude=35,
            description="spoof",
        )
    assert client.post(f"/api/v1/exercises/{e}/{action}", json=body).status_code == 404


def test_scoped_export_including_events(env):
    client, _, _, _, exercises, p, _, _ = env
    e = str(exercises[0].id)
    response = client.post(
        f"/api/v1/exercises/{e}/export-data",
        json={"participant_ids": [str(p["alice"].id)]},
    )
    assert response.status_code == 200, response.text
    assert [x["displayName"] for x in response.json()["tracks"]] == ["alice"]
    assert [x["description"] for x in response.json()["events"]] == ["alice"]
    assert (
        client.post(
            f"/api/v1/exercises/{e}/export-data",
            json={"participant_ids": [str(p["alice"].id), str(p["bob"].id)]},
        ).status_code
        == 404
    )


@pytest.mark.parametrize("suffix", ["", "/download"])
def test_old_video_cannot_bypass_scopes_even_for_requester(env, suffix):
    client, _, _, _, _, _, _, job = env
    assert client.get(f"/api/v1/exports/{job.id}{suffix}").status_code == 403


def test_manager_scoped_and_admin_recovers_legacy(env):
    client, _, active, users, exercises, p, _, _ = env
    e = str(exercises[0].id)
    active["user"] = users["manager"]
    assert len(client.get(f"/api/v1/exercises/{e}/participants").json()["items"]) == 3
    assert len(client.get(f"/api/v1/exercises/{e}/events").json()["items"]) == 4
    assert client.get(f"/api/v1/exercises/{exercises[1].id}").status_code == 404
    assert client.post(f"/api/v1/exercises/{exercises[1].id}/close").status_code == 404
    # Read permission never confers the right to report under another identity.
    assert (
        client.post(
            f"/api/v1/exercises/{e}/device-sessions",
            json={"participant_id": str(p["bob"].id), "device_id": "x"},
        ).status_code
        == 404
    )
    active["user"] = users["admin"]
    assert len(client.get("/api/v1/exercises").json()["items"]) == 3
    assert client.get(f"/api/v1/exercises/{exercises[2].id}").status_code == 200


def test_grant_revoke_and_legacy_assignment(env):
    client, db, active, users, exercises, p, _, _ = env
    e = str(exercises[0].id)
    payload = {"email": users["outsider"].email, "participant_id": str(p["legacy"].id)}
    assert client.post(f"/api/v1/exercises/{e}/access", json=payload).status_code == 403
    active["user"] = users["manager"]
    assert client.post(f"/api/v1/exercises/{e}/access", json=payload).status_code == 200
    assert db.get(Participant, p["legacy"].id).user_id == users["outsider"].id
    # Cannot silently reassign an already-owned participant.
    assert (
        client.post(
            f"/api/v1/exercises/{e}/access",
            json={"email": users["alice"].email, "participant_id": str(p["legacy"].id)},
        ).status_code
        == 409
    )
    active["user"] = users["outsider"]
    assert client.get(f"/api/v1/exercises/{e}").status_code == 200
    active["user"] = users["manager"]
    assert (
        client.delete(
            f'/api/v1/exercises/{e}/access/{users["outsider"].id}'
        ).status_code
        == 204
    )
    active["user"] = users["outsider"]
    assert client.get(f"/api/v1/exercises/{e}").status_code == 404
    assert (
        client.get(f'/api/v1/exercises/{e}/tracks/{p["legacy"].id}').status_code == 404
    )


def test_creator_gets_exercise_access(env):
    client, db, active, users, *_ = env
    active["user"] = users["manager"]
    response = client.post("/api/v1/exercises", json={"name": "new"})
    assert response.status_code == 201, response.text
    e = uuid.UUID(response.json()["id"])
    assert db.get(ExerciseMember, (e, users["manager"].id)) is not None
    active["user"] = users["outsider"]
    assert client.get(f"/api/v1/exercises/{e}").status_code == 404


def test_finish_requires_session_owner(env):
    client, db, active, users, exercises, _, sessions, _ = env
    exercise = exercises[0]
    exercise.status = ExerciseStatus.ENDING
    exercise.closing_started_at = datetime.now(timezone.utc)
    db.commit()
    foreign = (
        f'/api/v1/exercises/{exercise.id}/device-sessions/{sessions["bob"].id}/finish'
    )
    assert client.post(foreign).status_code == 404
    own = (
        f'/api/v1/exercises/{exercise.id}/device-sessions/{sessions["alice"].id}/finish'
    )
    assert client.post(own).status_code == 200
    assert db.get(DeviceSession, sessions["bob"].id).ended_at is None


def test_user_cannot_self_enroll_or_manage(env):
    client, _, _, _, exercises, _, _, _ = env
    assert (
        client.post(
            f"/api/v1/exercises/{exercises[1].id}/participants",
            json={"display_name": "intruder"},
        ).status_code
        == 404
    )
    assert client.post(f"/api/v1/exercises/{exercises[0].id}/close").status_code == 403


def test_anonymous_requests_still_require_login(env):
    client, _, _, _, exercises, _, _, _ = env
    del client.app.dependency_overrides[get_current_user]
    assert client.get("/api/v1/exercises").status_code == 401
    assert client.get(f"/api/v1/exercises/{exercises[0].id}/events").status_code == 401
