from __future__ import annotations

import argparse
import json

from energy_scheduler.config import load_config
from energy_scheduler.service import SchedulerService


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run the local energy scheduler")
    parser.add_argument("--config", required=True, help="Path to the scheduler JSON config")
    parser.add_argument("--once", action="store_true", help="Run one planning cycle and exit")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    config = load_config(args.config)
    service = SchedulerService(config)
    if args.once:
        snapshot = service.run_once()
        print(json.dumps(snapshot, indent=2, sort_keys=True))
        return 0
    service.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
