#!/usr/bin/env python3
"""Deterministic tests for the Docker Registry availability guard."""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path
from typing import Any
from unittest import mock

MODULE_PATH = Path(__file__).with_name("fedora_base_availability_test.py")
SPEC = importlib.util.spec_from_file_location("fedora_base_availability", MODULE_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load {MODULE_PATH}")
availability = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(availability)


def _digest(character: str) -> str:
    return f"sha256:{character * 64}"


class _Response:
    def __init__(self, payload: bytes = b"{}", **headers: str) -> None:
        self.payload = payload
        self.headers = headers

    def __enter__(self) -> _Response:
        return self

    def __exit__(self, *_args: Any) -> None:
        return None

    def read(self, _size: int = -1) -> bytes:
        return self.payload


class FedoraBaseAvailabilityTest(unittest.TestCase):
    def _registry_responses(self) -> list[tuple[dict[str, Any], str | None]]:
        amd64 = _digest("a")
        arm64 = _digest("b")
        return [
            ({"access_token": "fixture-token"}, None),
            (
                {
                    "manifests": [
                        {
                            "digest": amd64,
                            "size": 100,
                            "mediaType": "application/vnd.oci.image.manifest.v1+json",
                            "platform": {"os": "linux", "architecture": "amd64"},
                        },
                        {
                            "digest": arm64,
                            "size": 200,
                            "mediaType": "application/vnd.oci.image.manifest.v1+json",
                            "platform": {"os": "linux", "architecture": "arm64"},
                        },
                    ]
                },
                "sha256:762d73ba1c455232b0272c5d445a34f36c4b9f421cbc05ce8102552325b6a222",
            ),
            (
                {
                    "config": {"digest": _digest("c"), "size": 10},
                    "layers": [{"digest": _digest("d"), "size": 20}],
                },
                amd64,
            ),
            (
                {
                    "config": {"digest": _digest("e"), "size": 30},
                    "layers": [{"digest": _digest("f"), "size": 40}],
                },
                arm64,
            ),
        ]

    def test_main_checks_both_manifests_and_all_blobs(self) -> None:
        responses = iter(self._registry_responses())
        with (
            mock.patch.object(
                availability,
                "_read_json",
                side_effect=lambda *_a, **_k: next(responses),
            ),
            mock.patch.object(availability, "_check_blob") as check_blob,
            mock.patch("builtins.print") as print_output,
        ):
            availability.main()

        self.assertEqual(check_blob.call_count, 4)
        self.assertEqual(print_output.call_count, 2)

    def test_main_rejects_missing_required_platform(self) -> None:
        responses = iter(
            [
                ({"token": "fixture-token"}, None),
                (
                    {
                        "manifests": [
                            {
                                "digest": _digest("a"),
                                "size": 100,
                                "mediaType": "application/vnd.oci.image.manifest.v1+json",
                                "platform": {"os": "linux", "architecture": "amd64"},
                            }
                        ]
                    },
                    "sha256:762d73ba1c455232b0272c5d445a34f36c4b9f421cbc05ce8102552325b6a222",
                ),
            ]
        )
        with mock.patch.object(
            availability, "_read_json", side_effect=lambda *_a, **_k: next(responses)
        ):
            with self.assertRaisesRegex(RuntimeError, "missing required platforms"):
                availability.main()

    def test_main_rejects_wrong_index_digest(self) -> None:
        responses = iter(
            [
                ({"token": "fixture-token"}, None),
                ({"manifests": []}, _digest("0")),
            ]
        )
        with mock.patch.object(
            availability, "_read_json", side_effect=lambda *_a, **_k: next(responses)
        ):
            with self.assertRaisesRegex(RuntimeError, "served index digest"):
                availability.main()

    def test_main_fails_when_a_referenced_blob_is_unavailable(self) -> None:
        responses = iter(self._registry_responses())
        with (
            mock.patch.object(
                availability,
                "_read_json",
                side_effect=lambda *_a, **_k: next(responses),
            ),
            mock.patch.object(
                availability,
                "_check_blob",
                side_effect=RuntimeError("blob unavailable"),
            ),
        ):
            with self.assertRaisesRegex(RuntimeError, "blob unavailable"):
                availability.main()

    def test_main_uses_first_matching_platform_descriptor(self) -> None:
        responses = self._registry_responses()
        first_amd64 = _digest("9")
        responses[1][0]["manifests"].insert(
            0,
            {
                "digest": first_amd64,
                "size": 90,
                "mediaType": "application/vnd.oci.image.manifest.v1+json",
                "platform": {"os": "linux", "architecture": "amd64"},
            },
        )
        responses[2] = (responses[2][0], first_amd64)
        read_json = mock.Mock(side_effect=responses)
        with (
            mock.patch.object(availability, "_read_json", read_json),
            mock.patch.object(availability, "_check_blob"),
            mock.patch("builtins.print"),
        ):
            availability.main()
        self.assertEqual(
            read_json.call_args_list[2].kwargs["expected_digest"], first_amd64
        )

    def test_main_rejects_conflicting_sizes_for_one_blob(self) -> None:
        responses = self._registry_responses()
        responses[3][0]["config"] = {"digest": _digest("c"), "size": 999}
        with (
            mock.patch.object(availability, "_read_json", side_effect=responses),
            mock.patch.object(availability, "_check_blob"),
            mock.patch("builtins.print"),
        ):
            with self.assertRaisesRegex(RuntimeError, "conflicting sizes"):
                availability.main()

    def test_descriptor_rejects_malformed_digest_and_size(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "invalid digest"):
            availability._descriptor({"digest": "latest", "size": 1}, "fixture")
        with self.assertRaisesRegex(RuntimeError, "invalid size"):
            availability._descriptor({"digest": _digest("a"), "size": True}, "fixture")
        with self.assertRaisesRegex(RuntimeError, "invalid media type"):
            availability._descriptor(
                {
                    "digest": _digest("a"),
                    "size": 1,
                    "mediaType": "text/plain",
                },
                "fixture",
                availability.IMAGE_MANIFEST_MEDIA_TYPES,
            )

    def test_json_reader_rejects_oversized_and_non_object_responses(self) -> None:
        oversized = _Response(b"x" * (availability.MAX_RESPONSE_BYTES + 1))
        with mock.patch.object(availability._OPENER, "open", return_value=oversized):
            with self.assertRaisesRegex(RuntimeError, "exceeds"):
                availability._read_json("https://registry-1.docker.io/fixture")

        non_object = _Response(b"[]")
        with mock.patch.object(availability._OPENER, "open", return_value=non_object):
            with self.assertRaisesRegex(RuntimeError, "not a JSON object"):
                availability._read_json("https://registry-1.docker.io/fixture")

        payload = b'{"schemaVersion":2}'
        with mock.patch.object(
            availability._OPENER, "open", return_value=_Response(payload)
        ):
            with self.assertRaisesRegex(RuntimeError, "response digest"):
                availability._read_json(
                    "https://registry-1.docker.io/fixture",
                    expected_digest=_digest("0"),
                    expected_size=len(payload),
                )

    def test_blob_check_requires_matching_digest_and_size(self) -> None:
        digest = _digest("a")
        wrong_digest = _Response(
            **{"Docker-Content-Digest": _digest("b"), "Content-Length": "10"}
        )
        with mock.patch.object(availability._OPENER, "open", return_value=wrong_digest):
            with self.assertRaisesRegex(RuntimeError, "served blob digest"):
                availability._check_blob(
                    "https://registry-1.docker.io/blobs", digest, 10, "token"
                )

        wrong_size = _Response(
            **{"Docker-Content-Digest": digest, "Content-Length": "11"}
        )
        with mock.patch.object(availability._OPENER, "open", return_value=wrong_size):
            with self.assertRaisesRegex(RuntimeError, "served blob size"):
                availability._check_blob(
                    "https://registry-1.docker.io/blobs", digest, 10, "token"
                )

    def test_redirects_are_rejected(self) -> None:
        handler = availability._RejectRedirects()
        self.assertIsNone(
            handler.redirect_request(
                mock.Mock(),
                mock.Mock(),
                302,
                "Found",
                {},
                "http://127.0.0.1/internal",
            )
        )

    def test_nested_deadline_preserves_earlier_alarm(self) -> None:
        timer = availability.signal
        timer.setitimer(timer.ITIMER_REAL, 5)
        try:
            with mock.patch.object(
                availability.time, "monotonic", side_effect=[100.0, 101.0]
            ):
                with availability._request_deadline():
                    pass
            remaining, _interval = timer.getitimer(timer.ITIMER_REAL)
            self.assertGreater(remaining, 3.8)
            self.assertLess(remaining, 4.1)
        finally:
            timer.setitimer(timer.ITIMER_REAL, 0)


if __name__ == "__main__":
    unittest.main()
