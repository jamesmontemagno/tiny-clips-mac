#!/usr/bin/env python3

import json
import re
import sys
from pathlib import Path


STATE_DIR_NAME = ".state"
CHANGELOG_PATH = "CHANGELOG.md"
SOURCE_PREFIXES = (
    "TinyClips/",
    "TinyClips.xcodeproj/",
)
EDIT_TOOL_NAMES = {
    "apply_patch",
    "create_file",
    "vscode_renameSymbol",
}
PATCH_FILE_PATTERN = re.compile(
    r"^\*\*\*\s+(?:Add|Update|Delete)\s+File:\s+(.+?)(?:\s+->\s+.+)?$",
    re.MULTILINE,
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


def state_file(repo_root, session_id):
    return repo_root / ".github" / "hooks" / STATE_DIR_NAME / f"{session_id}.json"


def load_state(path):
    if not path.exists():
        return {"editedPaths": []}

    try:
        return json.loads(path.read_text())
    except (json.JSONDecodeError, OSError):
        return {"editedPaths": []}


def save_state(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True))


def is_source_path(path):
    return any(path.startswith(prefix) for prefix in SOURCE_PREFIXES)


def handle_post_tool_use(payload, repo_root):
    tool_name = payload.get("tool_name")
    if tool_name not in EDIT_TOOL_NAMES:
        emit({"continue": True})
        return

    edited_paths = sorted(extract_paths_from_payload(payload.get("tool_input", {}), repo_root))
    if not edited_paths:
        emit({"continue": True})
        return

    state_path = state_file(repo_root, payload["sessionId"])
    existing = load_state(state_path)
    merged_paths = sorted(set(existing.get("editedPaths", [])) | set(edited_paths))
    save_state(state_path, {"editedPaths": merged_paths})
    emit({"continue": True})


def handle_stop(payload, repo_root):
    if payload.get("stop_hook_active"):
        emit({"continue": True})
        return

    state_path = state_file(repo_root, payload["sessionId"])
    edited_paths = set(load_state(state_path).get("editedPaths", []))

    source_paths = sorted(path for path in edited_paths if is_source_path(path))
    changelog_touched = CHANGELOG_PATH in edited_paths

    if source_paths and not changelog_touched:
        reason = (
            "Product source files were edited in this session without updating CHANGELOG.md. "
            "Add a changelog entry before finishing if this work is a feature or fix. "
            f"Edited files: {', '.join(source_paths[:5])}"
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
        return

    emit({"continue": True})


def main():
    try:
        payload = json.load(sys.stdin)
    except json.JSONDecodeError:
        emit({"continue": True, "systemMessage": "require_changelog_update hook received invalid JSON input."})
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
        emit({"continue": True, "systemMessage": f"require_changelog_update hook warning: {error}"})
        return

    emit({"continue": True})


if __name__ == "__main__":
    main()