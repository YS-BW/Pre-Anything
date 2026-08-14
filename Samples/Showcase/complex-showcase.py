"""Complex, inert Python sample for Quick Look rendering."""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator, Callable
from dataclasses import dataclass, field
from enum import StrEnum
from typing import Generic, TypeVar

Payload = TypeVar("Payload")


class PreviewState(StrEnum):
    QUEUED = "queued"
    READY = "ready"
    FAILED = "failed"


@dataclass(frozen=True, slots=True)
class PreviewResult(Generic[Payload]):
    identifier: str
    state: PreviewState
    payload: Payload | None = None
    metadata: dict[str, str | int | bool] = field(default_factory=dict)

    @property
    def is_ready(self) -> bool:
        return self.state is PreviewState.READY


async def stream_previews(
    paths: list[str],
    transform: Callable[[str], str] = str.upper,
) -> AsyncIterator[PreviewResult[str]]:
    """Yield deterministic preview records without touching the network."""
    for index, path in enumerate(paths, start=1):
        await asyncio.sleep(0)
        normalized = transform(path.strip())
        yield PreviewResult(
            identifier=f"preview-{index:03d}",
            state=PreviewState.READY if normalized else PreviewState.FAILED,
            payload=normalized or None,
            metadata={"index": index, "cached": False, "ratio": 0.625},
        )


def classify(value: object) -> str:
    match value:
        case {"kind": "markdown", "size": int(size)} if size > 0:
            return f"document:{size}"
        case [first, *rest]:
            return f"sequence:{first!r}+{len(rest)}"
        case None:
            return "empty"
        case _:
            return "unknown"


if __name__ == "__main__":
    # Preview-only fixture: the Quick Look extension never executes this block.
    print(classify({"kind": "markdown", "size": 42}))
