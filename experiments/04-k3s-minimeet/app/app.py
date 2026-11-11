"""Reference MiniMeet API for the reproducible CRIU lab.

Uses the stdlib asyncio loop: uvloop may create io_uring mappings that CRIU
cannot dump on some kernel/runtime combinations. All database/Redis handles are
short-lived so quiescence leaves no open external service connections.
"""
import os
import threading
import time
from pathlib import Path
from contextlib import closing

import psycopg2
import redis
from fastapi import FastAPI
from fastapi.responses import JSONResponse
from pydantic import BaseModel

DATABASE_URL = os.environ["DATABASE_URL"]
REDIS_URL = os.environ["REDIS_URL"]
SHARED = Path("/shared")
PAUSE = SHARED / "minimeet.pause"
STATUS = SHARED / "backend.quiesce.status"

app = FastAPI(title="MiniMeet CRIU Demo")
_lock = threading.Lock()
_in_flight = 0


def _db():
    return psycopg2.connect(DATABASE_URL, connect_timeout=3)


def _redis():
    return redis.Redis.from_url(
        REDIS_URL, socket_connect_timeout=3, socket_timeout=5
    )


def _watch_pause():
    while True:
        with _lock:
            idle = _in_flight == 0
        if PAUSE.exists() and idle:
            STATUS.write_text("PAUSED\n")
        elif not PAUSE.exists() and STATUS.exists():
            STATUS.unlink()
        time.sleep(0.25)


@app.on_event("startup")
def start_watcher():
    SHARED.mkdir(parents=True, exist_ok=True)
    threading.Thread(target=_watch_pause, daemon=True).start()


@app.middleware("http")
async def quiescence_guard(request, call_next):
    global _in_flight
    with _lock:
        if PAUSE.exists():
            return JSONResponse(status_code=503, content={"detail": "paused"})
        _in_flight += 1
    try:
        return await call_next(request)
    finally:
        with _lock:
            _in_flight -= 1


class MeetingRequest(BaseModel):
    title: str


@app.get("/health")
def health():
    try:
        with closing(_db()) as db:
            with db.cursor() as cur:
                cur.execute("SELECT 1")
                database_ok = cur.fetchone()[0] == 1
    except Exception:
        database_ok = False
    try:
        client = _redis()
        try:
            redis_ok = bool(client.ping())
        finally:
            client.close()
    except Exception:
        redis_ok = False

    result = {"status": "healthy" if database_ok and redis_ok else "unhealthy",
              "database": database_ok, "redis": redis_ok}
    return JSONResponse(status_code=200 if database_ok and redis_ok else 503,
                        content=result)


@app.get("/meetings")
def list_meetings():
    with closing(_db()) as db:
        with db.cursor() as cur:
            cur.execute(
                "SELECT id, title, created_at, processed_at "
                "FROM meetings ORDER BY id DESC"
            )
            rows = cur.fetchall()
    return [
        {"id": row[0], "title": row[1],
         "created_at": row[2], "processed_at": row[3]}
        for row in rows
    ]


@app.post("/meetings", status_code=201)
def create_meeting(item: MeetingRequest):
    with closing(_db()) as db:
        with db.cursor() as cur:
            cur.execute("INSERT INTO meetings(title) VALUES (%s) RETURNING id",
                        (item.title,))
            meeting_id = cur.fetchone()[0]
            db.commit()
    client = _redis()
    try:
        client.rpush("meeting_jobs", meeting_id)
    finally:
        client.close()
    return {"id": meeting_id, "title": item.title, "status": "queued"}


@app.get("/meetings/{meeting_id}")
def get_meeting(meeting_id: int):
    with closing(_db()) as db:
        with db.cursor() as cur:
            cur.execute(
                "SELECT id, title, created_at, processed_at "
                "FROM meetings WHERE id = %s", (meeting_id,)
            )
            row = cur.fetchone()
    if not row:
        return JSONResponse(status_code=404, content={"detail": "Not found"})
    return {"id": row[0], "title": row[1],
            "created_at": row[2], "processed_at": row[3]}
