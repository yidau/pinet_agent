"""Build attributable evidence for one BSSID from observations already collected."""

from collections import OrderedDict
from hashlib import sha256
import json
from threading import Lock
from time import monotonic

from .ap_observations import canonical_bssid, timestamp


def _digest(value):
    raw = json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(",", ":"))
    return sha256(raw.encode()).hexdigest()[:24]


def matches_ap(event, ap):
    address = ap["bssid"]
    ids = {ap.get("id"), *ap.get("kismet_device_ids", ())} - {None}
    macs = event.get("device_macs") or []
    return (event.get("device_id") in ids or event.get("ap_id") in ids or
            any(canonical_bssid(value) == address for value in (event.get("bssid"), *macs)))


def _evidence(kind, address, source, when, data):
    return {"id": kind + "-" + _digest([address, source, when, data]), "kind": kind,
            "source": source, "timestamp": when, "data": data}


def investigate(details, session_points, events, limitations):
    """Correlate only exact AP identities; a same-name neighbor is a separate subject."""
    ap = details["access_point"]
    bssid = ap["bssid"]
    samples = {}
    for point in [*details.get("observations", ()), *session_points]:
        when = timestamp(point.get("timestamp"))
        source = point.get("observation_source")
        if when is None or not source:
            continue
        key = when, source, point.get("sample_kind", "")
        # A session may add security or channel to an already-recorded measurement.
        samples[key] = {**point, **samples.get(key, {}), **{k: v for k, v in point.items() if v is not None}}
    signals = [_evidence("observation", bssid, key[1], key[0], samples[key]) for key in sorted(samples)]
    summary_row = _evidence("ap", bssid, ap.get("observation_source"), ap.get("last_seen"), ap)
    links = {}
    for event in events:
        if not matches_ap(event, ap):
            continue
        source = event.get("observation_source") or "kismet"
        row = _evidence("event", bssid, source, event.get("timestamp"), event)
        links[row["id"]] = row
    linked = sorted(links.values(), key=lambda row: (row["timestamp"] or 0, row["id"]))
    changes = {"channel": [], "security": []}
    previous = {}
    for row in signals:
        point = row["data"]
        for field in ("channel", "security"):
            value = point.get(field)
            if value in (None, "", "0"):
                continue
            key = row["source"], field
            if key in previous and previous[key] != value:
                changes[field].append(row["id"])
            previous[key] = value
    observed_sources = sorted({row["source"] for row in signals} | set(ap.get("observation_sources", [])))
    limits = list(dict.fromkeys(reason for reason in limitations if reason))
    if not any(row["source"] == "monitor_mode" for row in signals):
        limits.append("没有此接入点的监听模式采样。普通扫描只反映各采样时刻。")
    if not signals:
        limits.append("没有带来源和观测时间的历史采样。")
    summary = {"observation_count": len(signals), "event_count": len(linked),
               "channel_change_count": len(changes["channel"]), "security_change_count": len(changes["security"]),
               "sources": observed_sources, "last_observed_at": ap.get("last_seen"), "limitations": limits}
    alerts = [row["id"] for row in linked if row["source"] == "kismet"]
    concerns = []
    if alerts:
        concerns.append({"finding": "该接入点有相关 Kismet 事件，需检查事件类型和上下文。",
                         "evidence_count": len(alerts), "evidence_ids": alerts[-4:]})
    if changes["security"]:
        concerns.append({"finding": "同一来源记录的安全配置有变化，需与设备配置记录核对。",
                         "evidence_count": len(changes["security"]), "evidence_ids": changes["security"][-4:]})
    report = {
        "confirmed_facts": [{"bssid": bssid, "ssid": ap.get("ssid"), "evidence_id": summary_row["id"]}],
        "possible_concerns": concerns, "change_evidence_ids": changes["channel"][-4:] + changes["security"][-4:],
        "uncertainties": limits, "follow_up": ["核对接入点配置和事件发生时间。"] if concerns else [],
    }
    return {"ap_id": bssid, "access_point": ap, "activity_summary": summary,
            "evidence": [summary_row, *signals, *linked], "report": report, "limitations": limits}


class InvestigationPages:
    """Freeze a short-lived read snapshot so concurrent observations cannot shift evidence pages."""

    def __init__(self):
        self._snapshots = OrderedDict()
        self._lock = Lock()

    def store(self, request_id, investigation):
        key = _digest([request_id, investigation["evidence"], investigation["limitations"]])
        with self._lock:
            self._snapshots[key] = (monotonic(), request_id, investigation)
            self._snapshots.move_to_end(key)
            while len(self._snapshots) > 24:
                self._snapshots.popitem(last=False)
        return key

    def page(self, request_id, key, offset):
        with self._lock:
            record = self._snapshots.get(key)
        if record is None or record[1] != request_id or monotonic() - record[0] >= 300:
            raise KeyError(key)
        investigation = record[2]
        rows = investigation["evidence"]
        page = rows[offset:offset + 12]
        end = offset + len(page)
        return {k: investigation[k] for k in ("ap_id", "access_point", "activity_summary", "report", "limitations")} | {
            "source": "wireless_investigation", "snapshot_id": key, "offset": offset,
            "next_offset": end if end < len(rows) else None, "total": len(rows), "evidence": page,
        }
