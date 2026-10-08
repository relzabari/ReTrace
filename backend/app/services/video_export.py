import os
import re
import shutil
import subprocess
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from pathlib import Path

from sqlalchemy import select

from app.core.config import settings
from app.db.session import SessionLocal
from app.models.models import Exercise, VideoExportJob, VideoExportStatus

_executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="video-export")


def enqueue_video_export(job_id: uuid.UUID) -> None:
    _executor.submit(_render_video_export, job_id)


def recover_video_exports() -> None:
    output_dir = Path(settings.video_export_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    with SessionLocal() as db:
        now = datetime.now(timezone.utc)
        expired = db.scalars(
            select(VideoExportJob).where(
                VideoExportJob.expires_at.is_not(None),
                VideoExportJob.expires_at <= now,
            )
        ).all()
        for job in expired:
            if job.output_path:
                Path(job.output_path).unlink(missing_ok=True)
            shutil.rmtree(output_dir / str(job.id), ignore_errors=True)
            db.delete(job)
        ready = db.scalars(
            select(VideoExportJob).where(VideoExportJob.status == VideoExportStatus.READY)
        ).all()
        for job in ready:
            if not job.output_path or not Path(job.output_path).is_file():
                job.status = VideoExportStatus.FAILED
                job.error_message = "The exported video file is no longer available"
                job.output_path = None
                job.file_size = None
        interrupted = db.scalars(
            select(VideoExportJob).where(VideoExportJob.status == VideoExportStatus.PROCESSING)
        ).all()
        for job in interrupted:
            job.status = VideoExportStatus.FAILED
            job.error_message = "Video rendering was interrupted because the server restarted"
            job.progress = 0
        queued = db.scalars(
            select(VideoExportJob).where(VideoExportJob.status == VideoExportStatus.QUEUED)
        ).all()
        pending_ids = [job.id for job in queued]
        db.commit()
    for job_id in pending_ids:
        enqueue_video_export(job_id)


def _update_job(job_id: uuid.UUID, **values) -> None:
    with SessionLocal() as db:
        job = db.get(VideoExportJob, job_id)
        if not job:
            return
        for key, value in values.items():
            setattr(job, key, value)
        db.commit()


def _safe_file_stem(value: str) -> str:
    normalized = re.sub(r"[^\w\-]+", "-", value.strip(), flags=re.UNICODE).strip("-")
    return normalized[:80] or "exercise"


def _render_video_export(job_id: uuid.UUID) -> None:
    work_dir: Path | None = None
    try:
        _update_job(job_id, status=VideoExportStatus.PROCESSING, progress=1, error_message=None)
        with SessionLocal() as db:
            job = db.get(VideoExportJob, job_id)
            if not job:
                return
            exercise = db.get(Exercise, job.exercise_id)
            if not exercise:
                raise RuntimeError("Exercise no longer exists")
            token = job.render_token
            quality = job.config.get("quality", "720p")
            exercise_name = exercise.name

        width, height = (1920, 1080) if quality == "1080p" else (1280, 720)
        crf = "23" if quality == "1080p" else "25"
        output_dir = Path(settings.video_export_dir)
        work_dir = output_dir / str(job_id)
        video_dir = work_dir / "browser"
        work_dir.mkdir(parents=True, exist_ok=True)
        video_dir.mkdir(parents=True, exist_ok=True)
        output_path = output_dir / f"{job_id}.mp4"
        internal_base_url = f"http://127.0.0.1:{os.getenv('PORT', '8000')}"
        render_url = (
            f"{internal_base_url.rstrip('/')}/video-render/{job_id}"
            f"#token={token}"
        )

        from playwright.sync_api import sync_playwright

        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(
                executable_path=settings.chromium_executable,
                headless=True,
                args=[
                    "--no-sandbox",
                    "--disable-dev-shm-usage",
                    "--disable-gpu",
                    "--disable-extensions",
                    "--disable-background-networking",
                    "--renderer-process-limit=1",
                    "--no-zygote",
                    "--js-flags=--max-old-space-size=192",
                ],
            )
            context = browser.new_context(
                viewport={"width": width, "height": height},
                record_video_dir=str(video_dir),
                record_video_size={"width": width, "height": height},
                locale="he-IL",
                timezone_id="Asia/Jerusalem",
            )
            page = context.new_page()
            page.goto(render_url, wait_until="networkidle", timeout=120_000)
            page.wait_for_function("window.exportReady === true || Boolean(window.exportFailure)", timeout=120_000)
            render_failure = page.evaluate("window.exportFailure || null")
            if render_failure:
                raise RuntimeError(f"Render page failed: {render_failure}")
            start_offset = float(page.evaluate("performance.now() / 1000"))
            duration = float(page.evaluate("window.exportDurationSeconds"))
            page.evaluate("window.startExportPlayback()")
            while not page.evaluate("window.exportComplete === true"):
                progress = int(page.evaluate("Math.round(window.exportProgress || 0)"))
                _update_job(job_id, progress=max(2, min(94, progress)))
                time.sleep(0.75)
            time.sleep(0.5)
            recorded_video = page.video
            page.close()
            context.close()
            browser.close()
            webm_path = Path(recorded_video.path())

        _update_job(job_id, progress=96)
        command = [
            "ffmpeg",
            "-y",
            "-ss",
            f"{max(0.0, start_offset - 0.15):.3f}",
            "-i",
            str(webm_path),
            "-t",
            f"{duration + 0.5:.3f}",
            "-an",
            "-c:v",
            "libx264",
            "-preset",
            "medium",
            "-crf",
            crf,
            "-pix_fmt",
            "yuv420p",
            "-movflags",
            "+faststart",
            str(output_path),
        ]
        result = subprocess.run(command, capture_output=True, text=True, timeout=3600)
        if result.returncode != 0:
            raise RuntimeError(f"FFmpeg failed: {result.stderr[-1500:]}")
        file_name = f"ReTrace-{_safe_file_stem(exercise_name)}.mp4"
        _update_job(
            job_id,
            status=VideoExportStatus.READY,
            progress=100,
            file_name=file_name,
            output_path=str(output_path),
            file_size=output_path.stat().st_size,
            expires_at=datetime.now(timezone.utc) + timedelta(hours=settings.video_export_retention_hours),
        )
        shutil.rmtree(work_dir, ignore_errors=True)
    except Exception as error:
        if work_dir is not None:
            shutil.rmtree(work_dir, ignore_errors=True)
        _update_job(
            job_id,
            status=VideoExportStatus.FAILED,
            error_message=str(error)[:4000],
        )
