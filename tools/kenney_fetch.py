# Fetch free asset packs from https://kenney.nl/assets.
# Kenney publishes these packs for download. This tool only follows public
# asset pages and their zip links. It does not log in, bypass a paywall, or
# download the paid all-in-one bundle.
#
# Examples:
#   python tools/kenney_fetch.py search --query furniture
#   python tools/kenney_fetch.py download --query "top down" --out artifacts/kenney --limit 3

import argparse
import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = "https://kenney.nl/assets"
USER_AGENT = "TownDinerKenneyFetch/1.0 (personal asset staging)"
PAUSE_SEC = 0.4


def fetch(url: str) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read().decode("utf-8", "replace")


def asset_links(html: str) -> list[dict]:
    found = []
    seen = set()
    pattern = re.compile(r"href='(https://kenney\.nl/assets/([a-z0-9-]+))'[^>]*>([^<]+)</a>", re.I)
    for match in pattern.finditer(html):
        slug = match.group(2)
        if slug.startswith(("category:", "tag:", "series:", "page:")) or slug in seen:
            continue
        seen.add(slug)
        found.append({"slug": slug, "title": match.group(3).strip(), "url": match.group(1)})
    return found


def search(query: str, pages: int) -> list[dict]:
    results = []
    seen = set()
    for page in range(1, pages + 1):
        if page == 1:
            url = ROOT + "?" + urllib.parse.urlencode({"search": query})
        else:
            url = f"{ROOT}/page:{page}?" + urllib.parse.urlencode({"search": query})
        rows = asset_links(fetch(url))
        if not rows:
            break
        for row in rows:
            if row["slug"] not in seen:
                seen.add(row["slug"])
                results.append(row)
        time.sleep(PAUSE_SEC)
    return results


def zip_url(page_html: str) -> str:
    match = re.search(r"https://kenney\.nl/media/pages/assets/[^'\" ]+\.zip", page_html)
    return match.group(0) if match else ""


def download(query: str, output: Path, limit: int, pages: int) -> list[dict]:
    output.mkdir(parents=True, exist_ok=True)
    saved = []
    for row in search(query, pages)[:limit]:
        page = fetch(row["url"])
        pack = zip_url(page)
        time.sleep(PAUSE_SEC)
        if pack == "":
            row["status"] = "NO_ZIP"
            saved.append(row)
            continue
        target = output / f"{row['slug']}.zip"
        urllib.request.urlretrieve(pack, target)
        row["file"] = str(target)
        row["status"] = "SAVED"
        saved.append(row)
        time.sleep(PAUSE_SEC)
    manifest = output / "manifest.json"
    manifest.write_text(json.dumps(saved, ensure_ascii=False, indent=2), encoding="utf-8")
    return saved


def main() -> None:
    parser = argparse.ArgumentParser(description="Search and download free Kenney asset packs.")
    parser.add_argument("command", choices=["search", "download"])
    parser.add_argument("--query", required=True)
    parser.add_argument("--pages", type=int, default=2)
    parser.add_argument("--limit", type=int, default=5)
    parser.add_argument("--out", default="artifacts/kenney")
    args = parser.parse_args()
    if args.command == "search":
        for row in search(args.query, args.pages):
            print(f"{row['title']}\t{row['url']}")
        return
    saved = download(args.query, Path(args.out), args.limit, args.pages)
    print(f"SAVED {sum(1 for row in saved if row.get('status') == 'SAVED')} / {len(saved)}")


if __name__ == "__main__":
    main()
