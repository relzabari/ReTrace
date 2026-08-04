from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    database_url: str = "postgresql+psycopg://exercise:exercise@localhost:5432/exercise"
    supabase_url: str = ""
    supabase_publishable_key: str = ""
    supabase_secret_key: str = ""
    initial_admin_email: str = ""
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


settings = Settings()
