from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    database_url: str = "postgresql+psycopg://exercise:exercise@localhost:5432/exercise"
    supabase_url: str = ""
    supabase_publishable_key: str = ""
    supabase_secret_key: str = ""
    initial_admin_email: str = ""
    password_reset_redirect_url: str = "https://retrace-exercise-platform.onrender.com/"
    video_export_dir: str = "/tmp/retrace-video-exports"
    video_export_retention_hours: int = 48
    chromium_executable: str = "/usr/bin/chromium"
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
