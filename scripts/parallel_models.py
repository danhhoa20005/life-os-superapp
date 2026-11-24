#!/usr/bin/env python3
"""Antigravity v6.1 — Parallel Multi-Model CLI Wave Runner (6-Ban Architecture).

Khởi tạo song song các tiến trình `agy` độc lập cho một wave công việc đã chốt
contract, gắn chính xác từng `--model <slug>` đã xác minh qua `agy models` và
cô lập mỗi task trong một Git worktree riêng `agy/<run>/<task>`.

Nguyên tắc an toàn (AGENTS.md v6.1 §2.1, §4, §10):
- KHÔNG dùng `--dangerously-skip-permissions`.
- Mặc định chạy `--mode plan` (chỉ đọc/phân tích). Chỉ cho phép sửa khi có cả
  cờ `--allow-edits` trên dòng lệnh lẫn `"mode": "edit"` trong JSON của task
  (chạy `--mode accept-edits --sandbox`).
- Hậu kiểm phạm vi sau khi chạy: thu `git status --porcelain` trong từng
  worktree, tự xuất `logs/<task_id>.diff.patch` khi có thay đổi và đối chiếu
  với `owned_paths` (đặt `status = "SCOPE_VIOLATION"`, `exit_code = 4` nếu vượt
  quyền ghi).
- Hỗ trợ `--cleanup-clean-worktrees` để tự động dọn worktree & nhánh tạm của
  các task hoàn thành sạch (`exit_code == 0` và không phát sinh file thay đổi),
  giữ nguyên `logs/` và `summary.json`.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime as dt
import json
import pathlib
import re
import shutil
import subprocess
import sys
import threading
import time
from dataclasses import asdict, dataclass, field
from typing import Any


KNOWN_ROLES: set[str] = {
    "architect",
    "developer",
    "qa",
    "creative",
    "release",
    "worker",
}


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
    changed_files: list[str] = field(default_factory=list)
    scope_violations: list[str] = field(default_factory=list)
    diff_patch: str | None = None
    worktree_cleaned: bool = False


def _normalize_rel_path(raw_path: str) -> str:
    cleaned = raw_path.strip().strip('"').replace("\\", "/")
    while cleaned.startswith("./"):
        cleaned = cleaned[2:]
    cleaned = cleaned.strip("/")
    if not cleaned or cleaned == ".":
        return ""
    norm = pathlib.PurePosixPath(cleaned).as_posix().strip("/")
    return "" if norm == "." else norm


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
        role = str(item.get("role", "worker")).strip() or "worker"
        if role not in KNOWN_ROLES:
            print(
                f"Cảnh báo: Task {tid} dùng role {role!r} ngoài tập chuẩn "
                f"{sorted(KNOWN_ROLES)}; vẫn giữ nguyên để tương thích ngược.",
                file=sys.stderr,
            )
        mode = str(item.get("mode", "plan")).strip().lower()
        if mode not in {"plan", "edit"}:
            raise ValueError(f"Task {tid}: mode chỉ nhận 'plan' hoặc 'edit' (nhận {mode!r}).")
        specs.append(
            WaveTaskSpec(
                id=tid,
                role=role,
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


def _paths_overlap(path_a: str, path_b: str) -> bool:
    return (
        path_a == path_b
        or path_a.startswith(f"{path_b}/")
        or path_b.startswith(f"{path_a}/")
    )


def _validate_single_writer(tasks: list[WaveTaskSpec]) -> None:
    owned_entries: list[tuple[str, str]] = []
    for task in tasks:
        if task.mode != "edit":
            continue
        for raw_p in task.owned_paths or []:
            norm = _normalize_rel_path(raw_p)
            if not norm:
                continue
            for prev_path, prev_owner in owned_entries:
                if prev_owner != task.id and _paths_overlap(norm, prev_path):
                    raise ValueError(
                        f"Vi phạm single-writer: đường dẫn '{norm}' ({task.id}) "
                        f"chồng lấn với '{prev_path}' ({prev_owner})."
                    )
            owned_entries.append((norm, task.id))


def _detect_scope_violations(
    effective_mode: str,
    owned_paths: list[str] | None,
    changed_files: list[str],
) -> list[str]:
    if not changed_files:
        return []
    normalized_changed = [
        norm for raw in changed_files if (norm := _normalize_rel_path(raw))
    ]
    if effective_mode == "plan":
        return normalized_changed
    if effective_mode == "accept-edits":
        allowed_prefixes = [
            norm for raw in (owned_paths or []) if (norm := _normalize_rel_path(raw))
        ]
        violations: list[str] = []
        for changed in normalized_changed:
            is_allowed = any(
                changed == prefix or changed.startswith(f"{prefix}/")
                for prefix in allowed_prefixes
            )
            if not is_allowed:
                violations.append(changed)
        return violations
    return normalized_changed


def _collect_worktree_changes(
    worktree_dir: pathlib.Path,
    diff_patch_path: pathlib.Path,
) -> tuple[list[str], str | None]:
    status_proc = subprocess.run(
        ["git", "-c", "core.quotepath=false", "status", "--porcelain", "-uall"],
        cwd=str(worktree_dir),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if status_proc.returncode != 0:
        raise RuntimeError(
            f"Không đọc được `git status --porcelain` tại {worktree_dir}:\n"
            f"{status_proc.stderr.strip()}"
        )

    changed_set: set[str] = set()
    untracked_files: list[str] = []
    for line in status_proc.stdout.splitlines():
        if len(line) < 4:
            continue
        xy = line[:2]
        raw_entry = line[3:]
        if ("R" in xy or "C" in xy) and " -> " in raw_entry:
            old_raw, new_raw = raw_entry.split(" -> ", 1)
            old_norm = _normalize_rel_path(old_raw)
            new_norm = _normalize_rel_path(new_raw)
            if old_norm:
                changed_set.add(old_norm)
            if new_norm:
                changed_set.add(new_norm)
        else:
            norm = _normalize_rel_path(raw_entry)
            if norm:
                changed_set.add(norm)
                if xy == "??":
                    untracked_files.append(norm)

    changed_files = sorted(changed_set)
    if not changed_files:
        return [], None

    patch_chunks: list[str] = []
    tracked_diff = subprocess.run(
        ["git", "-c", "core.quotepath=false", "diff", "--binary", "HEAD"],
        cwd=str(worktree_dir),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if tracked_diff.stdout:
        patch_chunks.append(tracked_diff.stdout)

    for rel_untracked in sorted(set(untracked_files)):
        untracked_diff = subprocess.run(
            [
                "git",
                "-c",
                "core.quotepath=false",
                "diff",
                "--binary",
                "--no-index",
                "--",
                "/dev/null",
                rel_untracked,
            ],
            cwd=str(worktree_dir),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
        if untracked_diff.stdout:
            patch_chunks.append(untracked_diff.stdout)

    diff_patch_path.write_text("\n".join(patch_chunks), encoding="utf-8")
    return changed_files, str(diff_patch_path)


def _build_worker_prompt(task: WaveTaskSpec) -> str:
    header_lines = [
        f"[ANTIGRAVITY v6.1 WAVE WORKER | task_id={task.id} | role={task.role} | mode={task.mode}]",
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
    cleanup_clean_worktrees: bool,
    timeout_sec: int,
    git_lock: threading.Lock,
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
    diff_patch_path = logs_dir / f"{task.id}.diff.patch"

    full_prompt = _build_worker_prompt(task)
    prompt_path.write_text(full_prompt, encoding="utf-8")

    with git_lock:
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

    changed_files, diff_patch = _collect_worktree_changes(worktree_dir, diff_patch_path)
    scope_violations = _detect_scope_violations(
        effective_mode, task.owned_paths, changed_files
    )
    if scope_violations:
        status = "SCOPE_VIOLATION"
        exit_code = 4

    worktree_cleaned = False
    if cleanup_clean_worktrees and exit_code == 0 and not changed_files:
        with git_lock:
            _run_checked(
                ["git", "worktree", "remove", "--force", str(worktree_dir)],
                cwd=repo_root,
            )
            _run_checked(
                ["git", "branch", "-D", branch_name],
                cwd=repo_root,
            )
        worktree_cleaned = True

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
        changed_files=changed_files,
        scope_violations=scope_violations,
        diff_patch=diff_patch,
        worktree_cleaned=worktree_cleaned,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Antigravity v6.1 Parallel Multi-Model CLI Wave Runner (6-Ban)"
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
        "--cleanup-clean-worktrees",
        action="store_true",
        help=(
            "Tự động dọn Git worktree và xóa nhánh tạm agy/<run>/<task> đối với các task "
            "hoàn thành với exit_code == 0 và không phát sinh file thay đổi."
        ),
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
        help="Thư mục lưu worktree và log của lần chạy (mặc định: ~/.gemini/tmp/agy-runs/<repo>/<run_id>).",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Chỉ kiểm tra schema JSON, known roles, single-writer, Git snapshot và danh sách model từ `agy models` mà không tạo tiến trình worker.",
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
            "version": "6.1",
            "dry_run": True,
            "agy_binary": agy_bin,
            "repo_root": str(repo_root),
            "base_commit": base_commit,
            "dirty_working_tree_preserved": bool(dirty_status),
            "jobs": args.jobs,
            "allow_edits": args.allow_edits,
            "cleanup_clean_worktrees": args.cleanup_clean_worktrees,
            "known_roles": sorted(KNOWN_ROLES),
            "verified_models": sorted({t.model for t in tasks}),
            "tasks": [asdict(t) for t in tasks],
        }
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        return 0

    base_runs_dir.mkdir(parents=True, exist_ok=True)
    git_lock = threading.Lock()
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
                cleanup_clean_worktrees=args.cleanup_clean_worktrees,
                timeout_sec=args.timeout,
                git_lock=git_lock,
            ): t
            for t in tasks
        }
        for fut in concurrent.futures.as_completed(future_map):
            results.append(fut.result())

    results.sort(key=lambda r: r.task_id)
    wall_seconds = round(time.perf_counter() - wave_start, 3)
    summary_payload = {
        "version": "6.1",
        "run_id": run_id,
        "repo_root": str(repo_root),
        "base_commit": base_commit,
        "jobs": args.jobs,
        "allow_edits": args.allow_edits,
        "cleanup_clean_worktrees": args.cleanup_clean_worktrees,
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
