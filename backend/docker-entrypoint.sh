#!/bin/sh
# Migrate the database and load the seed questions (idempotent), then start the server.
set -e
alembic upgrade head
python -m app.questions.seed
exec "$@"
