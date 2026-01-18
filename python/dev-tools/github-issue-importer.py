# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "httpx~=0.27",
#     "click>=8",
#     "python-dotenv>=1",
#     "loguru>=0.7",
# ]
# ///
"""Bulk‑import GitHub issues from a CSV file via the issues‑import API.

Each CSV row must have three columns:
    title, body, labels

Labels are a comma‑separated list in the single *labels* column.

Example usage:
    $ bulk-issue-import issues.csv --owner indrasvat --repo hews

The script loads a `.env` file automatically and falls back to the
`GITHUB_TOKEN` environment variable for authentication.
"""
from __future__ import annotations

import asyncio
import csv
import json
import sys
from pathlib import Path
from types import TracebackType
from typing import Iterable, List, Optional, Type

import click
import httpx
from dotenv import load_dotenv
from loguru import logger

# ---------------------------------------------------------------------------
# Helpers & data structures
# ---------------------------------------------------------------------------

GITHUB_API_ROOT = "https://api.github.com/"
PREVIEW_ACCEPT_HEADER = "application/vnd.github.golden-comet-preview+json"


class IssueImporter:
    """Import issues one‑by‑one using the GitHub issues‑import endpoint."""

    def __init__(
        self,
        owner: str,
        repo: str,
        token: str,
        *,
        timeout: float = 10.0,
    ) -> None:
        self.owner = owner
        self.repo = repo
        self.base_url = (
            f"https://api.github.com/repos/{owner}/{repo}/import/issues"
        )
        self._client = httpx.AsyncClient(
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": PREVIEW_ACCEPT_HEADER,
                "Content-Type": "application/json",
            },
            timeout=timeout,
        )

    async def __aenter__(self) -> "IssueImporter":
        return self

    async def __aexit__(
        self,
        exc_type: Optional[Type[BaseException]],
        exc: Optional[BaseException],
        tb: Optional[TracebackType],
    ) -> None:
        await self._client.aclose()

    async def import_issue(self, *, title: str, body: str, labels: List[str]) -> None:
        payload = {
            "issue": {
                "title": title,
                "body": body,
                "labels": labels,
            }
        }
        logger.debug("Payload for '{}': {}", title, payload)

        resp = await self._client.post(self.base_url, content=json.dumps(payload))
        if resp.status_code == 202:
            resp_json = resp.json()
            issue_url = resp_json.get("url")
            status = resp_json.get("status")

            logger.success("✅ Imported: '(Status: {}) {}'  → {}", status, title, issue_url)
        else:
            try:
                err = resp.json()
            except ValueError:
                err = resp.text
            logger.error(
                "❌ Failed to import '{}': {} {}", title, resp.status_code, err
            )
            resp.raise_for_status()


# ---------------------------------------------------------------------------
# CSV reading
# ---------------------------------------------------------------------------

def iter_csv_rows(csv_path: Path) -> Iterable[dict[str, str]]:
    with csv_path.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            yield row


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

@click.command("bulk-issue-import")
@click.argument(
    "csv_file",
    type=click.Path(exists=True, readable=True, dir_okay=False, path_type=Path),
)
@click.option("--owner", required=True, help="GitHub repository owner (user/org)")
@click.option("--repo", required=True, help="Repository name")
@click.option(
    "--token",
    envvar="GITHUB_TOKEN",
    help="GitHub personal access token (defaults to env GITHUB_TOKEN)",
)
@click.option(
    "--log-level",
    default="INFO",
    show_default=True,
    help="Logging level",
)
def main(csv_file: Path, owner: str, repo: str, token: str | None, log_level: str) -> None:  # noqa: D401
    """Import every issue in CSV_FILE into the specified GitHub repo."""

    load_dotenv()
    token = token or sys.exit("GITHUB_TOKEN is not set (option or env var required)")

    logger.remove()  # reset default
    logger.add(sys.stderr, level=log_level.upper())

    logger.info("Starting import into {}/{} from {}", owner, repo, csv_file)

    async def _run() -> None:
        async with IssueImporter(owner, repo, token) as importer:
            for row in iter_csv_rows(csv_file):
                title = row["title"].strip()
                body = row["body"].rstrip()
                labels = [lbl.strip() for lbl in row["labels"].split(",")]
                await importer.import_issue(title=title, body=body, labels=labels)

                # Wait for 5 seconds before the next request
                await asyncio.sleep(5)

    asyncio.run(_run())


if __name__ == "__main__":  # pragma: no cover
    main()
