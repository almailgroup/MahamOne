#!/usr/bin/env python3
"""Asks App Store Connect how a TestFlight build is doing, and with --wait,
waits until Apple has finished processing it.

usage: build_status.py [--wait] [BUILD]    BUILD: "7.1"; empty = the newest

Reads KEY_ID, ISSUER_ID and AUTH_KEY_PATH from the environment, like
check_asc_key.py. Writes the answer to the job summary when there is one.
"""
import os
import sys
import time
import urllib.parse

from check_asc_key import BUNDLE_ID, get, make_token

# Apple's processing usually takes 10–30 minutes; past this, say so and stop.
WAIT_MINUTES = 45


def summary(text: str) -> None:
    print(text)
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a") as file:
            file.write(text + "\n\n")


def newest_build(app_id: str, version: str) -> dict | None:
    query = {"filter[app]": app_id, "sort": "-uploadedDate", "limit": 1}
    if version:
        query["filter[version]"] = version
    status, body = get(f"/builds?{urllib.parse.urlencode(query)}", make_token())
    if status != 200:
        print(f"::warning::Apple answered {status} when asked for the build.")
        return None
    builds = body.get("data", [])
    return builds[0] if builds else None


def main() -> int:
    args = [arg for arg in sys.argv[1:] if arg != "--wait"]
    wait = "--wait" in sys.argv[1:]
    version = args[0].strip() if args else ""

    query = urllib.parse.urlencode({"filter[bundleId]": BUNDLE_ID, "limit": 1})
    status, body = get(f"/apps?{query}", make_token())
    if status != 200 or not body.get("data"):
        print(f"::error::Couldn't find Maham One in App Store Connect (Apple answered {status}).")
        return 1
    app_id = body["data"][0]["id"]

    deadline = time.time() + WAIT_MINUTES * 60
    while True:
        build = newest_build(app_id, version)
        state = build["attributes"].get("processingState") if build else None
        number = build["attributes"].get("version", version) if build else version
        if state == "VALID":
            summary(
                f"### Build {number} is ready in TestFlight\n\n"
                "Apple has processed it. Testers in an internal group with automatic distribution get it "
                "in the TestFlight app; otherwise add it to a group in App Store Connect → TestFlight.")
            return 0
        if state in ("FAILED", "INVALID"):
            summary(
                f"### Apple couldn't process build {number} ({state.lower()})\n\n"
                "App Store Connect emails the reason to the account holder; it also shows under "
                "TestFlight → the build.")
            return 1
        if not wait or time.time() > deadline:
            if build:
                summary(f"### Build {number} is still processing\n\nApple emails you when it's ready.")
            else:
                summary(f"### Build {version or 'the newest'} isn't in App Store Connect yet\n\n"
                        "Right after an upload it can take a few minutes to appear.")
            return 0
        print(f"Build {number or '(not listed yet)'}: {state or 'waiting for it to appear'}…")
        time.sleep(60)


if __name__ == "__main__":
    sys.exit(main())
