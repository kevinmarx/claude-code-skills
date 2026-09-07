import copy
import json
import sys
import unittest
from pathlib import Path


SKILL_DIR = Path(__file__).resolve().parents[1]
FIXTURE_PATH = SKILL_DIR / "testdata" / "pr-12131-lifecycle.json"
sys.path.insert(0, str(SKILL_DIR))

import render_triage


class RenderTriageTests(unittest.TestCase):
    def setUp(self):
        self.report = json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))

    def test_pr_12131_fixture_preserves_open_lifecycle_axes(self):
        output = render_triage.render_report(self.report)

        self.assertIn(
            "0 need changes; 0 contested; 0 unverified; 5 addressed.", output
        )
        self.assertIn("3 source artifact response gaps", output)
        self.assertIn("0 thread resolution gaps", output)
        self.assertIn("2 required human actions", output)
        self.assertIn("3 reviewer follow-ups", output)
        self.assertIn("1 review coverage gap", output)
        self.assertIn(
            "No implementation changes remain. Lifecycle actions are still open",
            output,
        )
        self.assertIn("review #185359086", output)
        self.assertIn("Obtain HA-SECURITY sign-off", output)
        self.assertIn("Copilot review setup failed before analysis", output)
        self.assertIn(
            "edpiva` — awaiting rereview; CHANGES_REQUESTED", output
        )
        self.assertIn(
            "blocked by undispositioned review #185359086", output
        )
        self.assertIn("carmen-pfeil` — awaiting acknowledgement", output)
        self.assertIn("ready for follow-up", output)

    def test_duplicate_finding_sources_count_as_artifacts_once(self):
        gaps = render_triage.response_gaps(
            render_triage.validate_report(self.report)
        )

        self.assertEqual(
            ["comment:236906881", "review:185337886", "review:185359086"],
            [render_triage.source_key(gap["source"]) for gap in gaps],
        )

    def test_full_all_clear_requires_every_axis_to_be_closed(self):
        report = copy.deepcopy(self.report)
        for finding in report["findings"]:
            for source in finding["sources"]:
                source["response"] = "author_dispositioned"
                source["acceptance"] = "accepted"
        for action in report["required_human_actions"]:
            action["state"] = "satisfied"
        for action in report["review_workflow"]:
            action["state"] = "settled"
            action["verdict"] = "APPROVED"
            action["reviewed_sha"] = report["pr"]["head_sha"]
            action["head_state"] = "current"
        for gap in report["coverage_gaps"]:
            gap["state"] = "closed"

        output = render_triage.render_report(report)

        self.assertIn(
            "All 5 unique implementation findings are addressed and no "
            "lifecycle actions remain.",
            output,
        )
        self.assertNotIn("do not report this PR as fully addressed", output)

    def test_resolved_thread_does_not_hide_missing_implementation(self):
        report = copy.deepcopy(self.report)
        finding = report["findings"][0]
        finding["implementation"] = {
            "state": "unaddressed",
            "evidence": [],
            "details": "The requested source contract is still absent.",
        }
        finding["sources"].append(
            {
                "kind": "thread",
                "id": "PRRT_example",
                "url": "https://microsoft.ghe.com/example/thread",
                "author": "dspektor",
                "reviewed_sha": self.report["pr"]["head_sha"],
                "response": "unanswered",
                "acceptance": "pending",
                "thread_resolution": "resolved",
            }
        )

        output = render_triage.render_report(report)

        self.assertIn("1 need changes", output)
        self.assertIn(
            "[UNADDRESSED] Make Redis Cluster claim CAS executable", output
        )

    def test_addressed_implementation_requires_evidence(self):
        report = copy.deepcopy(self.report)
        report["findings"][0]["implementation"]["evidence"] = []

        with self.assertRaisesRegex(ValueError, "evidence is required"):
            render_triage.validate_report(report)

    def test_partial_disposition_of_multi_finding_artifact_is_preserved(self):
        report = copy.deepcopy(self.report)
        report["findings"][1]["sources"][0]["response"] = "author_dispositioned"

        gaps = render_triage.response_gaps(render_triage.validate_report(report))
        source_gap = next(
            gap
            for gap in gaps
            if render_triage.source_key(gap["source"]) == "review:185337886"
        )

        self.assertEqual(
            ["Make Redis Cluster claim CAS executable"],
            source_gap["findings"],
        )

    def test_thread_resolution_does_not_supply_artifact_response(self):
        report = copy.deepcopy(self.report)
        report["findings"][0]["sources"].append(
            {
                "kind": "thread",
                "id": "PRRT_example",
                "url": "https://microsoft.ghe.com/example/thread",
                "author": "dspektor",
                "reviewed_sha": self.report["pr"]["head_sha"],
                "response": "unanswered",
                "acceptance": "pending",
                "thread_resolution": "resolved",
            }
        )

        gaps = render_triage.response_gaps(render_triage.validate_report(report))

        self.assertIn(
            "thread:PRRT_example",
            [render_triage.source_key(gap["source"]) for gap in gaps],
        )

    def test_unresolved_thread_remains_open_after_author_disposition(self):
        report = copy.deepcopy(self.report)
        report["findings"][0]["sources"].append(
            {
                "kind": "thread",
                "id": "PRRT_unresolved",
                "url": "https://microsoft.ghe.com/example/unresolved-thread",
                "author": "dspektor",
                "reviewed_sha": self.report["pr"]["head_sha"],
                "response": "author_dispositioned",
                "acceptance": "pending",
                "thread_resolution": "unresolved",
            }
        )

        output = render_triage.render_report(report)

        self.assertIn("1 thread resolution gap", output)
        self.assertIn("thread #PRRT_unresolved", output)

    def test_unknown_review_metadata_remains_renderable(self):
        report = copy.deepcopy(self.report)
        report["review_workflow"][0]["reviewed_sha"] = None
        report["review_workflow"][0]["head_state"] = "unknown"

        output = render_triage.render_report(report)

        self.assertIn("unknown reviewed SHA", output)
        self.assertIn("unknown relative to current head", output)

    def test_changes_requested_cannot_be_settled_without_later_verdict(self):
        report = copy.deepcopy(self.report)
        report["review_workflow"][0]["state"] = "settled"

        with self.assertRaisesRegex(
            ValueError, "cannot be settled while the latest verdict requests changes"
        ):
            render_triage.validate_report(report)


if __name__ == "__main__":
    unittest.main()
