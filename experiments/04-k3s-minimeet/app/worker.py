"""Reference MiniMeet Redis worker with checkpoint-safe quiescence."""
import os
import time
from pathlib import Path
from contextlib import closing

import psycopg2
import redis

DATABASE_URL = os.environ["DATABASE_URL"]
REDIS_URL = os.environ["REDIS_URL"]
SHARED = Path("/shared")
PAUSE = SHARED / "minimeet.pause"
STATUS = SHARED / "worker.quiesce.status"
LOG = SHARED / "worker.log"
SHARED.mkdir(parents=True, exist_ok=True)

client = None
while True:
    if PAUSE.exists():
        if client is not None:
            client.close()
            client = None
        STATUS.write_text("PAUSED\n")
        time.sleep(0.25)
        continue

    if STATUS.exists():
        STATUS.unlink()

    try:
        if client is None:
            # BRPOP is bounded (2 s), and socket timeout is longer (5 s).
            client = redis.Redis.from_url(
                REDIS_URL, socket_timeout=5, socket_connect_timeout=3
            )
        item = client.brpop("meeting_jobs", timeout=2)
        if item is None:
            continue
        meeting_id = int(item[1])
        with closing(psycopg2.connect(DATABASE_URL, connect_timeout=3)) as db:
            with db.cursor() as cur:
                cur.execute(
                    "UPDATE meetings SET processed_at=NOW() WHERE id=%s",
                    (meeting_id,)
                )
            db.commit()
        with LOG.open("a") as out:
            out.write(f"processed meeting id={meeting_id}\n")
            out.flush()
    except (redis.RedisError, psycopg2.Error, OSError, ValueError) as exc:
        with LOG.open("a") as out:
            out.write(f"worker retry after error: {type(exc).__name__}\n")
        if client is not None:
            client.close()
            client = None
        time.sleep(1)
