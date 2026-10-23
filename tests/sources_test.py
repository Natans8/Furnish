"""The build's fetch: a transient failure is tried again, a refusal is not."""

import io
import urllib.error
import urllib.request
from collections.abc import Iterator
from typing import Any

import pytest

from furnish import sources


class _Response(io.BytesIO):
    def __enter__(self) -> _Response:
        return self

    def __exit__(self, *_: object) -> None:
        self.close()


def _urlopen_script(answers: list[Any]) -> Iterator[Any]:
    yield from answers


def test_a_dropped_connection_is_tried_again(monkeypatch: pytest.MonkeyPatch) -> None:
    script = _urlopen_script(
        [
            urllib.error.URLError("connection reset"),
            TimeoutError("timed out"),
            _Response(b"rows"),
        ]
    )
    waits: list[float] = []

    def urlopen(_request: Any, timeout: int) -> Any:
        answer = next(script)
        if isinstance(answer, Exception):
            raise answer
        return answer

    monkeypatch.setattr(urllib.request, "urlopen", urlopen)
    assert sources._get("https://x/t.csv", 1, sleep=waits.append) == b"rows"
    assert waits == [2.0, 4.0]


def test_a_refusal_is_not_tried_again(monkeypatch: pytest.MonkeyPatch) -> None:
    calls = 0

    def urlopen(_request: Any, timeout: int) -> Any:
        nonlocal calls
        calls += 1
        raise urllib.error.HTTPError("https://x/t.csv", 404, "not found", {}, None)  # type: ignore[arg-type]

    monkeypatch.setattr(urllib.request, "urlopen", urlopen)
    with pytest.raises(RuntimeError, match="refused: HTTP 404"):
        sources._get("https://x/t.csv", 1, sleep=lambda _: None)
    assert calls == 1


def test_every_attempt_failing_names_the_last_error(monkeypatch: pytest.MonkeyPatch) -> None:
    def urlopen(_request: Any, timeout: int) -> Any:
        raise urllib.error.HTTPError("https://x/t.csv", 503, "busy", {}, None)  # type: ignore[arg-type]

    monkeypatch.setattr(urllib.request, "urlopen", urlopen)
    with pytest.raises(RuntimeError, match="in 3 attempts"):
        sources._get("https://x/t.csv", 1, sleep=lambda _: None)
