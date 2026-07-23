from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import FileResponse

from app.api.routes import router
from app.db.session import Base, engine
from app.models import models  # noqa: F401

app = FastAPI(title="Exercise Platform Prototype", version="0.2.0")


@app.on_event("startup")
def startup() -> None:
    Base.metadata.create_all(bind=engine)


app.include_router(router)


@app.get("/", include_in_schema=False)
def prototype_web() -> FileResponse:
    return FileResponse(Path(__file__).parent / "static" / "index.html")
