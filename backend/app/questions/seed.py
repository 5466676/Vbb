"""Load the built-in seed questions: ``python -m app.questions.seed`` (idempotent)."""

import asyncio

from app.config import get_settings
from app.db import make_engine, make_sessionmaker
from app.questions.bank import load_seed


async def main() -> None:
    engine = make_engine(get_settings().database_url)
    async with make_sessionmaker(engine)() as s:
        result = await load_seed(s)
    await engine.dispose()
    print(
        f"seed: {result.inserted} inserted, {result.duplicates} already present, "
        f"{len(result.errors)} errors"
    )


if __name__ == "__main__":
    asyncio.run(main())
