#!/usr/bin/env python3
"""Validate the content-free physical local-speech cycle report."""
import json
import argparse
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("report", type=Path)
parser.add_argument("--deepseek", action="store_true", help="also require one real DeepSeek reply and resumed input")
args = parser.parse_args()
report = json.loads(args.report.read_text())
engine = report["engine"]
state = report.get("stateAtCompletion") or report["state"]
if engine["outputFinishes"] > 0 and not state["synthesizerSpeaking"]:
    assert not state["outputPending"], "completed reading still blocks microphone handoff"
assert report["status"] == "complete", "diagnostic did not finish"
assert report["cyclePassed"] and report["completedCycles"] == 3, "microphone did not resume in all three cycles"
assert engine["outputStarts"] >= 3 and engine["outputFinishes"] >= 3, "system reading did not complete"
assert engine["recognitionStartsAfterOutput"] >= 3, "recognition did not restart after each reply"
assert engine["microphoneCallbacksAfterOutput"] >= 15, "no sustained microphone capture after replies"
assert engine["conversionFailures"] == 0, "audio conversion failed"
assert report["disconnected"] and report["inputStoppedAfterDisconnect"], "input was not released"
if args.deepseek:
    assert report.get("provider") == "deepSeek", "wrong provider"
    assert report.get("modelReplies") == 1, "expected one real synthetic reply"
    assert report.get("modelReplyResumedInput") is True, "microphone did not resume after the model reply"
print("PASS: three reading/recognition/microphone-resume cycles; input released.")
