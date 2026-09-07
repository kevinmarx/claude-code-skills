#!/usr/bin/env python3

import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


SCHEMA = "km-review-check/v2"
IMPLEMENTATION_STATES = {"addressed", "unaddressed", "contested", "unverified"}
SEVERITIES = {"blocking", "high", "medium", "low", "non-blocking"}
RESPONSE_STATES = {"unanswered", "author_dispositioned"}
ACCEPTANCE_STATES = {"pending", "accepted"}
THREAD_STATES = {"not_applicable", "unresolved", "resolved", "unknown"}
HUMAN_ACTION_STATES = {"pending", "satisfied"}
WORKFLOW_STATES = {
    "awaiting_rereview",
    "awaiting_acknowledgement",
    "settled",
}
COVERAGE_STATES = {"open", "closed"}
SEVERITY_ORDER = ("blocking", "high", "medium", "low", "non-blocking")


def require_mapping(value: Any, path: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{path} must be an object")
    return value


def require_list(value: Any, path: str) -> list[Any]:
    if not isinstance(value, list):
        raise ValueError(f"{path} must be an array")
    return value


def require_string(value: Any, path: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{path} must be a non-empty string")
    return value


def require_enum(value: Any, allowed: set[str], path: str) -> str:
    text = require_string(value, path)
    if text not in allowed:
        choices = ", ".join(sorted(allowed))
        raise ValueError(f"{path} must be one of: {choices}")
    return text


def validate_source(source: Any, path: str) -> dict[str, Any]:
    item = require_mapping(source, path)
    require_string(item.get("kind"), f"{path}.kind")
    require_string(item.get("id"), f"{path}.id")
    require_string(item.get("url"), f"{path}.url")
    return item


def validate_finding(finding: Any, path: str) -> dict[str, Any]:
    item = require_mapping(finding, path)
    require_string(item.get("id"), f"{path}.id")
    require_string(item.get("summary"), f"{path}.summary")
    require_enum(item.get("severity"), SEVERITIES, f"{path}.severity")

    implementation = require_mapping(
        item.get("implementation"), f"{path}.implementation"
    )
    state = require_enum(
        implementation.get("state"),
        IMPLEMENTATION_STATES,
        f"{path}.implementation.state",
    )
    evidence = require_list(
        implementation.get("evidence"), f"{path}.implementation.evidence"
    )
    if state == "addressed" and not evidence:
        raise ValueError(f"{path}.implementation.evidence is required when addressed")
    if state != "addressed":
        require_string(
            implementation.get("details"), f"{path}.implementation.details"
        )
    for index, value in enumerate(evidence):
        require_string(value, f"{path}.implementation.evidence[{index}]")

    sources = require_list(item.get("sources"), f"{path}.sources")
    if not sources:
        raise ValueError(f"{path}.sources must not be empty")
    for index, source in enumerate(sources):
        source_item = validate_source(source, f"{path}.sources[{index}]")
        require_string(source_item.get("author"), f"{path}.sources[{index}].author")
        require_enum(
            source_item.get("response"),
            RESPONSE_STATES,
            f"{path}.sources[{index}].response",
        )
        require_enum(
            source_item.get("acceptance"),
            ACCEPTANCE_STATES,
            f"{path}.sources[{index}].acceptance",
        )
        require_enum(
            source_item.get("thread_resolution"),
            THREAD_STATES,
            f"{path}.sources[{index}].thread_resolution",
        )
        is_thread = source_item["kind"] == "thread"
        thread_state = source_item["thread_resolution"]
        if is_thread and thread_state == "not_applicable":
            raise ValueError(
                f"{path}.sources[{index}].thread_resolution must describe the thread"
            )
        if not is_thread and thread_state != "not_applicable":
            raise ValueError(
                f"{path}.sources[{index}].thread_resolution must be not_applicable"
            )
    return item


def validate_human_action(action: Any, path: str) -> dict[str, Any]:
    item = require_mapping(action, path)
    require_string(item.get("id"), f"{path}.id")
    require_string(item.get("summary"), f"{path}.summary")
    require_enum(item.get("state"), HUMAN_ACTION_STATES, f"{path}.state")
    require_string(item.get("owner"), f"{path}.owner")
    sources = require_list(item.get("sources"), f"{path}.sources")
    if not sources:
        raise ValueError(f"{path}.sources must not be empty")
    for index, source in enumerate(sources):
        validate_source(source, f"{path}.sources[{index}]")
    return item


def validate_workflow_action(action: Any, path: str) -> dict[str, Any]:
    item = require_mapping(action, path)
    require_string(item.get("reviewer"), f"{path}.reviewer")
    require_enum(item.get("state"), WORKFLOW_STATES, f"{path}.state")
    require_string(item.get("verdict"), f"{path}.verdict")
    reviewed_sha = item.get("reviewed_sha")
    if reviewed_sha is not None:
        require_string(reviewed_sha, f"{path}.reviewed_sha")
    require_enum(
        item.get("head_state"),
        {"current", "stale", "unknown"},
        f"{path}.head_state",
    )
    state = item["state"]
    verdict = item["verdict"]
    if state == "awaiting_rereview" and verdict != "CHANGES_REQUESTED":
        raise ValueError(
            f"{path}.verdict must be CHANGES_REQUESTED when awaiting_rereview"
        )
    if state == "settled" and verdict == "CHANGES_REQUESTED":
        raise ValueError(
            f"{path} cannot be settled while the latest verdict requests changes"
        )
    sources = require_list(item.get("sources"), f"{path}.sources")
    if not sources:
        raise ValueError(f"{path}.sources must not be empty")
    for index, source in enumerate(sources):
        validate_source(source, f"{path}.sources[{index}]")
    return item


def validate_coverage_gap(gap: Any, path: str) -> dict[str, Any]:
    item = require_mapping(gap, path)
    require_string(item.get("id"), f"{path}.id")
    require_string(item.get("summary"), f"{path}.summary")
    require_enum(item.get("state"), COVERAGE_STATES, f"{path}.state")
    validate_source(item.get("source"), f"{path}.source")
    return item


def validate_unique_ids(items: list[dict[str, Any]], path: str) -> None:
    seen = set()
    for item in items:
        item_id = item["id"]
        if item_id in seen:
            raise ValueError(f"{path} contains duplicate id: {item_id}")
        seen.add(item_id)


def validate_unique_reviewers(items: list[dict[str, Any]]) -> None:
    seen = set()
    for item in items:
        reviewer = item["reviewer"]
        if reviewer in seen:
            raise ValueError(
                f"report.review_workflow contains duplicate reviewer: {reviewer}"
            )
        seen.add(reviewer)


def validate_source_consistency(findings: list[dict[str, Any]]) -> None:
    seen: dict[str, tuple[str, str, Any, str]] = {}
    for finding in findings:
        for source in finding["sources"]:
            key = source_key(source)
            state = (
                source["url"],
                source["author"],
                source.get("reviewed_sha"),
                source["thread_resolution"],
            )
            if key in seen and seen[key] != state:
                raise ValueError(
                    f"finding source {key} has inconsistent lifecycle metadata"
                )
            seen[key] = state


def validate_report(report: Any) -> dict[str, Any]:
    data = require_mapping(report, "report")
    if data.get("schema") != SCHEMA:
        raise ValueError(f"report.schema must equal {SCHEMA}")

    pr = require_mapping(data.get("pr"), "report.pr")
    if not isinstance(pr.get("number"), int):
        raise ValueError("report.pr.number must be an integer")
    require_string(pr.get("title"), "report.pr.title")
    require_string(pr.get("branch"), "report.pr.branch")
    require_string(pr.get("head_sha"), "report.pr.head_sha")
    require_string(
        pr.get("thread_resolution_state"), "report.pr.thread_resolution_state"
    )

    findings = [
        validate_finding(item, f"report.findings[{index}]")
        for index, item in enumerate(require_list(data.get("findings"), "report.findings"))
    ]
    actions = [
        validate_human_action(item, f"report.required_human_actions[{index}]")
        for index, item in enumerate(
            require_list(
                data.get("required_human_actions"),
                "report.required_human_actions",
            )
        )
    ]
    workflow = [
        validate_workflow_action(item, f"report.review_workflow[{index}]")
        for index, item in enumerate(
            require_list(data.get("review_workflow"), "report.review_workflow")
        )
    ]
    gaps = [
        validate_coverage_gap(item, f"report.coverage_gaps[{index}]")
        for index, item in enumerate(
            require_list(data.get("coverage_gaps"), "report.coverage_gaps")
        )
    ]
    validate_unique_ids(findings, "report.findings")
    validate_unique_ids(actions, "report.required_human_actions")
    validate_unique_ids(gaps, "report.coverage_gaps")
    validate_unique_reviewers(workflow)
    validate_source_consistency(findings)
    return data


def implementation_counts(report: dict[str, Any]) -> dict[str, int]:
    counts = {state: 0 for state in IMPLEMENTATION_STATES}
    for finding in report["findings"]:
        counts[finding["implementation"]["state"]] += 1
    return counts


def source_key(source: dict[str, Any]) -> str:
    return f"{source['kind']}:{source['id']}"


def response_gaps(report: dict[str, Any]) -> list[dict[str, Any]]:
    gaps: dict[str, dict[str, Any]] = {}
    summaries: dict[str, list[str]] = defaultdict(list)
    for finding in report["findings"]:
        for source in finding["sources"]:
            if (
                source["response"] != "unanswered"
                or source["acceptance"] != "pending"
            ):
                continue
            key = source_key(source)
            gaps[key] = source
            summaries[key].append(finding["summary"])

    result = []
    for key in sorted(gaps):
        result.append({"source": gaps[key], "findings": summaries[key]})
    return result


def thread_gaps(report: dict[str, Any]) -> list[dict[str, Any]]:
    gaps: dict[str, dict[str, Any]] = {}
    for finding in report["findings"]:
        for source in finding["sources"]:
            if source["thread_resolution"] not in {"unresolved", "unknown"}:
                continue
            gaps[source_key(source)] = source
    return [gaps[key] for key in sorted(gaps)]


def open_items(report: dict[str, Any], key: str, closed_state: str) -> list[Any]:
    return [item for item in report[key] if item["state"] != closed_state]


def plural(count: int, singular: str, plural_form: str | None = None) -> str:
    noun = singular if count == 1 else plural_form or f"{singular}s"
    return f"{count} {noun}"


def render_implementation_findings(
    lines: list[str], findings: list[dict[str, Any]]
) -> None:
    for severity in SEVERITY_ORDER:
        matching = [
            finding for finding in findings if finding["severity"] == severity
        ]
        if not matching:
            continue
        lines.extend(["", f"### {severity.title()}"])
        for finding in matching:
            state = finding["implementation"]["state"].upper()
            authors = sorted({source["author"] for source in finding["sources"]})
            lines.append(
                f"- **[{state}] {finding['summary']}** ({', '.join(authors)})"
            )
            details = finding["implementation"].get("details")
            if details:
                lines.append(f"  - Details: {details}")
            for evidence in finding["implementation"]["evidence"]:
                lines.append(f"  - Evidence: `{evidence}`")


def render_response_gaps(lines: list[str], gaps: list[dict[str, Any]]) -> None:
    if not gaps:
        return
    lines.extend(["", "## Artifact response coverage"])
    for gap in gaps:
        source = gap["source"]
        findings = "; ".join(gap["findings"])
        lines.append(
            f"- [{source['kind']} #{source['id']}]({source['url']}) "
            f"by `{source['author']}` — no source-specific disposition for: {findings}"
        )


def render_human_actions(lines: list[str], actions: list[dict[str, Any]]) -> None:
    if not actions:
        return
    lines.extend(["", "## Required human actions"])
    for action in actions:
        links = ", ".join(
            f"[{source['kind']} #{source['id']}]({source['url']})"
            for source in action["sources"]
        )
        lines.append(
            f"- **{action['summary']}** — owner: {action['owner']}; sources: {links}"
        )


def render_thread_gaps(lines: list[str], gaps: list[dict[str, Any]]) -> None:
    if not gaps:
        return
    lines.extend(["", "## Thread resolution"])
    for source in gaps:
        state = source["thread_resolution"].replace("_", " ")
        lines.append(
            f"- [{source['kind']} #{source['id']}]({source['url']}) "
            f"by `{source['author']}` — {state}"
        )


def render_workflow(
    lines: list[str],
    actions: list[dict[str, Any]],
    response_gap_keys: set[str],
) -> None:
    if not actions:
        return
    lines.extend(["", "## Reviewer acceptance"])
    for action in actions:
        reviewed_sha = action.get("reviewed_sha")
        reviewed_at = f"`{reviewed_sha}`" if reviewed_sha else "unknown reviewed SHA"
        blocked_sources = [
            source
            for source in action["sources"]
            if source_key(source) in response_gap_keys
        ]
        if blocked_sources:
            source_list = ", ".join(
                f"{source['kind']} #{source['id']}" for source in blocked_sources
            )
            readiness = f"blocked by undispositioned {source_list}"
        else:
            readiness = "ready for follow-up"
        lines.append(
            f"- `{action['reviewer']}` — {action['state'].replace('_', ' ')}; "
            f"{action['verdict']} at {reviewed_at} "
            f"({action['head_state']} relative to current head); {readiness}"
        )


def render_coverage_gaps(lines: list[str], gaps: list[dict[str, Any]]) -> None:
    if not gaps:
        return
    lines.extend(["", "## Review coverage gaps"])
    for gap in gaps:
        source = gap["source"]
        lines.append(
            f"- **{gap['summary']}** — "
            f"[{source['kind']} #{source['id']}]({source['url']})"
        )


def render_report(report: Any) -> str:
    data = validate_report(report)
    pr = data["pr"]
    counts = implementation_counts(data)
    gaps = response_gaps(data)
    gap_keys = {source_key(gap["source"]) for gap in gaps}
    threads = thread_gaps(data)
    human_actions = open_items(data, "required_human_actions", "satisfied")
    workflow = open_items(data, "review_workflow", "settled")
    coverage = open_items(data, "coverage_gaps", "closed")
    open_findings = [
        finding
        for finding in data["findings"]
        if finding["implementation"]["state"] != "addressed"
    ]

    lines = [
        f"## Review Findings Triage — #{pr['number']} {pr['title']}",
        "",
        (
            f"{counts['unaddressed']} need changes; "
            f"{counts['contested']} contested; "
            f"{counts['unverified']} unverified; "
            f"{counts['addressed']} addressed."
        ),
        (
            f"{len(data['findings'])} unique implementation findings assessed "
            f"at `{pr['head_sha']}`."
        ),
        f"Thread resolution state: {pr['thread_resolution_state']}.",
        (
            "Lifecycle: "
            f"{plural(len(gaps), 'source artifact response gap')}; "
            f"{plural(len(threads), 'thread resolution gap')}; "
            f"{plural(len(human_actions), 'required human action')}; "
            f"{plural(len(workflow), 'reviewer follow-up')}; "
            f"{plural(len(coverage), 'review coverage gap')}."
        ),
    ]

    if open_findings:
        lines.extend(["", "## Implementation findings still needing attention"])
        render_implementation_findings(lines, open_findings)
    elif gaps or threads or human_actions or workflow or coverage:
        lines.extend(
            [
                "",
                (
                    "**No implementation changes remain. Lifecycle actions are "
                    "still open; do not report this PR as fully addressed.**"
                ),
            ]
        )
    else:
        lines.extend(
            [
                "",
                (
                    f"All {len(data['findings'])} unique implementation findings "
                    "are addressed and no lifecycle actions remain."
                ),
            ]
        )

    render_response_gaps(lines, gaps)
    render_thread_gaps(lines, threads)
    render_human_actions(lines, human_actions)
    render_workflow(lines, workflow, gap_keys)
    render_coverage_gaps(lines, coverage)
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate and render normalized km-review-check triage JSON."
    )
    parser.add_argument("--input", required=True, type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        report = json.loads(args.input.read_text(encoding="utf-8"))
        print(render_report(report))
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"km-review-check: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
