#!/usr/bin/env python3
"""Antigravity v6.0 — Parallel Multi-Model CLI Wave Runner.

Khởi tạo song song các tiến trình `agy` độc lập cho một wave công việc đã chốt
contract, gắn chính xác từng `--model <slug>` đã xác minh qua `agy models` và
cô lập mỗi task trong một Git worktree riêng `agy/<run>/<task>`.

Nguyên tắc an toàn (AGENTS.md §2.1, §4, §10):
- KHÔNG dùng `--dangerously-skip-permissions`.
- Mặc định chạy `--mode plan` (chỉ đọc/phân tích). Chỉ cho phép sửa khi có cả
  cờ `--allow-edits` trên dòng lệnh lẫn `"mode": "edit"` trong JSON của task
  (chạy `--mode accept-edits --sandbox`).
- KHÔNG tự động merge, commit, push hay xóa nhánh của người dùng; giữ nguyên
  worktree và ghi `summary.json` để Engineering Lead kiểm tra diff & chạy gate.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime as dt
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from typing import Any


@dataclass(frozen=True)
class WaveTaskSpec:
    id: str
    role: str
    model: str
    prompt: str
    mode: str = "plan"
    owned_paths: list[str] | None = None
    readonly_paths: list[str] | None = None


@dataclass
class WaveTaskResult:
    task_id: str
    role: str
    model: str
    mode: str
    branch: str
    worktree_path: str
    base_commit: str
    exit_code: int
    duration_seconds: float
    stdout_log: str
    stderr_log: str
    status: str


def _resolve_agy_binary(explicit_bin: str | None) -> str:
    if explicit_bin:
        candidate = pathlib.Path(explicit_bin).expanduser()
        if candidate.is_file():
            return str(candidate)
        raise FileNotFoundError(f"Không tìm thấy agy binary tại: {explicit_bin}")

    in_path = shutil.which("agy") or shutil.which("agy.exe")
    if in_path:
        return in_path

    home = pathlib.Path.home()
    fallback_candidates = [
        home / ".gemini" / "bin" / "agy.exe",
        home / ".gemini" / "bin" / "agy",
    ]
    for cand in fallback_candidates:
        if cand.is_file():
            return str(cand)

    raise FileNotFoundError(
        "Không tìm thấy CLI `agy` trong PATH hoặc ~/.gemini/bin/. "
        "Hãy kiểm tra cài đặt Antigravity CLI trước khi chạy runner."
    )


def _run_checked(cmd: list[str], cwd: pathlib.Path) -> str:
    proc = subprocess.run(
        cmd,
        cwd=str(cwd),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"Lệnh thất bại ({proc.returncode}): {' '.join(cmd)}\n{proc.stderr.strip()}"
        )
    return proc.stdout.strip()


def _fetch_available_models(agy_bin: str, cwd: pathlib.Path) -> set[str]:
    proc = subprocess.run(
        [agy_bin, "models"],
        cwd=str(cwd),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=45,
        check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"Không lấy được danh sách `agy models` (exit {proc.returncode}):\n"
            f"{proc.stderr.strip() or proc.stdout.strip()}"
        )
    models: set[str] = set()
    for raw_line in proc.stdout.splitlines():
        line = raw_line.strip()
        if not line or line.lower().startswith("fetching"):
            continue
        slug = line.split()[0].strip()
        if slug:
            models.add(slug)
    return models


def _sanitize_token(raw: str) -> str:
    cleaned = re.sub(r"[^a-zA-Z0-9._-]+", "-", raw.strip())
    cleaned = cleaned.strip("-")
    if not cleaned:
        raise ValueError(f"Định danh không hợp lệ: {raw!r}")
    return cleaned


def _load_tasks(json_path: pathlib.Path) -> list[WaveTaskSpec]:
    payload = json.loads(json_path.read_text(encoding="utf-8"))
    raw_tasks: list[dict[str, Any]]
    if isinstance(payload, dict) and isinstance(payload.get("tasks"), list):
        raw_tasks = payload["tasks"]
    elif isinstance(payload, list):
        raw_tasks = payload
    else:
        raise ValueError("File JSON phải là mảng task hoặc object có khóa 'tasks'.")

    seen_ids: set[str] = set()
    specs: list[WaveTaskSpec] = []
    for item in raw_tasks:
        tid = _sanitize_token(str(item["id"]))
        if tid in seen_ids:
            raise ValueError(f"Trùng task id trong cùng wave: {tid}")
        seen_ids.add(tid)
        mode = str(item.get("mode", "plan")).strip().lower()
        if mode not in {"plan", "edit"}:
            raise ValueError(f"Task {tid}: mode chỉ nhận 'plan' hoặc 'edit' (nhận {mode!r}).")
        specs.append(
            WaveTaskSpec(
                id=tid,
                role=str(item.get("role", "worker")).strip(),
                model=str(item["model"]).strip(),
                prompt=str(item["prompt"]).strip(),
                mode=mode,
                owned_paths=list(item.get("owned_paths") or []),
                readonly_paths=list(item.get("readonly_paths") or []),
            )
        )
    if not specs:
        raise ValueError("Danh sách task rỗng.")
    return specs


def _validate_single_writer(tasks: list[WaveTaskSpec]) -> None:
    owner_by_path: dict[str, str] = {}
    for task in tasks:
        if task.mode != "edit":
            continue
        for raw_p in task.owned_paths or []:
            norm = pathlib.PurePosixPath(raw_p.replace("\\", "/")).as_posix().strip("/")
            if not norm:
                continue
            prev = owner_by_path.get(norm)
            if prev and prev != task.id:
                raise ValueError(
                    f"Vi phạm single-writer: đường dẫn '{norm}' được giao cho cả '{prev}' và '{task.id}'."
                )
            owner_by_path[norm] = task.id


def _build_worker_prompt(task: WaveTaskSpec) -> str:
    header_lines = [
        f"[ANTIGRAVITY v6.0 WAVE WORKER | task_id={task.id} | role={task.role} | mode={task.mode}]",
        "Đọc AGENTS.md ở thư mục gốc nếu có. Tuân thủ nghiêm ngặt phạm vi đường dẫn dưới đây.",
    ]
    if task.owned_paths:
        header_lines.append(f"Paths được phép ghi (single-writer): {', '.join(task.owned_paths)}")
    else:
        header_lines.append("Paths được phép ghi: KHÔNG CÓ (chỉ đọc và phân tích).")
    if task.readonly_paths:
        header_lines.append(f"Paths tham chiếu chỉ đọc: {', '.join(task.readonly_paths)}")
    header_lines.append(
        "Bàn giao cuối phản hồi gồm: task_id, status (DONE/PARTIAL/BLOCKED/FAILED), "
        "danh sách file thay đổi, lệnh kiểm tra đã chạy + exit code, giả định và rủi ro."
    )
    header_lines.append("---")
    header_lines.append(task.prompt)
    return "\n".join(header_lines)


def _execute_single_task(
    *,
    agy_bin: str,
    repo_root: pathlib.Path,
    run_id: str,
    run_dir: pathlib.Path,
    base_commit: str,
    task: WaveTaskSpec,
    allow_edits: bool,
    timeout_sec: int,
) -> WaveTaskResult:
    effective_mode = "accept-edits" if (allow_edits and task.mode == "edit") else "plan"
    branch_name = f"agy/{run_id}/{task.id}"
    worktree_dir = run_dir / "worktrees" / task.id
    logs_dir = run_dir / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)
    worktree_dir.parent.mkdir(parents=True, exist_ok=True)

    stdout_path = logs_dir / f"{task.id}.stdout.log"
    stderr_path = logs_dir / f"{task.id}.stderr.log"
    prompt_path = logs_dir / f"{task.id}.prompt.txt"

    full_prompt = _build_worker_prompt(task)
    prompt_path.write_text(full_prompt, encoding="utf-8")

    _run_checked(
        ["git", "worktree", "add", "-b", branch_name, str(worktree_dir), base_commit],
        cwd=repo_root,
    )

    cmd = [
        agy_bin,
        "-p",
        full_prompt,
        "--model",
        task.model,
        "--mode",
        effective_mode,
        "--output-format",
        "text",
        "--print-timeout",
        f"{timeout_sec}s",
    ]
    if effective_mode == "accept-edits":
        cmd.append("--sandbox")

    started = time.perf_counter()
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(worktree_dir),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout_sec + 30,
            check=False,
        )
        elapsed = round(time.perf_counter() - started, 3)
        stdout_path.write_text(proc.stdout, encoding="utf-8")
        stderr_path.write_text(proc.stderr, encoding="utf-8")
        exit_code = proc.returncode
        status = "DONE" if exit_code == 0 else "FAILED"
    except subprocess.TimeoutExpired as exc:
        elapsed = round(time.perf_counter() - started, 3)
        stdout_path.write_text(exc.stdout or "", encoding="utf-8")
        stderr_path.write_text(
            f"Timeout sau {timeout_sec}s.\n{exc.stderr or ''}", encoding="utf-8"
        )
        exit_code = 124
        status = "TIMEOUT"

    return WaveTaskResult(
        task_id=task.id,
        role=task.role,
        model=task.model,
        mode=effective_mode,
        branch=branch_name,
        worktree_path=str(worktree_dir),
        base_commit=base_commit,
        exit_code=exit_code,
        duration_seconds=elapsed,
        stdout_log=str(stdout_path),
        stderr_log=str(stderr_path),
        status=status,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Antigravity v6.0 Parallel Multi-Model CLI Wave Runner"
    )
    parser.add_argument(
        "--tasks",
        required=True,
        help="Đường dẫn tới file JSON khai báo các task độc lập của wave.",
    )
    parser.add_argument(
        "--jobs",
        type=int,
        default=3,
        help="Số tiến trình worker chạy đồng thời tối đa (mặc định: 3).",
    )
    parser.add_argument(
        "--base",
        default=None,
        help="Commit/ref cơ sở cho các Git worktree (bắt buộc nếu repo gốc đang có thay đổi chưa commit).",
    )
    parser.add_argument(
        "--allow-edits",
        action="store_true",
        help="Cho phép các task có mode='edit' chạy ở chế độ accept-edits kèm --sandbox.",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=900,
        help="Giới hạn thời gian mỗi tiến trình tính bằng giây (mặc định: 900).",
    )
    parser.add_argument(
        "--agy-bin",
        default=None,
        help="Đường dẫn tùy chọn tới thực thi `agy`.",
    )
    parser.add_argument(
        "--output-dir",
        default=None,
        help="Thư mục lưu worktree và log của lần chạy (mặc định: .agy-runs/<run_id> ngoài git index).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Chỉ kiểm tra schema JSON, single-writer, Git snapshot và danh sách model từ `agy models` mà không tạo tiến trình worker.",
    )
    args = parser.parse_args(argv)

    if args.jobs < 1 or args.jobs > 8:
        print("Lỗi: --jobs phải nằm trong khoảng 1..8.", file=sys.stderr)
        return 2

    tasks_file = pathlib.Path(args.tasks).resolve()
    if not tasks_file.is_file():
        print(f"Lỗi: Không tìm thấy file tasks: {tasks_file}", file=sys.stderr)
        return 2

    tasks = _load_tasks(tasks_file)
    _validate_single_writer(tasks)

    edit_tasks = [t.id for t in tasks if t.mode == "edit"]
    if edit_tasks and not args.allow_edits and not args.dry_run:
        print(
            f"Chặn an toàn: Các task {edit_tasks} đặt mode='edit' nhưng chưa truyền --allow-edits.",
            file=sys.stderr,
        )
        return 2

    repo_root = pathlib.Path(
        _run_checked(["git", "rev-parse", "--show-toplevel"], cwd=pathlib.Path.cwd())
    )
    dirty_status = _run_checked(["git", "status", "--porcelain"], cwd=repo_root)
    if dirty_status and not args.base and not args.dry_run:
        print(
            "Chặn bảo vệ code chưa commit: Working tree hiện có thay đổi cục bộ.\n"
            "Hãy truyền rõ `--base HEAD` nếu muốn chạy wave đọc/thử nghiệm trên commit HEAD "
            "(các thay đổi chưa commit ở repo gốc vẫn được giữ nguyên 100%).",
            file=sys.stderr,
        )
        return 2

    base_ref = args.base or "HEAD"
    base_commit = _run_checked(["git", "rev-parse", base_ref], cwd=repo_root)
    agy_bin = _resolve_agy_binary(args.agy_bin)
    available_models = _fetch_available_models(agy_bin, repo_root)

    missing_models = sorted({t.model for t in tasks if t.model not in available_models})
    if missing_models:
        print(
            "Dừng trước khi tạo worker (strict model pinning): Các model sau không có trong `agy models` của tài khoản:\n"
            + "\n".join(f"  - {m}" for m in missing_models),
            file=sys.stderr,
        )
        return 3

    run_id = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    base_runs_dir = (
        pathlib.Path(args.output_dir).resolve()
        if args.output_dir
        else (pathlib.Path.home() / ".gemini" / "tmp" / "agy-runs" / repo_root.name / run_id)
    )

    if args.dry_run:
        summary = {
            "dry_run": True,
            "agy_binary": agy_bin,
            "repo_root": str(repo_root),
            "base_commit": base_commit,
            "dirty_working_tree_preserved": bool(dirty_status),
            "jobs": args.jobs,
            "verified_models": sorted({t.model for t in tasks}),
            "tasks": [asdict(t) for t in tasks],
        }
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        return 0

    base_runs_dir.mkdir(parents=True, exist_ok=True)
    wave_start = time.perf_counter()
    results: list[WaveTaskResult] = []

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        future_map = {
            pool.submit(
                _execute_single_task,
                agy_bin=agy_bin,
                repo_root=repo_root,
                run_id=run_id,
                run_dir=base_runs_dir,
                base_commit=base_commit,
                task=t,
                allow_edits=args.allow_edits,
                timeout_sec=args.timeout,
            ): t
            for t in tasks
        }
        for fut in concurrent.futures.as_completed(future_map):
            results.append(fut.result())

    results.sort(key=lambda r: r.task_id)
    wall_seconds = round(time.perf_counter() - wave_start, 3)
    summary_payload = {
        "run_id": run_id,
        "repo_root": str(repo_root),
        "base_commit": base_commit,
        "jobs": args.jobs,
        "allow_edits": args.allow_edits,
        "wall_clock_seconds": wall_seconds,
        "sum_worker_seconds": round(sum(r.duration_seconds for r in results), 3),
        "results": [asdict(r) for r in results],
    }
    summary_path = base_runs_dir / "summary.json"
    summary_path.write_text(
        json.dumps(summary_payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(f"Hoàn tất wave {run_id} trong {wall_seconds}s. Summary: {summary_path}")
    return 0 if all(r.exit_code == 0 for r in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
