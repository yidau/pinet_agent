"""One bounded, operator-started wireless observation session per MCP process."""

from collections import defaultdict, deque
from dataclasses import dataclass, field
import logging
from threading import Event, RLock, Thread
import time
from uuid import uuid4

from .ap_observations import canonical_bssid, known_channel, timestamp
from .kismet_adapter import KismetError
from .phone_radio import RadioError, session_radio


class MonitoringError(Exception):
    def __init__(self, reason, code="MONITORING_DEGRADED"):
        super().__init__(reason)
        self.reason = reason
        self.code = code


@dataclass
class _Run:
    source: str
    interval: int
    duration: int
    id: str = field(default_factory=lambda: uuid4().hex)
    started: float = field(default_factory=time.time)
    begin: float = field(default_factory=time.monotonic)
    cancel: Event = field(default_factory=Event)
    state: str = "running"
    reason: str = ""
    ended: float | None = None
    elapsed: float | None = None
    count: int = 0
    baseline: int = 0
    channel_changes: int = 0
    security_changes: int = 0
    truncated: bool = False
    event_seq: int = 0
    event_counts: dict = field(default_factory=lambda: defaultdict(int))
    aps: dict = field(default_factory=dict)
    points: dict = field(default_factory=lambda: defaultdict(list))
    events: deque = field(default_factory=lambda: deque(maxlen=2048))

    def change(self, kind, ap, when, previous=None, current=None):
        self.event_seq += 1
        self.event_counts[ap["bssid"]] += 1
        self.events.append({"id": f"{self.id}:event:{self.event_seq}", "type": kind,
                            "timestamp": when, "bssid": ap["bssid"], "ssid": ap.get("ssid"),
                            "observation_source": self.source, "previous": previous, "current": current})

    def record(self, snapshot):
        self.truncated |= bool(snapshot.get("truncated"))
        for ap in snapshot["access_points"]:
            addr = canonical_bssid(ap.get("bssid") or ap.get("mac"))
            when = timestamp(ap.get("observed_at")) or timestamp(ap.get("last_seen"))
            if addr is None or when is None:
                self.truncated = True
                continue
            # Kismet's live-source device view can contain old historical devices.
            # Kismet's last_seen has whole-second resolution. Only count device
            # sightings whose source timestamp falls inside this session.
            if self.source == "monitor_mode" and when < int(self.started):
                continue
            previous = self.aps.get(addr)
            if previous is None and len(self.aps) >= 512:
                self.truncated = True
                continue
            if previous and when <= previous["last_seen"]:
                continue
            signal = ap.get("rssi_dbm")
            if ap.get("rssi_observed_at") not in (None, when):
                signal = None
            point = {"id": f"{self.id}:{addr}:{when}", "timestamp": when, "rssi_dbm": signal,
                     "channel": known_channel(ap), "security": ap.get("security"), "observation_source": self.source}
            entry = {**ap, "bssid": addr, "ssid": ap.get("ssid", ap.get("name")), "last_seen": when,
                     "rssi_dbm": signal, "observation_source": self.source, "observation_sources": [self.source]}
            self.aps[addr] = entry
            self.points[addr].append(point)
            if previous is None and self.count:
                self.change("new_ap", entry, when)
            if previous is not None:
                old_ch = known_channel(previous)
                if old_ch and point["channel"] and old_ch != point["channel"]:
                    self.channel_changes += 1
                    self.change("channel_change", entry, when, old_ch, point["channel"])
                old_sec = previous.get("security")
                if old_sec and point["security"] and old_sec != point["security"]:
                    self.security_changes += 1
                    self.change("security_change", entry, when, old_sec, point["security"])
        if self.count == 0:
            self.baseline = len(self.aps)
        self.count += 1


class MonitoringSession:
    def __init__(self, probe, sample):
        self._probe = probe
        self._sample = sample
        self._lock = RLock()
        self._run = None
        self._worker = None

    def availability(self, sources):
        try:
            self._probe(sources)
            return "AVAILABLE", ""
        except MonitoringError as error:
            return "DEGRADED", error.reason

    def _status(self):
        r = self._run
        elapsed = (time.monotonic() - r.begin if r.elapsed is None else r.elapsed) if r else 0
        return {"session_id": r.id if r else None, "state": r.state if r else "idle",
                "observation_source": r.source if r else None, "reason": r.reason if r else "",
                "started_at": r.started if r else None, "ended_at": r.ended if r else None,
                "elapsed_seconds": min(r.duration, int(elapsed)) if r else 0,
                "interval_seconds": r.interval if r else 30, "duration_seconds": r.duration if r else 600,
                "scan_count": r.count if r else 0, "ap_count": len(r.aps) if r else 0,
                "new_ap_count": len(r.aps) - r.baseline if r else 0,
                "recent_events": list(r.events)[-8:] if r else [],
                "summary": {"baseline_ap_count": r.baseline if r else 0,
                            "new_ap_count": len(r.aps) - r.baseline if r else 0,
                            "channel_change_count": r.channel_changes if r else 0,
                            "security_change_count": r.security_changes if r else 0,
                            "truncated": r.truncated if r else False}}

    def status(self):
        with self._lock:
            return self._status()

    def start(self, confirm, interval_seconds=30, duration_seconds=600):
        if confirm is not True or type(interval_seconds) is not int or not 30 <= interval_seconds <= 3600 or (
                type(duration_seconds) is not int or not 1 <= duration_seconds <= 3600):
            raise MonitoringError("请确认开始观测，采样间隔为 30–3600 秒，持续时间为 1–3600 秒。", "INVALID_ARGUMENT")
        with self._lock:
            if self._worker and self._worker.is_alive():
                raise MonitoringError("设备正在执行一个无线观测任务。", "MONITORING_CONFLICT")
            source = self._probe()
            run = _Run(source, interval_seconds, duration_seconds)
            worker = Thread(target=self._observe, args=(run,), name="pocketnet-observation", daemon=True)
            worker.start()
            self._run, self._worker = run, worker
            return self._status()

    def stop(self, confirm):
        if confirm is not True:
            raise MonitoringError("请确认停止本次观测。", "INVALID_ARGUMENT")
        with self._lock:
            if self._run and self._run.state == "running":
                self._run.state = "stopping"
                self._run.cancel.set()
            return self._status()

    def close(self):
        self.stop(True)
        if self._worker:
            self._worker.join(timeout=8)

    def _observe(self, r):
        deadline = r.begin + r.duration
        state, reason = "completed", ""
        try:
            while not r.cancel.is_set() and time.monotonic() < deadline:
                cycle_start = time.monotonic()
                result = self._sample(r.source, r.cancel, deadline)
                with self._lock:
                    if r.cancel.is_set() or time.monotonic() >= deadline:
                        break
                    r.record(result)
                next_tick = min(deadline, cycle_start + r.interval)
                r.cancel.wait(max(0, next_tick - time.monotonic()))
        except MonitoringError as error:
            state, reason = "degraded", error.reason
        except Exception:
            logging.getLogger(__name__).exception("Wireless observation session failed")
            state, reason = "degraded", "无线观测读取失败。"
        finally:
            with self._lock:
                r.state = "stopped" if r.cancel.is_set() and not reason else state
                r.reason = reason
                r.ended, r.elapsed = time.time(), time.monotonic() - r.begin

    def access_point(self, bssid):
        with self._lock:
            return self._run.aps.get(canonical_bssid(bssid)) if self._run else None

    def evidence(self, bssid):
        # The operator can start another session while an investigation is in progress.
        with self._lock:
            return {"access_point": self.access_point(bssid), "history": self.history(bssid),
                    "events": self.events(bssid)}

    def history(self, bssid=None):
        with self._lock:
            r = self._run
            if not r:
                return {"history": [], "truncated": False}
            selected = [canonical_bssid(bssid)] if bssid else list(r.points)[:32]
            truncated = r.truncated or (not bssid and (len(r.points) > 32 or any(len(v) > 8 for v in r.points.values())))
            return {"session_id": r.id, "source": r.source, "truncated": truncated,
                    "history": [{"id": addr, "bssid": addr, "name": r.aps[addr].get("ssid"),
                                 "observation_source": r.source, "samples": list(r.points[addr] if bssid else r.points[addr][-8:])}
                                for addr in selected if addr in r.points]}

    def events(self, bssid=None):
        with self._lock:
            r = self._run
            if not r:
                return {"events": [], "total": 0, "truncated": False}
            address = canonical_bssid(bssid)
            hits = [e for e in r.events if bssid is None or e["bssid"] == address]
            total = r.event_seq if bssid is None else r.event_counts.get(address, 0)
            selected = hits[-128:] if bssid is None else hits
            return {"session_id": r.id, "source": r.source, "events": selected,
                    "total": total, "truncated": r.truncated or total > len(selected)}


def monitoring_for(adapter, scan_reader):
    from .ap_observations import ApObservations
    from .managed_scan import empty_state
    from .wireless_service import WifiView

    observations = ApObservations()
    not_supplied = object()

    def sources_now():
        try:
            return adapter.get_datasources()
        except KismetError as error:
            raise MonitoringError("Kismet 数据源不可用。") from error

    def probe(sources=not_supplied):
        if sources is not_supplied:
            sources = sources_now()
        if sources is None:
            raise MonitoringError("Kismet 数据源不可用。")
        if any(s["driver"] == "linuxwifi" and s["running"] and not s["paused"] and not s["error"] for s in sources):
            return "monitor_mode"
        try:
            session_radio("session-check")
        except RadioError as error:
            raise MonitoringError(str(error)) from error
        return "managed_scan"

    def sample(source, cancel, deadline):
        if source == "monitor_mode":
            view = WifiView(adapter, sources_now(), empty_state(""), observations)
            if view.monitor["status"] != "AVAILABLE":
                raise MonitoringError(view.monitor["reason"])
            return {"access_points": view.aps, "truncated": view.scope["truncated"]}

        due = min(time.monotonic() + 30, deadline)
        try:
            if cancel.is_set() or time.monotonic() >= due:
                return {"access_points": []}
            invocation = session_radio("session-scan")
            finished = False
            try:
                while not cancel.is_set() and time.monotonic() < due:
                    report = scan_reader()
                    if (report.get("scan_mode") == "monitoring" and report.get("scan_id") == invocation
                            and not report.get("in_progress")):
                        finished = True
                        if report["status"] != "AVAILABLE":
                            raise MonitoringError(report["reason"])
                        return report
                    cancel.wait(min(.3, max(0, due - time.monotonic())))
            finally:
                if not finished:
                    session_radio("session-stop", invocation)
            if not cancel.is_set() and time.monotonic() < deadline:
                raise MonitoringError("扫描助手未在时限内返回本轮结果。")
            return {"access_points": []}
        except RadioError as error:
            raise MonitoringError(str(error)) from error

    return MonitoringSession(probe, sample)
