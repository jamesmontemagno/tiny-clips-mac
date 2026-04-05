#!/usr/bin/env python3

import json
import re
import sys
from pathlib import Path


STATE_DIR_NAME = ".state"
STATE_FILE_SUFFIX = "-build-validation.json"
SOURCE_PREFIXES = (
    "TinyClips/",
    "TinyClips.xcodeproj/",
)
EDIT_TOOL_NAMES = {
    "apply_patch",
    "create_file",
    "multi_replace_string_in_file",
    "replace_string_in_file",
    "vscode_renameSymbol",
}
BUILD_TOOL_NAMES = {
    "create_and_run_task",
    "execution_subagent",
    "run_in_terminal",
}
TARGET_SCHEMES = ("TinyClips", "TinyClipsMAS")
PATCH_FILE_PATTERN = re.compile(
    r"^\*\*\*\s+(?:Add|Update|Delete)\s+File:\s+(.+?)(?:\s+->\s+.+)?$",
    re.MULTILINE,
)
SUCCESS_PATTERNS = (
    re.compile(r"\bBUILD SUCCEEDED\b", re.IGNORECASE),
    re.compile(r"\bexit code:?\s*0\b", re.IGNORECASE),
    re.compile(r"\bExit Code:\s*0\b", re.IGNORECASE),
)


def emit(payload):
    sys.stdout.write(json.dumps(payload))


def normalize_path(value, repo_root):
    if not isinstance(value, str) or not value:
        return None

    path_value = value
    if path_value.startswith("file://"):
        path_value = path_value[7:]

    try:
        path = Path(path_value)
    except OSError:
        return None

    if not path.is_absolute():
        path = (repo_root / path).resolve()
    else:
        path = path.resolve()

    try:
        return path.relative_to(repo_root).as_posix()
    except ValueError:
        return None


def extract_paths_from_patch(patch_text, repo_root):
    paths = set()
    if not isinstance(patch_text, str):
        return paths

    for match in PATCH_FILE_PATTERN.finditer(patch_text):
        normalized = normalize_path(match.group(1).strip(), repo_root)
        if normalized:
            paths.add(normalized)

    return paths


def extract_paths_from_payload(payload, repo_root):
    paths = set()

    def visit(value, parent_key=None):
        if isinstance(value, dict):
            for key, nested_value in value.items():
                visit(nested_value, key)
            return

        if isinstance(value, list):
            for item in value:
                visit(item, parent_key)
            return

        if not isinstance(value, str):
            return

        if parent_key == "input":
            paths.update(extract_paths_from_patch(value, repo_root))

        if parent_key in {"filePath", "filePaths", "path", "uri", "oldPath", "newPath", "old_path", "new_path"}:
            normalized = normalize_path(value, repo_root)
            if normalized:
                paths.add(normalized)

    visit(payload)
    return paths


def collect_strings(value):
    strings = []

    def visit(node):
        if isinstance(node, dict):
            for child in node.values():
                visit(child)
            return

        if isinstance(node, list):
            for child in node:
                visit(child)
            return

        if isinstance(node, str):
            strings.append(node)

    visit(value)
    return strings


def state_file(repo_root, session_id):
    return repo_root / ".github" / "hooks" / STATE_DIR_NAME / f"{session_id}{STATE_FILE_SUFFIX}"


def load_state(path):
    if not path.exists():
        return {
            "editedPaths": [],
            "sourceRevision": 0,
            "validatedSchemes": {scheme: 0 for scheme in TARGET_SCHEMES},
        }

    try:
        data = json.loads(path.read_text())
    except (json.JSONDecodeError, OSError):
        data = {}

    validated = data.get("validatedSchemes", {})
    return {
        "editedPaths": data.get("editedPaths", []),
        "sourceRevision": data.get("sourceRevision", 0),
        "validatedSchemes": {
            scheme: int(validated.get(scheme, 0)) for scheme in TARGET_SCHEMES
        },
    }


def save_state(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True))


def is_source_path(path):
    return any(path.startswith(prefix) for prefix in SOURCE_PREFIXES)


def mark_edits(payload, repo_root, state):
    edited_paths = sorted(extract_paths_from_payload(payload.get("tool_input", {}), repo_root))
    if not edited_paths:
        return state

    merged_paths = sorted(set(state.get("editedPaths", [])) | set(edited_paths))
    source_revision = state.get("sourceRevision", 0)
    if any(is_source_path(path) for path in edited_paths):
        source_revision += 1

    return {
        **state,
        "editedPaths": merged_paths,
        "sourceRevision": source_revision,
    }


def payload_mentions_scheme(text, scheme):
    return f"-scheme {scheme}" in text or f"scheme {scheme}" in text


def payload_has_success(text):
    return any(pattern.search(text) for pattern in SUCCESS_PATTERNS)


def mark_builds(payload, state):
    combined_text = "\n".join(collect_strings(payload))
    if "xcodebuild" not in combined_text:
        return state

    if not payload_has_success(combined_text):
        return state

    validated_schemes = dict(state.get("validatedSchemes", {}))
    current_revision = state.get("sourceRevision", 0)
    for scheme in TARGET_SCHEMES:
        if payload_mentions_scheme(combined_text, scheme):
            validated_schemes[scheme] = current_revision

    return {
        **state,
        "validatedSchemes": validated_schemes,
    }


def handle_post_tool_use(payload, repo_root):
    tool_name = payload.get("tool_name")
    if tool_name not in EDIT_TOOL_NAMES and tool_name not in BUILD_TOOL_NAMES:
        emit({"continue": True})
        return

    state_path = state_file(repo_root, payload["sessionId"])
    state = load_state(state_path)

    if tool_name in EDIT_TOOL_NAMES:
        state = mark_edits(payload, repo_root, state)

    if tool_name in BUILD_TOOL_NAMES:
        state = mark_builds(payload, state)

    save_state(state_path, state)
    emit({"continue": True})


def handle_stop(payload, repo_root):
    if payload.get("stop_hook_active"):
        emit({"continue": True})
        return

    state = load_state(state_file(repo_root, payload["sessionId"]))
    source_revision = state.get("sourceRevision", 0)
    if source_revision == 0:
        emit({"continue": True})
        return

    missing_schemes = [
        scheme
        for scheme, validated_revision in state.get("validatedSchemes", {}).items()
        if validated_revision < source_revision
    ]
    if not missing_schemes:
        emit({"continue": True})
        return

    reason = (
        "Product source files changed in this session, but required scheme builds are missing or stale. "
        f"Run successful builds for: {', '.join(missing_schemes)}. "
        "Preferred commands: xcodebuild build -project TinyClips.xcodeproj -scheme TinyClips -configuration Debug "
        "CODE_SIGN_IDENTITY=\"\" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO and xcodebuild build -project "
        "TinyClips.xcodeproj -scheme TinyClipsMAS -configuration Debug CODE_SIGN_IDENTITY=\"\" CODE_SIGNING_REQUIRED=NO "
        "CODE_SIGNING_ALLOWED=NO."
    )
    emit(
        {
            "hookSpecificOutput": {
                "hookEventName": "Stop",
                "decision": "block",
                "reason": reason,
            }
        }
    )


def main():
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        emit({"continue": True, "systemMessage": "require_build_validation hook received invalid JSON input."})
        return

    cwd = payload.get("cwd")
    session_id = payload.get("sessionId")
    event_name = payload.get("hookEventName")
    if not cwd or not session_id or not event_name:
        emit({"continue": True})
        return

    repo_root = Path(cwd).resolve()

    try:
        if event_name == "PostToolUse":
            handle_post_tool_use(payload, repo_root)
            return

        if event_name == "Stop":
            handle_stop(payload, repo_root)
            return
    except OSError as error:
        emit({"continue": True, "systemMessage": f"require_build_validation hook warning: {error}"})
        return

    emit({"continue": True})


if __name__ == "__main__":
    main()