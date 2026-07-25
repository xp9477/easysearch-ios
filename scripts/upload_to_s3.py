#!/usr/bin/env python3
"""Upload a local file to an S3-compatible endpoint (MinIO) with AWS SigV4."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import hmac
import os
import ssl
import sys
import urllib.error
import urllib.request


def _sign(key: bytes, msg: str) -> bytes:
    return hmac.new(key, msg.encode("utf-8"), hashlib.sha256).digest()


def _signature_key(secret: str, datestamp: str, region: str, service: str) -> bytes:
    k_date = _sign(("AWS4" + secret).encode("utf-8"), datestamp)
    k_region = _sign(k_date, region)
    k_service = _sign(k_region, service)
    return _sign(k_service, "aws4_request")


def put_object(
    *,
    endpoint: str,
    bucket: str,
    key: str,
    file_path: str,
    access_key: str,
    secret_key: str,
    region: str,
    content_type: str,
) -> None:
    endpoint = endpoint.rstrip("/")
    host = endpoint.split("://", 1)[1]
    with open(file_path, "rb") as fh:
        body = fh.read()

    payload_hash = hashlib.sha256(body).hexdigest()
    now = dt.datetime.now(dt.timezone.utc)
    amz_date = now.strftime("%Y%m%dT%H%M%SZ")
    datestamp = now.strftime("%Y%m%d")
    canonical_uri = f"/{bucket}/{key}"
    canonical_headers = (
        f"host:{host}\n"
        f"x-amz-content-sha256:{payload_hash}\n"
        f"x-amz-date:{amz_date}\n"
    )
    signed_headers = "host;x-amz-content-sha256;x-amz-date"
    canonical_request = "\n".join(
        [
            "PUT",
            canonical_uri,
            "",
            canonical_headers,
            signed_headers,
            payload_hash,
        ]
    )
    algorithm = "AWS4-HMAC-SHA256"
    credential_scope = f"{datestamp}/{region}/s3/aws4_request"
    string_to_sign = "\n".join(
        [
            algorithm,
            amz_date,
            credential_scope,
            hashlib.sha256(canonical_request.encode("utf-8")).hexdigest(),
        ]
    )
    signing_key = _signature_key(secret_key, datestamp, region, "s3")
    signature = hmac.new(signing_key, string_to_sign.encode("utf-8"), hashlib.sha256).hexdigest()
    authorization = (
        f"{algorithm} Credential={access_key}/{credential_scope}, "
        f"SignedHeaders={signed_headers}, Signature={signature}"
    )

    url = f"{endpoint}{canonical_uri}"
    request = urllib.request.Request(url, data=body, method="PUT")
    request.add_header("Content-Type", content_type)
    request.add_header("x-amz-content-sha256", payload_hash)
    request.add_header("x-amz-date", amz_date)
    request.add_header("Authorization", authorization)

    context = ssl.create_default_context()
    try:
        with urllib.request.urlopen(request, context=context, timeout=300) as response:
            print(f"Uploaded s3://{bucket}/{key} -> HTTP {response.status}")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", "replace")
        raise SystemExit(f"Upload failed HTTP {exc.code}: {detail}") from exc


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", required=True)
    parser.add_argument("--key", required=True, help="Object key inside bucket, e.g. easysearch-iOS/latest.json")
    parser.add_argument("--content-type", default="application/octet-stream")
    args = parser.parse_args()

    endpoint = os.environ.get("S3_ENDPOINT", "").strip()
    bucket = os.environ.get("S3_BUCKET", "").strip()
    access_key = os.environ.get("S3_ACCESS_KEY", "").strip()
    secret_key = os.environ.get("S3_SECRET_KEY", "").strip()
    region = os.environ.get("S3_REGION", "us-east-1").strip() or "us-east-1"

    missing = [name for name, value in [
        ("S3_ENDPOINT", endpoint),
        ("S3_BUCKET", bucket),
        ("S3_ACCESS_KEY", access_key),
        ("S3_SECRET_KEY", secret_key),
    ] if not value]
    if missing:
        raise SystemExit(f"Missing required env: {', '.join(missing)}")

    put_object(
        endpoint=endpoint,
        bucket=bucket,
        key=args.key,
        file_path=args.file,
        access_key=access_key,
        secret_key=secret_key,
        region=region,
        content_type=args.content_type,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
