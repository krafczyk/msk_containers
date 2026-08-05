#!/usr/bin/env python3
"""Verify the pinned Fedora index, required manifests, and referenced blobs."""

from __future__ import annotations

import contextlib
import hashlib
import json
import re
import signal
import sys
import time
import urllib.parse
import urllib.request
from collections.abc import Iterator
from pathlib import Path
from types import FrameType
from typing import Any

REFERENCE_PATTERN = re.compile(r"docker\.io/library/fedora:43@(sha256:[0-9a-f]{64})")
DIGEST_PATTERN = re.compile(r"sha256:[0-9a-f]{64}")
MANIFEST_ACCEPT = ", ".join(
    (
        "application/vnd.oci.image.index.v1+json",
        "application/vnd.docker.distribution.manifest.list.v2+json",
        "application/vnd.oci.image.manifest.v1+json",
        "application/vnd.docker.distribution.manifest.v2+json",
    )
)
IMAGE_MANIFEST_MEDIA_TYPES = {
    "application/vnd.oci.image.manifest.v1+json",
    "application/vnd.docker.distribution.manifest.v2+json",
}
MAX_RESPONSE_BYTES = 2 * 1024 * 1024
REQUEST_TIMEOUT_SECONDS = 30
USER_AGENT = "mkchad-fedora-base-availability-test/1"


class _RejectRedirects(urllib.request.HTTPRedirectHandler):
    """Prevent an external Registry response from redirecting host requests."""

    def redirect_request(
        self,
        req: urllib.request.Request,
        fp: Any,
        code: int,
        msg: str,
        headers: Any,
        newurl: str,
    ) -> None:
        """Reject every redirect rather than issuing a follow-up request."""
        return None


_OPENER = urllib.request.build_opener(_RejectRedirects())


def _timeout_request(_signum: int, _frame: FrameType | None) -> None:
    raise TimeoutError("registry request exceeded its wall-clock deadline")


@contextlib.contextmanager
def _request_deadline() -> Iterator[None]:
    previous_handler = signal.getsignal(signal.SIGALRM)
    previous_timer = signal.getitimer(signal.ITIMER_REAL)
    deadline = REQUEST_TIMEOUT_SECONDS
    if previous_timer[0] > 0:
        deadline = min(deadline, previous_timer[0])
    started = time.monotonic()
    signal.signal(signal.SIGALRM, _timeout_request)
    signal.setitimer(signal.ITIMER_REAL, deadline)
    try:
        yield
    finally:
        signal.setitimer(signal.ITIMER_REAL, 0)
        signal.signal(signal.SIGALRM, previous_handler)
        if previous_timer[0] > 0:
            elapsed = time.monotonic() - started
            remaining = max(0.000001, previous_timer[0] - elapsed)
            signal.setitimer(signal.ITIMER_REAL, remaining, previous_timer[1])


def _headers(token: str | None = None) -> dict[str, str]:
    headers = {"Accept": MANIFEST_ACCEPT, "User-Agent": USER_AGENT}
    if token is not None:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def _read_json(
    url: str,
    *,
    token: str | None = None,
    expected_digest: str | None = None,
    expected_size: int | None = None,
) -> tuple[dict[str, Any], str | None]:
    request = urllib.request.Request(url, headers=_headers(token))
    with _request_deadline():
        with _OPENER.open(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
            payload = response.read(MAX_RESPONSE_BYTES + 1)
            if len(payload) > MAX_RESPONSE_BYTES:
                raise RuntimeError(
                    f"registry response exceeds {MAX_RESPONSE_BYTES} bytes"
                )
            if expected_size is not None and len(payload) != expected_size:
                raise RuntimeError(
                    f"registry response size {len(payload)}, expected {expected_size}"
                )
            if expected_digest is not None:
                actual_digest = f"sha256:{hashlib.sha256(payload).hexdigest()}"
                if actual_digest != expected_digest:
                    raise RuntimeError(
                        f"registry response digest {actual_digest}, "
                        f"expected {expected_digest}"
                    )
            parsed = json.loads(payload)
            if not isinstance(parsed, dict):
                raise RuntimeError("registry response is not a JSON object")
            return parsed, response.headers.get("Docker-Content-Digest")


def _descriptor(
    value: Any, label: str, media_types: set[str] | None = None
) -> tuple[str, int]:
    if not isinstance(value, dict):
        raise RuntimeError(f"{label} descriptor is not an object")
    digest = value.get("digest")
    size = value.get("size")
    if not isinstance(digest, str) or DIGEST_PATTERN.fullmatch(digest) is None:
        raise RuntimeError(f"{label} descriptor has an invalid digest")
    if not isinstance(size, int) or isinstance(size, bool) or size < 0:
        raise RuntimeError(f"{label} descriptor has an invalid size")
    if media_types is not None and value.get("mediaType") not in media_types:
        raise RuntimeError(f"{label} descriptor has an invalid media type")
    return digest, size


def _check_blob(url: str, digest: str, size: int, token: str) -> None:
    request = urllib.request.Request(
        f"{url}/{digest}", headers=_headers(token), method="HEAD"
    )
    with _request_deadline():
        with _OPENER.open(request, timeout=REQUEST_TIMEOUT_SECONDS) as response:
            served_digest = response.headers.get("Docker-Content-Digest")
            served_size = response.headers.get("Content-Length")
            if served_digest != digest:
                raise RuntimeError(
                    f"registry served blob digest {served_digest!r}, expected {digest}"
                )
            if served_size is None or int(served_size) != size:
                raise RuntimeError(
                    f"registry served blob size {served_size!r}, expected {size}"
                )


def _dockerfile_reference(path: Path) -> str:
    with path.open(encoding="utf-8") as dockerfile:
        for line in dockerfile:
            fields = line.split()
            if fields and fields[0].upper() == "FROM" and len(fields) >= 2:
                return fields[1]
    raise RuntimeError(f"missing FROM instruction in {path}")


def main() -> None:
    """Validate source parity, immutable identity, platforms, and blob retention."""
    repo = Path(__file__).resolve().parents[1]
    dockerfiles = (
        repo / "nvim/x86/nvim_container_x86.dockerfile",
        repo / "nvim/aarch64/nvim_container_aarch64.dockerfile",
    )
    references = {_dockerfile_reference(path) for path in dockerfiles}
    if len(references) != 1:
        raise RuntimeError("x86_64 and aarch64 Fedora base references differ")
    reference = references.pop()
    match = REFERENCE_PATTERN.fullmatch(reference)
    if match is None:
        raise RuntimeError(f"unexpected Fedora base reference: {reference}")
    index_digest = match.group(1)

    token_query = urllib.parse.urlencode(
        {
            "service": "registry.docker.io",
            "scope": "repository:library/fedora:pull",
        }
    )
    token_response, _ = _read_json(f"https://auth.docker.io/token?{token_query}")
    token = token_response.get("token")
    if not isinstance(token, str) or not token:
        token = token_response.get("access_token")
    if not isinstance(token, str) or not token:
        raise RuntimeError("Docker Hub token response did not contain a bearer token")

    registry_url = "https://registry-1.docker.io/v2/library/fedora"
    manifest_url = f"{registry_url}/manifests"
    index, served_digest = _read_json(
        f"{manifest_url}/{index_digest}",
        token=token,
        expected_digest=index_digest,
    )
    if served_digest != index_digest:
        raise RuntimeError(
            f"registry served index digest {served_digest!r}, expected {index_digest}"
        )
    manifests = index.get("manifests")
    if not isinstance(manifests, list):
        raise RuntimeError("pinned Fedora reference is not a multi-architecture index")

    required = {("linux", "amd64"), ("linux", "arm64")}
    selected: dict[tuple[str, str], tuple[str, int]] = {}
    for manifest in manifests:
        if not isinstance(manifest, dict) or not isinstance(
            manifest.get("platform"), dict
        ):
            continue
        platform = manifest["platform"]
        key = (platform.get("os"), platform.get("architecture"))
        if key in required and key not in selected:
            selected[key] = _descriptor(
                manifest, f"{key} manifest", IMAGE_MANIFEST_MEDIA_TYPES
            )
    missing = required - selected.keys()
    if missing:
        raise RuntimeError(
            f"Fedora index is missing required platforms: {sorted(missing)}"
        )

    checked_blobs: dict[str, int] = {}
    blob_url = f"{registry_url}/blobs"
    for platform in sorted(required):
        child_digest, child_size = selected[platform]
        child, served_child_digest = _read_json(
            f"{manifest_url}/{child_digest}",
            token=token,
            expected_digest=child_digest,
            expected_size=child_size,
        )
        if served_child_digest != child_digest:
            raise RuntimeError(
                f"registry served {platform} digest {served_child_digest!r}, "
                f"expected {child_digest}"
            )
        config_descriptor = _descriptor(child.get("config"), f"{platform} config")
        layers = child.get("layers")
        if not isinstance(layers, list):
            raise RuntimeError(f"{platform} manifest layers are not an array")
        descriptors = [config_descriptor]
        descriptors.extend(
            _descriptor(layer, f"{platform} layer {index}")
            for index, layer in enumerate(layers)
        )
        for digest, size in descriptors:
            if digest in checked_blobs:
                if checked_blobs[digest] != size:
                    raise RuntimeError(
                        f"conflicting sizes for blob {digest}: "
                        f"{checked_blobs[digest]} and {size}"
                    )
                continue
            _check_blob(blob_url, digest, size, token)
            checked_blobs[digest] = size
        print(f"Fedora 43 {platform[0]}/{platform[1]} available at {child_digest}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError) as error:
        print(f"Fedora base availability check failed: {error}", file=sys.stderr)
        raise SystemExit(1) from error
