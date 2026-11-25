#!/usr/bin/env python3
"""Asks Apple whether the TestFlight workflow's App Store Connect key works,
and says in plain words what's wrong if it doesn't. Nothing secret is
printed: only whether each thing matches.

Reads KEY_ID, ISSUER_ID, TEAM_ID and AUTH_KEY_PATH from the environment.
Needs PyJWT with cryptography (the workflow installs them).
"""
import base64
import json
import os
import plistlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

API = "https://api.appstoreconnect.apple.com/v1"
BUNDLE_ID = "com.almailgroup.mahamone"
APP_GROUP = "group.com.almailgroup.mahamone"
HELP = 'See ios/README.md, "Getting it to TestFlight".'


def error(message: str) -> None:
    print(f"::error::{message} {HELP}")


def get(path: str, token: str, method: str = "GET") -> tuple[int, dict]:
    request = urllib.request.Request(
        f"{API}{path}", method=method, headers={"Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as failure:
        try:
            body = json.load(failure)
        except (ValueError, json.JSONDecodeError):
            body = {}
        return failure.code, body


def app_groups(profile_content: str) -> list[str]:
    """The App Groups a provisioning profile allows (it's a signed plist)."""
    data = base64.b64decode(profile_content)
    start, end = data.find(b"<?xml"), data.find(b"</plist>")
    if start < 0 or end < 0:
        return []
    plist = plistlib.loads(data[start : end + len(b"</plist>")])
    return list(plist.get("Entitlements", {}).get("com.apple.security.application-groups", []))


def check_profiles(identifier: str, token: str) -> None:
    """What Apple holds for one app id: its capabilities, and each profile's
    App Groups. A profile made before the App Group was attached is deleted,
    so Xcode makes a fresh one with the group in it."""
    query = urllib.parse.urlencode({"filter[identifier]": identifier, "limit": 5})
    status, body = get(f"/bundleIds?{query}", token)
    items = [item for item in body.get("data", []) if item["attributes"].get("identifier") == identifier]
    if not items:
        print(f"{identifier}: not registered yet (Xcode registers it).")
        return
    bundle = items[0]["id"]
    status, body = get(f"/bundleIds/{bundle}/bundleIdCapabilities", token)
    capabilities = sorted(item["attributes"].get("capabilityType", "") for item in body.get("data", []))
    print(f"{identifier}: capabilities {', '.join(capabilities) or 'none'}.")
    if "APP_GROUPS" not in capabilities:
        print(f"::error::{identifier} doesn't have App Groups switched on. {HELP}")
    status, body = get(f"/bundleIds/{bundle}/profiles?limit=50", token)
    profiles = body.get("data", [])
    if status != 200:
        print(f"  (Apple answered {status} when asked for its profiles.)")
    elif not profiles:
        print("  no stored profiles (Xcode's own team profiles aren't listed here).")
    for profile in profiles:
        attributes = profile["attributes"]
        name = attributes.get("name", "")
        groups = app_groups(attributes["profileContent"]) if attributes.get("profileContent") else []
        print(f"  profile \"{name}\" ({attributes.get('profileType')}, {attributes.get('profileState')}): App Groups {groups or 'none'}")
        if APP_GROUP not in groups:
            status, _ = get(f"/profiles/{profile['id']}", token, method="DELETE")
            if status in (200, 204):
                print(f"  deleted it: it was made without {APP_GROUP}, and Xcode makes a new one.")
            else:
                print(f"  couldn't delete it (Apple answered {status}).")


def main() -> int:
    key_id, issuer, team = os.environ["KEY_ID"].strip(), os.environ["ISSUER_ID"].strip(), os.environ["TEAM_ID"].strip()
    with open(os.environ["AUTH_KEY_PATH"]) as file:
        private_key = file.read()

    try:
        now = int(time.time())
        token = jwt.encode(
            {"iss": issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
            private_key, algorithm="ES256", headers={"kid": key_id, "typ": "JWT"})
    except Exception:
        error("APP_STORE_CONNECT_KEY isn't a valid .p8 key. Paste the whole text of the file again.")
        return 1

    ok = True
    query = urllib.parse.urlencode({"filter[identifier]": BUNDLE_ID, "limit": 5})
    status, body = get(f"/bundleIds?{query}", token)
    if status == 401:
        error(
            "Apple refused the key. The Key ID, the Issuer ID and the .p8 text must all belong to the same "
            "key, made under Team Keys (an Individual key has no Issuer ID and doesn't work here).")
        return 1
    if status == 403:
        error("The key works but isn't allowed to manage identifiers and certificates. Make a Team key with Admin access.")
        return 1
    if status != 200:
        error(f"Apple answered {status} when asked about the app's identifier. Try again in a few minutes.")
        return 1

    matches = [item for item in body.get("data", []) if item["attributes"].get("identifier") == BUNDLE_ID]
    if not matches:
        error(f"The key works, but its team has no identifier {BUNDLE_ID}. Register it (step 1) in the same team as the key.")
        ok = False
    else:
        print(f"The key works, and its team has the identifier {BUNDLE_ID}.")
        prefix = matches[0]["attributes"].get("seedId", "")
        if prefix and prefix != team:
            error(
                "APPLE_TEAM_ID isn't the team this key belongs to. Copy the Team ID from developer.apple.com → "
                "Membership details, for the team where you made the key, and update the secret.")
            ok = False
        elif prefix:
            print("APPLE_TEAM_ID matches the key's team.")

    query = urllib.parse.urlencode({"filter[bundleId]": BUNDLE_ID, "limit": 5})
    status, body = get(f"/apps?{query}", token)
    if status == 200 and not body.get("data"):
        error(f"App Store Connect has no app for {BUNDLE_ID} in this key's team. Create it (step 2).")
        ok = False
    elif status == 200:
        print("The app exists in App Store Connect.")
    else:
        print(f"::warning::Couldn't check the app in App Store Connect (Apple answered {status}).")

    for identifier in (BUNDLE_ID, BUNDLE_ID + ".widgets"):
        check_profiles(identifier, token)

    # Xcode's automatic signing makes a development profile for the archive,
    # and Apple only makes those for a team with at least one device.
    status, body = get("/devices?filter%5Bstatus%5D=ENABLED&limit=1", token)
    if status == 200:
        total = body.get("meta", {}).get("paging", {}).get("total", len(body.get("data", [])))
        print(f"Registered devices in the team: {total}.")

    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
