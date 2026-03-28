#!/usr/bin/env python3

import json
import sys


def main():
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        payload = {}

    if payload.get("hookEventName") != "SessionStart":
        sys.stdout.write(json.dumps({"continue": True}))
        return

    context = (
        "Repository policy reminders: if this turn adds a feature or fixes a bug, update CHANGELOG.md before finishing. "
        "If you edit product source under TinyClips/ or TinyClips.xcodeproj/, validate both app schemes before finishing. "
        "Preferred verification commands are: xcodebuild build -project TinyClips.xcodeproj -scheme TinyClips -configuration Debug "
        "CODE_SIGN_IDENTITY=\"\" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO and xcodebuild build -project TinyClips.xcodeproj "
        "-scheme TinyClipsMAS -configuration Debug CODE_SIGN_IDENTITY=\"\" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO. "
        "If sandboxed xcodebuild fails with cache or SwiftPM permission errors, rerun unsandboxed."
    )
    sys.stdout.write(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "SessionStart",
                    "additionalContext": context,
                }
            }
        )
    )


if __name__ == "__main__":
    main()