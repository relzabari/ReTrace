from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import FileResponse
from sqlalchemy import text

from app.api.auth_routes import router as auth_router
from app.api.routes import router
from app.db.session import Base, engine
from app.models import models  # noqa: F401

app = FastAPI(title="Exercise Platform Prototype", version="0.2.0")


@app.on_event("startup")
def startup() -> None:
    Base.metadata.create_all(bind=engine)
    # Lightweight migration for installations created before participant roles
    # were introduced. New installations already receive this column via ORM.
    with engine.begin() as connection:
        connection.execute(
            text(
                """
                ALTER TABLE exercise_participants
                ADD COLUMN IF NOT EXISTS role VARCHAR(40)
                NOT NULL DEFAULT 'כיתת כוננות'
                """
            )
        )


app.include_router(router)
app.include_router(auth_router)


@app.get("/", include_in_schema=False)
def prototype_web() -> FileResponse:
    return FileResponse(Path(__file__).parent / "static" / "index.html")
