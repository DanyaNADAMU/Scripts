#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "httpx[http2]>=0.27.0",
# ]
# ///
# ==============================================================================
# Script:      scan_reality.py (scan-reality)
# Category:    server
# Description: Scan, validate and rank TLS 1.3 & HTTP/2 camouflage targets for XTLS Reality.
# Target:      Linux / macOS
# Requires:    python >= 3.11, uv
# Usage:       scan-reality [options]
# ==============================================================================
from __future__ import annotations

import argparse
import asyncio
import csv
import datetime
import json
import os
import re
import socket
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import logging
import warnings
from dataclasses import asdict, dataclass
from typing import Any

# Suppress internal asyncio transport closure warnings
logging.getLogger("asyncio").setLevel(logging.ERROR)
warnings.filterwarnings("ignore", message=".*returning true from eof_received.*")

VERSION = "1.0.0"

# ==============================================================================
# Curated Default Whitelist
# High-bandwidth, stable domestic services with TLS 1.3 & HTTP/2 support
# ==============================================================================
DEFAULT_WHITELIST = (
    # Mail.ru & VK infrastructure
    "top-fwz1.mail.ru",
    "cloud.mail.ru",
    "cpg.money.mail.ru",
    "ctlog2024.mail.ru",
    "public.infra.mail.ru",
    "static.operator.mail.ru",
    "ufo.mail.ru",
    "wf.mail.ru",
    "status.mcs.mail.ru",
    "team.mail.ru",
    "tech.mail.ru",
    "stream.mail.ru",
    "vk.com",
    "login.vk.com",
    "cloud.vk.com",
    "cloud.vk.ru",
    "api.vk.ru",
    "login.vk.ru",
    "stats.vk-portal.net",
    "akashi.vk-portal.net",
    "queuev4.vk.com",
    "sun9-10.userapi.com",
    "sun9-20.userapi.com",
    "sun9-30.userapi.com",
    "sun9-40.userapi.com",
    "sun9-50.userapi.com",
    "sun9-60.userapi.com",
    "sun9-70.userapi.com",
    "sun9-80.userapi.com",
    "sun1-20.userapi.com",
    "sun1-50.userapi.com",
    "sun2-15.userapi.com",
    "sun3-20.userapi.com",
    "sun4-15.userapi.com",
    "sun7-15.userapi.com",
    # 2GIS
    "catalog.api.2gis.com",
    "api.2gis.ru",
    "disk.2gis.com",
    "2gis.com",
    "2gis.ru",
    "mapgl.2gis.com",
    "jam.api.2gis.com",
    "keys.api.2gis.com",
    "favorites.api.2gis.com",
    "tile0.maps.2gis.com",
    "tile1.maps.2gis.com",
    # Yandex & affiliated services
    "yandex.ru",
    "ya.ru",
    "300.ya.ru",
    "dzen.ru",
    "yastatic.net",
    "avatars.mds.yandex.net",
    "cloud.cdn.yandex.net",
    "api.s3.yandex.net",
    "cdn.s3.yandex.net",
    "speller.yandex.net",
    "csp.yandex.net",
    "s3.yandex.net",
    "api-maps.yandex.ru",
    "neuro.translate.yandex.ru",
    "cloudcdn-m9-2.cdn.yandex.net",
    "cloudcdn-m9-5.cdn.yandex.net",
    "cloudcdn-m9-10.cdn.yandex.net",
    # Ozon
    "ozon.ru",
    "www.ozon.ru",
    "seller.ozon.ru",
    "bank.ozon.ru",
    "invest.ozon.ru",
    "xapi.ozon.ru",
    "pay.ozon.ru",
    "securepay.ozon.ru",
    "st.ozone.ru",
    # Avito
    "avito.ru",
    "www.avito.ru",
    "api.avito.ru",
    "stats.avito.ru",
    "st.avito.ru",
    "avito.st",
    # Kinopoisk
    "kinopoisk.ru",
    "www.kinopoisk.ru",
    "hd.kinopoisk.ru",
    "st.kinopoisk.ru",
    "graphql.kinopoisk.ru",
    # RZD & Transport
    "rzd.ru",
    "www.rzd.ru",
    "ticket.rzd.ru",
    "travel.rzd.ru",
    "market.rzd.ru",
    "tutu.ru",
    "moskva.taximaxim.ru",
    # Wildberries
    "wb.ru",
    "a.wb.ru",
    "finance.wb.ru",
    # News & Media
    "lenta.ru",
    "gazeta.ru",
    "rbc.ru",
    "rambler.ru",
    "rutube.ru",
    "static.rutube.ru",
    # Retail & Telecom
    "lemanapro.ru",
    "static.lemanapro.ru",
    "t2.ru",
    "www.t2.ru",
    "s3.t2.ru",
)


# ==============================================================================
# Data Structures
# ==============================================================================
@dataclass
class ScanResult:
    domain: str
    ip: str
    total_ms: float
    tcp_ms: float
    tls_ms: float
    http_ms: float
    http_status: int
    http_version: str
    tls_version: str
    alpn: str
    cipher: str
    cert_issuer: str
    cert_expiry: str
    cert_sans: list[str]


@dataclass
class FailureResult:
    domain: str
    reason: str
    detail: str = ""


# ==============================================================================
# Target Prober
# ==============================================================================
class RealityProber:
    def __init__(
        self,
        timeout: float = 4.0,
        require_h2: bool = True,
        allow_redirects: bool = False,
        allowed_status_codes: set[int] | None = None,
        allow_untrusted_cert: bool = False,
    ) -> None:
        self.timeout = timeout
        self.require_h2 = require_h2
        self.allow_redirects = allow_redirects
        self.allowed_status_codes = allowed_status_codes or {200}
        self.allow_untrusted_cert = allow_untrusted_cert

    async def probe(
        self, domain: str, client: Any
    ) -> tuple[ScanResult | None, FailureResult | None]:
        loop = asyncio.get_running_loop()

        # ----------------------------------------------------------------------
        # Stage 0: DNS Resolution
        # ----------------------------------------------------------------------
        try:
            addr_info = await asyncio.wait_for(
                loop.getaddrinfo(domain, 443, family=socket.AF_INET),
                timeout=min(self.timeout, 2.5),
            )
            if not addr_info:
                return None, FailureResult(domain, "DNS Lookup Failed", "No IPv4 records")
            ip = addr_info[0][4][0]
        except TimeoutError:
            return None, FailureResult(domain, "DNS Timeout", "DNS query timed out")
        except Exception as e:
            return None, FailureResult(domain, "DNS Lookup Failed", str(e))

        # ----------------------------------------------------------------------
        # Stage 1: TCP Handshake (Connect)
        # ----------------------------------------------------------------------
        try:
            t0 = time.perf_counter()
            _, writer = await asyncio.wait_for(
                asyncio.open_connection(ip, 443),
                timeout=self.timeout,
            )
            tcp_ms = (time.perf_counter() - t0) * 1000
        except TimeoutError:
            return None, FailureResult(domain, "TCP Timeout", f"Port 443 unreachable ({ip})")
        except Exception as e:
            return None, FailureResult(domain, "TCP Connect Failed", str(e))

        # ----------------------------------------------------------------------
        # Stage 2: TLS 1.3 Handshake & Certificate Validation
        # ----------------------------------------------------------------------
        transport = writer.transport
        try:
            ctx = ssl.create_default_context()
            ctx.minimum_version = ssl.TLSVersion.TLSv1_3
            ctx.maximum_version = ssl.TLSVersion.TLSv1_3
            ctx.set_alpn_protocols(["h2", "http/1.1"])

            if self.allow_untrusted_cert:
                ctx.check_hostname = False
                ctx.verify_mode = ssl.CERT_NONE

            t1 = time.perf_counter()
            protocol = transport.get_protocol()
            tls_transport = await asyncio.wait_for(
                loop.start_tls(transport, protocol, ctx, server_hostname=domain),
                timeout=self.timeout,
            )
            tls_ms = (time.perf_counter() - t1) * 1000

            ssl_obj = tls_transport.get_extra_info("ssl_object")
            if not ssl_obj:
                tls_transport.close()
                return None, FailureResult(domain, "TLS Failed", "No SSL object after handshake")

            ver = ssl_obj.version() or "Unknown"
            if ver != "TLSv1.3":
                tls_transport.close()
                return None, FailureResult(domain, "No TLS 1.3", f"Negotiated {ver}")

            alpn = ssl_obj.selected_alpn_protocol()
            if self.require_h2 and alpn != "h2":
                tls_transport.close()
                return None, FailureResult(domain, "Missing ALPN h2", f"ALPN: {alpn or 'None'}")

            cipher_info = ssl_obj.cipher()
            cipher = cipher_info[0] if cipher_info else "Unknown"

            cert = ssl_obj.getpeercert() or {}
            issuer_entries = dict(x[0] for x in cert.get("issuer", []))
            issuer = issuer_entries.get(
                "organizationName", issuer_entries.get("commonName", "Unknown")
            )
            expiry = cert.get("notAfter", "")
            sans = [v for t, v in cert.get("subjectAltName", []) if t == "DNS"]

            tls_transport.close()
        except ssl.SSLCertVerificationError as e:
            transport.close()
            return None, FailureResult(domain, "Certificate Untrusted", e.verify_message)
        except TimeoutError:
            transport.close()
            return None, FailureResult(domain, "TLS Timeout", "TLS 1.3 handshake timed out")
        except Exception as e:
            transport.close()
            err_msg = str(e)
            if "TLSv1.3" in err_msg or "handshake" in err_msg.lower():
                return None, FailureResult(domain, "TLS Handshake Failed", err_msg)
            return None, FailureResult(domain, "TLS Error", err_msg)

        # ----------------------------------------------------------------------
        # Stage 3: HTTP/2 Request & Redirect Verification
        # ----------------------------------------------------------------------
        try:
            t2 = time.perf_counter()
            resp = await client.get(f"https://{domain}/")
            http_ms = (time.perf_counter() - t2) * 1000

            status = resp.status_code
            http_ver = resp.http_version
            location = resp.headers.get("location")

            if status in (301, 302, 303, 307, 308) and not self.allow_redirects:
                return None, FailureResult(
                    domain, "HTTP Redirect (3xx)", f"Status {status} -> {location or 'unknown'}"
                )

            if status not in self.allowed_status_codes:
                return None, FailureResult(
                    domain,
                    "HTTP Non-Accepted Status",
                    f"Status {status} not in {sorted(self.allowed_status_codes)}",
                )

            total_ms = tcp_ms + tls_ms + http_ms

            result = ScanResult(
                domain=domain,
                ip=ip,
                total_ms=round(total_ms, 2),
                tcp_ms=round(tcp_ms, 2),
                tls_ms=round(tls_ms, 2),
                http_ms=round(http_ms, 2),
                http_status=status,
                http_version=http_ver,
                tls_version=ver,
                alpn=alpn or "None",
                cipher=cipher,
                cert_issuer=issuer,
                cert_expiry=expiry,
                cert_sans=sans,
            )
            return result, None

        except TimeoutError:
            return None, FailureResult(domain, "HTTP Timeout", "GET request timed out")
        except Exception as e:
            return None, FailureResult(domain, "HTTP Probe Failed", str(e))


# ==============================================================================
# Domain Loader
# ==============================================================================
def normalize_domain(raw: str) -> str:
    cleaned = raw.strip()
    if not cleaned or cleaned.startswith("#"):
        return ""
    if "://" in cleaned:
        try:
            parsed = urllib.parse.urlparse(cleaned)
            cleaned = parsed.netloc or parsed.path
        except Exception:
            pass
    # Strip port, path, trailing slashes
    cleaned = cleaned.split("/")[0].split(":")[0].strip()
    return cleaned.lower()


def load_whitelist(source: str | None) -> list[str]:
    """Load domains from file, URL, stdin, or embedded default."""
    if not source:
        return [normalize_domain(d) for d in DEFAULT_WHITELIST if normalize_domain(d)]

    lines: list[str] = []
    if source == "-":
        lines = sys.stdin.read().splitlines()
    elif source.startswith("http://") or source.startswith("https://"):
        req = urllib.request.Request(
            source,
            headers={"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) scan-reality/1.0"},
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            content = resp.read().decode("utf-8", errors="ignore")
            lines = content.splitlines()
    else:
        path = os.path.expanduser(source)
        if not os.path.exists(path):
            raise FileNotFoundError(f"Whitelist file not found: {source}")
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()

    unique_domains: list[str] = []
    seen: set[str] = set()
    for line in lines:
        d = normalize_domain(line)
        if d and d not in seen and "." in d:
            seen.add(d)
            unique_domains.append(d)

    return unique_domains


# ==============================================================================
# Export & Presentation Formats
# ==============================================================================
def export_results(results: list[ScanResult], output_path: str, fmt: str) -> None:
    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)

    if fmt == "csv":
        with open(output_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(
                [
                    "rank",
                    "domain",
                    "ip",
                    "total_ms",
                    "tcp_ms",
                    "tls_ms",
                    "http_ms",
                    "http_status",
                    "http_version",
                    "tls_version",
                    "alpn",
                    "cipher",
                    "cert_issuer",
                    "cert_expiry",
                    "cert_sans",
                ]
            )
            for idx, r in enumerate(results, start=1):
                writer.writerow(
                    [
                        idx,
                        r.domain,
                        r.ip,
                        f"{r.total_ms:.2f}",
                        f"{r.tcp_ms:.2f}",
                        f"{r.tls_ms:.2f}",
                        f"{r.http_ms:.2f}",
                        r.http_status,
                        r.http_version,
                        r.tls_version,
                        r.alpn,
                        r.cipher,
                        r.cert_issuer,
                        r.cert_expiry,
                        ";".join(r.cert_sans),
                    ]
                )

    elif fmt == "json":
        data = []
        for idx, r in enumerate(results, start=1):
            item = asdict(r)
            item["rank"] = idx
            data.append(item)
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)

    elif fmt == "txt":
        with open(output_path, "w", encoding="utf-8") as f:
            for r in results:
                f.write(f"{r.domain}\n")


def print_summary(
    total: int,
    results: list[ScanResult],
    failures: list[FailureResult],
    output_path: str,
    top_n: int,
) -> None:
    passed = len(results)
    print("\n" + "=" * 76)
    print("  XTLS Reality Camouflage Scanner — Scan Complete")
    print("=" * 76)
    print(f"  Total Domains Checked:  {total}")
    pct = (passed / total * 100) if total else 0.0
    print(f"  Passed (TLS 1.3 + h2):  {passed} ({pct:.1f}%)")
    print(f"  Rejected:               {len(failures)}")

    # Failure reasons breakdown
    reasons: dict[str, int] = {}
    for f in failures:
        reasons[f.reason] = reasons.get(f.reason, 0) + 1

    for reason, count in sorted(reasons.items(), key=lambda x: -x[1]):
        print(f"    - {reason:<26} {count}")

    if results and top_n > 0:
        preview = results[:top_n]
        print("\n" + "-" * 76)
        print(f"  Top {min(top_n, len(preview))} Fastest Camouflage Targets (Sorted by Total RTT)")
        print("-" * 76)
        print(
            f"  {'#':<3} {'Domain':<28} {'Total':>8} {'TCP':>8} {'TLS':>8} {'HTTP':>8}  {'CA Issuer'}"
        )
        print(f"  {'-'*3} {'-'*28} {'-'*8} {'-'*8} {'-'*8} {'-'*8}  {'-'*16}")
        for idx, r in enumerate(preview, start=1):
            short_issuer = (r.cert_issuer[:16] + "..") if len(r.cert_issuer) > 18 else r.cert_issuer
            print(
                f"  {idx:<3} {r.domain:<28} {r.total_ms:>7.2f}m {r.tcp_ms:>7.2f}m {r.tls_ms:>7.2f}m {r.http_ms:>7.2f}m  {short_issuer}"
            )

    print("=" * 76)
    print(f"  Full results saved to: {output_path}")
    print("=" * 76 + "\n")


# ==============================================================================
# Async Scan Orchestrator
# ==============================================================================
async def scan_orchestrator(
    domains: list[str],
    prober: RealityProber,
    concurrency: int = 40,
    quiet: bool = False,
    verbose: bool = False,
) -> tuple[list[ScanResult], list[FailureResult]]:
    import httpx

    queue: asyncio.Queue[str] = asyncio.Queue()
    for d in domains:
        queue.put_nowait(d)

    total = len(domains)
    completed = 0
    results: list[ScanResult] = []
    failures: list[FailureResult] = []
    lock = asyncio.Lock()
    is_tty = sys.stdout.isatty() and not quiet

    limits = httpx.Limits(max_connections=concurrency * 2, max_keepalive_connections=concurrency)
    async with httpx.AsyncClient(
        http2=True,
        timeout=prober.timeout,
        follow_redirects=False,
        verify=not prober.allow_untrusted_cert,
        limits=limits,
    ) as client:

        async def worker() -> None:
            nonlocal completed
            while True:
                try:
                    domain = queue.get_nowait()
                except asyncio.QueueEmpty:
                    break

                res, fail = await prober.probe(domain, client)

                async with lock:
                    completed += 1
                    if res:
                        results.append(res)
                    elif fail:
                        failures.append(fail)
                        if verbose:
                            print(f"\n[FAIL] {fail.domain}: {fail.reason} ({fail.detail})", file=sys.stderr)

                    if is_tty:
                        pct = (completed / total) * 100
                        curr = domain if len(domain) <= 24 else f"{domain[:21]}..."
                        sys.stdout.write(
                            f"\r\033[K  ⏳ [{completed}/{total}] {pct:5.1f}% | Valid: {len(results):<4} | Scanning: {curr}"
                        )
                        sys.stdout.flush()

                queue.task_done()

        workers = [asyncio.create_task(worker()) for _ in range(min(concurrency, total))]
        await asyncio.gather(*workers)

    if is_tty:
        sys.stdout.write("\r\033[K")
        sys.stdout.flush()

    # Sort results by total latency ascending
    results.sort(key=lambda r: r.total_ms)
    return results, failures


# ==============================================================================
# CLI Arguments Parser & Main Entrypoint
# ==============================================================================
def parse_args() -> argparse.Namespace:
    today_str = datetime.date.today().isoformat()
    default_out = f"reality_targets_{today_str}.csv"

    parser = argparse.ArgumentParser(
        prog="scan-reality",
        description="High-performance async TLS 1.3 & HTTP/2 scanner for XTLS Reality camouflage targets.",
        epilog=(
            "Examples:\n"
            "  scan-reality                          # Scan embedded curated whitelist to reality_targets_YYYY-MM-DD.csv\n"
            "  scan-reality -w whitelist.txt         # Scan custom domain whitelist\n"
            "  scan-reality -w https://example.com/domains.txt -o results.json -f json\n"
            "  cat domains.txt | scan-reality -w -   # Read domains from stdin pipe\n"
            "  scan-reality -c 100 -t 3.0 --top 10   # High concurrency with top 10 preview\n"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument(
        "-w",
        "--whitelist",
        metavar="PATH_OR_URL",
        help="Path to whitelist file, HTTP(S) URL, or '-' for stdin. Defaults to built-in curated whitelist.",
    )
    parser.add_argument(
        "-o",
        "--output",
        metavar="PATH",
        default=default_out,
        help=f"Output destination path (default: {default_out}).",
    )
    parser.add_argument(
        "-f",
        "--format",
        choices=["csv", "json", "txt"],
        default="csv",
        help="Output serialization format: csv, json, or txt (default: csv).",
    )
    parser.add_argument(
        "-c",
        "--concurrency",
        type=int,
        default=40,
        metavar="N",
        help="Number of concurrent asynchronous scan workers (default: 40).",
    )
    parser.add_argument(
        "-t",
        "--timeout",
        type=float,
        default=4.0,
        metavar="SEC",
        help="Network timeout in seconds per domain connection/handshake (default: 4.0).",
    )
    parser.add_argument(
        "--no-h2",
        action="store_true",
        help="Allow HTTP/1.1; do not strictly require ALPN h2 (default: h2 is required).",
    )
    parser.add_argument(
        "--allow-redirects",
        action="store_true",
        help="Allow HTTP 3xx redirects (default: redirects are strictly rejected).",
    )
    parser.add_argument(
        "--allow-status",
        metavar="CODES",
        default="200",
        help="Comma-separated list of allowed HTTP response codes (default: 200).",
    )
    parser.add_argument(
        "--allow-untrusted-cert",
        action="store_true",
        help="Permit self-signed or untrusted CA root certificates such as Russian Trusted CA (default: require valid trusted CA).",
    )
    parser.add_argument(
        "--top",
        type=int,
        default=5,
        metavar="N",
        help="Number of top fastest candidates to preview in console summary (default: 5, 0 to disable).",
    )
    parser.add_argument(
        "-q",
        "--quiet",
        action="store_true",
        help="Suppress real-time console progress indicator.",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print detailed failure diagnostics to stderr during scanning.",
    )
    parser.add_argument(
        "-v",
        "--version",
        action="version",
        version=f"%(prog)s {VERSION}",
    )

    return parser.parse_args()


def main() -> None:
    args = parse_args()

    # Parse allowed status codes
    try:
        allowed_status_codes = {int(c.strip()) for c in args.allow_status.split(",") if c.strip()}
    except ValueError:
        print(f"Error: Invalid --allow-status specification: {args.allow_status}", file=sys.stderr)
        sys.exit(2)

    # Load targets
    try:
        domains = load_whitelist(args.whitelist)
    except Exception as e:
        print(f"Error loading whitelist: {e}", file=sys.stderr)
        sys.exit(1)

    if not domains:
        print("Error: No valid domains found in whitelist.", file=sys.stderr)
        sys.exit(1)

    if not args.quiet:
        source_label = args.whitelist or "built-in curated list"
        print(f"[*] Loaded {len(domains)} unique domain(s) from {source_label}.")
        print(f"[*] Scanner parameters: Concurrency={args.concurrency}, Timeout={args.timeout}s, Require H2={not args.no_h2}")
        print(f"[*] Starting async TLS 1.3 / HTTP probe...")

    prober = RealityProber(
        timeout=args.timeout,
        require_h2=not args.no_h2,
        allow_redirects=args.allow_redirects,
        allowed_status_codes=allowed_status_codes,
        allow_untrusted_cert=args.allow_untrusted_cert,
    )

    t_start = time.perf_counter()
    try:
        results, failures = asyncio.run(
            scan_orchestrator(
                domains=domains,
                prober=prober,
                concurrency=args.concurrency,
                quiet=args.quiet,
                verbose=args.verbose,
            )
        )
    except KeyboardInterrupt:
        print("\n[!] Scan interrupted by user.", file=sys.stderr)
        sys.exit(130)

    elapsed = time.perf_counter() - t_start

    # Export to requested format
    try:
        export_results(results, args.output, args.format)
    except Exception as e:
        print(f"Error writing output file '{args.output}': {e}", file=sys.stderr)
        sys.exit(1)

    if not args.quiet:
        print_summary(
            total=len(domains),
            results=results,
            failures=failures,
            output_path=args.output,
            top_n=args.top,
        )
        print(f"[*] Finished in {elapsed:.2f}s ({len(domains)/elapsed:.1f} domains/s).")

    # Exit 0 if at least one candidate passed, otherwise exit 1
    sys.exit(0 if results else 1)


if __name__ == "__main__":
    main()
