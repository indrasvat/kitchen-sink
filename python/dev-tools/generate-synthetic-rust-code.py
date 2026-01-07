# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
from __future__ import annotations

import argparse
import random
import string
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Settings:
    out_file: Path
    target_lines: int
    seed: int
    approx_module_lines: int
    overwrite: bool


RUST_KEYWORDS: set[str] = {
    "as",
    "break",
    "const",
    "continue",
    "crate",
    "else",
    "enum",
    "extern",
    "false",
    "fn",
    "for",
    "if",
    "impl",
    "in",
    "let",
    "loop",
    "match",
    "mod",
    "move",
    "mut",
    "pub",
    "ref",
    "return",
    "self",
    "Self",
    "static",
    "struct",
    "super",
    "trait",
    "true",
    "type",
    "unsafe",
    "use",
    "where",
    "while",
    "async",
    "await",
    "dyn",
}


DOMAINS: list[str] = [
    "auth",
    "cache",
    "codec",
    "config",
    "ingest",
    "metrics",
    "net",
    "parser",
    "query",
    "router",
    "storage",
    "telemetry",
    "worker",
    "scheduler",
    "limits",
    "policy",
]

NOUNS: list[str] = [
    "Record",
    "Request",
    "Response",
    "State",
    "Policy",
    "Stats",
    "Plan",
    "Snapshot",
    "Cursor",
    "Envelope",
    "Event",
    "Task",
    "Job",
    "Frame",
]


def _ident(rng: random.Random, min_len: int = 6, max_len: int = 12) -> str:
    n = rng.randint(min_len, max_len)
    s = "".join(rng.choice(string.ascii_lowercase) for _ in range(n))
    if s in RUST_KEYWORDS:
        s = f"{s}_x"
    return s


def _lines(s: str) -> list[str]:
    # Normalize to lines without trailing \n.
    return s.splitlines()


def _module_block(rng: random.Random, idx: int, domain: str) -> list[str]:
    prefix = f"M{idx:04d}"
    type_record = f"{prefix}{rng.choice(NOUNS)}"
    type_status = f"{prefix}Status"
    type_output = f"{prefix}Output"
    type_trait = f"{prefix}Processor"

    f1, f2, f3, f4 = (_ident(rng), _ident(rng), _ident(rng), _ident(rng))
    tag = f"{domain}-{idx:04d}"

    helpers_n = rng.randint(8, 14)
    methods_n = rng.randint(5, 9)

    helpers: list[str] = []
    for _ in range(helpers_n):
        fn = _ident(rng)
        helpers.extend(
            [
                f"    pub fn {fn}(input: &str) -> Result<u32> {{",
                f'        let s = normalize_ws(require_nonempty(input, "{fn}")?);',
                "        Ok(checksum32(s.as_bytes()))",
                "    }",
                "",
            ]
        )

    methods: list[str] = []
    for _ in range(methods_n):
        m = _ident(rng)
        methods.extend(
            [
                f"        pub fn {m}(&self, value: i64) -> Result<i64> {{",
                "            let v = clamp_i64(value + self.priority as i64, -10_000, 10_000, \"policy\")?;",
                "            Ok(v / (1 + (self.priority as i64 % 5)))",
                "        }",
                "",
            ]
        )

    # One module ~= 180-260 lines; tuned to “feels real” and scalable.
    out: list[str] = []
    out += [
        f"    /// Generated module {idx:04d} ({domain}). Tag: {tag}",
        f"    pub mod m{idx:04d} {{",
        "        use crate::{",
        "            clamp_i64, checksum32, normalize_ws, parse_i64, require_nonempty, split_kv, Error, Result,",
        "        };",
        "        use core::cmp::Ordering;",
        "        use std::collections::BTreeMap;",
        "",
        "        #[derive(Clone, Debug, PartialEq, Eq)]",
        f"        pub enum {type_status} {{",
        "            New,",
        "            Ready,",
        "            Blocked,",
        "            Done,",
        "        }",
        "",
        "        #[derive(Clone, Debug, PartialEq, Eq)]",
        f"        pub struct {type_record} {{",
        "            pub id: u64,",
        "            pub name: String,",
        "            pub level: u8,",
        "            pub tag: String,",
        "            pub attrs: BTreeMap<String, String>,",
        f"            pub status: {type_status},",
        f"            pub {f1}: u32,",
        f"            pub {f2}: u32,",
        f"            pub {f3}: u32,",
        f"            pub {f4}: u32,",
        "        }",
        "",
        f"        impl {type_record} {{",
        "            pub fn key(&self) -> String {",
        "                format!(\"{}:{}:{}\", self.tag, self.level, self.id)",
        "            }",
        "",
        "            pub fn cmp_by_priority(&self, other: &Self) -> Ordering {",
        "                (self.level, self.id).cmp(&(other.level, other.id))",
        "            }",
        "        }",
        "",
        "        #[derive(Clone, Debug, PartialEq, Eq)]",
        f"        pub struct {type_output} {{",
        "            pub score: i64,",
        "            pub label: String,",
        "            pub fingerprint: u32,",
        "        }",
        "",
        f"        pub trait {type_trait} {{",
        f"            fn process(&self, record: &{type_record}) -> Result<{type_output}>;",
        "        }",
        "",
        "        #[derive(Clone, Debug)]",
        "        pub struct DefaultProcessor {",
        "            priority: u8,",
        "        }",
        "",
        "        impl DefaultProcessor {",
        "            pub fn new(priority: u8) -> Self {",
        "                Self { priority }",
        "            }",
        "",
    ]
    out += methods
    out += [
        f"            pub fn score_label(&self, record: &{type_record}) -> (i64, String) {{",
        "                let base = (record.level as i64) * 100 + (record.id as i64 % 97);",
        f"                let label = if record.status == {type_status}::Blocked {{",
        "                    \"blocked\"",
        f"                }} else if record.status == {type_status}::Done {{",
        "                    \"done\"",
        "                } else {",
        "                    \"active\"",
        "                };",
        "                (base + self.priority as i64, format!(\"{}/{}\", label, record.tag))",
        "            }",
        "        }",
        "",
        f"        impl {type_trait} for DefaultProcessor {{",
        f"            fn process(&self, record: &{type_record}) -> Result<{type_output}> {{",
        "                let (score, label) = self.score_label(record);",
        f"                let fp = checksum32(record.key().as_bytes()) ^ record.{f1} ^ record.{f2} ^ record.{f3} ^ record.{f4};",
        "                Ok(",
        f"                    {type_output} {{",
        "                        score: clamp_i64(score, -1_000_000, 1_000_000, \"score\")?,",
        "                        label,",
        "                        fingerprint: fp,",
        "                    }},",
        "                )",
        "            }",
        "        }",
        "",
        f"        pub fn parse(input: &str) -> Result<{type_record}> {{",
        "            let mut id: Option<u64> = None;",
        "            let mut name: Option<String> = None;",
        "            let mut level: Option<u8> = None;",
        "            let mut tag: Option<String> = None;",
        "",
        "            let mut attrs = BTreeMap::new();",
        "            for raw in input.lines() {",
        "                let line = normalize_ws(raw);",
        "                if line.is_empty() {",
        "                    continue;",
        "                }",
        "                let Some((k, v)) = split_kv(&line) else {",
        "                    return Err(Error::InvalidInput { what: \"kv\", value: line });",
        "                };",
        "                match k {",
        "                    \"id\" => {",
        "                        let parsed = parse_i64(v, \"id\")?;",
        "                        let clamped = clamp_i64(parsed, 0, i64::from(u64::MAX as u32), \"id\")?;",
        "                        id = Some(clamped as u64);",
        "                    }",
        "                    \"name\" => {",
        "                        name = Some(require_nonempty(v, \"name\")?.to_string());",
        "                    }",
        "                    \"level\" => {",
        "                        let parsed = parse_i64(v, \"level\")?;",
        "                        let clamped = clamp_i64(parsed, 0, 255, \"level\")?;",
        "                        level = Some(clamped as u8);",
        "                    }",
        "                    \"tag\" => {",
        "                        tag = Some(require_nonempty(v, \"tag\")?.to_string());",
        "                    }",
        "                    _ => {",
        "                        attrs.insert(k.to_string(), v.to_string());",
        "                    }",
        "                }",
        "            }",
        "",
        "            let id = id.ok_or(Error::MissingField { field: \"id\" })?;",
        "            let name = name.ok_or(Error::MissingField { field: \"name\" })?;",
        "            let level = level.ok_or(Error::MissingField { field: \"level\" })?;",
        f"            let tag = tag.unwrap_or_else(|| \"{tag}\".to_string());",
        "",
        "            let a = checksum32(name.as_bytes());",
        "            let b = checksum32(tag.as_bytes());",
        "            let c = checksum32(format!(\"{}:{}\", id, level).as_bytes());",
        "            let d = checksum32(input.as_bytes());",
        "",
        "            Ok(",
        f"                {type_record} {{",
        "                    id,",
        "                    name,",
        "                    level,",
        "                    tag,",
        "                    attrs,",
        f"                    status: {type_status}::Ready,",
        f"                    {f1}: a,",
        f"                    {f2}: b,",
        f"                    {f3}: c,",
        f"                    {f4}: d,",
        "                },",
        "            )",
        "        }",
        "",
    ]
    out += helpers
    out += [
        "        #[cfg(test)]",
        "        mod tests {",
        "            use super::*;",
        "",
        "            #[test]",
        "            fn test_parse_and_process() {",
        f"                let input = \"id=42\\nname=alpha\\nlevel=3\\ntag={tag}\";",
        "                let rec = parse(input).expect(\"parse ok\");",
        "                let out = DefaultProcessor::new(2).process(&rec).expect(\"process ok\");",
        "                assert!(out.score >= 0);",
        "                assert!(!out.label.is_empty());",
        "            }",
        "        }",
        "    }",
        "",
    ]
    return out


def generate(settings: Settings) -> str:
    rng = random.Random(settings.seed)

    lines: list[str] = []
    lines += [
        "#![allow(dead_code, unused_imports, unused_variables, clippy::all)]",
        "//! Synthetic single-file Rust code (~40K LOC) generated for tooling tests.",
        "//!",
        "//! Intended uses: editor indexing, formatting benchmarks, LSP stress tests, static analysis, etc.",
        "",
        "use core::fmt;",
        "",
        "pub type Result<T> = core::result::Result<T, Error>;",
        "",
        "#[derive(Debug, Clone, PartialEq, Eq)]",
        "pub enum Error {",
        "    InvalidInput { what: &'static str, value: String },",
        "    OutOfRange { what: &'static str, value: i64, min: i64, max: i64 },",
        "    MissingField { field: &'static str },",
        "    Internal(String),",
        "}",
        "",
        "impl fmt::Display for Error {",
        "    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {",
        "        match self {",
        "            Error::InvalidInput { what, value } => write!(f, \"invalid input for {what}: {value}\"),",
        "            Error::OutOfRange { what, value, min, max } => {",
        "                write!(f, \"out of range for {what}: {value} (expected {min}..={max})\")",
        "            }",
        "            Error::MissingField { field } => write!(f, \"missing required field: {field}\"),",
        "            Error::Internal(msg) => write!(f, \"internal error: {msg}\"),",
        "        }",
        "    }",
        "}",
        "",
        "impl std::error::Error for Error {}",
        "",
        "pub fn clamp_i64(value: i64, min: i64, max: i64, what: &'static str) -> Result<i64> {",
        "    if value < min || value > max {",
        "        return Err(Error::OutOfRange { what, value, min, max });",
        "    }",
        "    Ok(value)",
        "}",
        "",
        "pub fn split_kv(line: &str) -> Option<(&str, &str)> {",
        "    let (k, v) = line.split_once('=')?;",
        "    Some((k.trim(), v.trim()))",
        "}",
        "",
        "pub fn normalize_ws(s: &str) -> String {",
        "    let mut out = String::with_capacity(s.len());",
        "    let mut prev_space = false;",
        "    for ch in s.chars() {",
        "        let is_space = ch.is_whitespace();",
        "        if is_space {",
        "            if !prev_space {",
        "                out.push(' ');",
        "            }",
        "        } else {",
        "            out.push(ch);",
        "        }",
        "        prev_space = is_space;",
        "    }",
        "    out.trim().to_string()",
        "}",
        "",
        "pub fn checksum32(bytes: &[u8]) -> u32 {",
        "    // Tiny non-cryptographic checksum (FNV-1a-ish).",
        "    let mut h: u32 = 2166136261;",
        "    for &b in bytes {",
        "        h ^= b as u32;",
        "        h = h.wrapping_mul(16777619);",
        "    }",
        "    h",
        "}",
        "",
        "pub fn parse_i64(s: &str, what: &'static str) -> Result<i64> {",
        "    s.parse::<i64>()",
        "        .map_err(|_| Error::InvalidInput { what, value: s.to_string() })",
        "}",
        "",
        "pub fn require_nonempty<'a>(s: &'a str, what: &'static str) -> Result<&'a str> {",
        "    if s.trim().is_empty() {",
        "        return Err(Error::InvalidInput { what, value: s.to_string() });",
        "    }",
        "    Ok(s)",
        "}",
        "",
        "pub mod generated {",
        "    //! Bulk synthetic code lives here.",
        "",
    ]

    # Reserve a small footer budget so we never overshoot.
    footer_budget = 12  # closing braces + main + optional padding label
    target = settings.target_lines

    # Generate modules until we're near the target.
    idx = 1
    while True:
        domain = rng.choice(DOMAINS)
        block = _module_block(rng, idx=idx, domain=domain)

        # If adding this module would exceed target, stop and pad instead.
        if len(lines) + len(block) + footer_budget > target:
            break

        lines += block
        idx += 1

        # Optional: stop if we've already reached a point where padding is small.
        if len(lines) + footer_budget >= target - settings.approx_module_lines:
            # Keep generating only if we can still fit at least one more module cleanly.
            continue

    lines += [
        "    pub fn demo() -> u32 {",
        "        // Touch a couple of modules to look realistic.",
        "        let a = m0001::helpers::checksum_hint();",
        "        let b = m0001::helpers::checksum_hint().wrapping_add(a);",
        "        b",
        "    }",
        "}",
        "",
        "fn main() {",
        "    // Keep runtime trivial; this file is meant for tooling, not behavior.",
        "    let _ = generated::demo();",
        "}",
    ]

    # Ensure generated::m0001::helpers exists: if we generated zero modules, we need one minimal.
    # But in practice, we always fit at least 1. Still, guard.
    if "pub mod m0001" not in "\n".join(lines):
        # Insert a minimal m0001 at the start of generated.
        insert_at = lines.index("pub mod generated {") + 3
        minimal = _lines(
            """
    /// Generated module 0001 (minimal fallback).
    pub mod m0001 {
        use crate::{checksum32, Result};

        pub mod helpers {
            use crate::checksum32;

            pub fn checksum_hint() -> u32 {
                checksum32(b"hint")
            }
        }

        pub fn ping() -> Result<u32> {
            Ok(checksum32(b"ping"))
        }
    }
"""
        )
        lines[insert_at:insert_at] = minimal

    # Patch: add m0001::helpers::checksum_hint() in modules (helpers module not present above).
    # Easiest: add a tiny helpers submodule into m0001 right after it opens.
    # We'll only do this once and only if it doesn't already exist.
    text = "\n".join(lines)
    if "pub mod m0001" in text and "pub mod helpers" not in text.split("pub mod m0001", 1)[1].split("pub mod m0002", 1)[0]:
        patched: list[str] = []
        for line in lines:
            patched.append(line)
            if line.strip() == "pub mod m0001 {":
                patched += [
                    "        pub mod helpers {",
                    "            use crate::checksum32;",
                    "            pub fn checksum_hint() -> u32 {",
                    "                checksum32(b\"m0001\")",
                    "            }",
                    "        }",
                    "",
                ]
        lines = patched

    # Pad/truncate to exact line count.
    if len(lines) > target:
        lines = lines[:target]
        # Guarantee last line ends the file sensibly (comment is fine).
        lines[-1] = "// truncated to exact target line count"
    elif len(lines) < target:
        pad_n = target - len(lines)
        lines += [f"// padding {i:05d}" for i in range(pad_n)]

    # Final newline at EOF (standard).
    return "\n".join(lines) + "\n"


def parse_args() -> Settings:
    p = argparse.ArgumentParser(description="Generate a single Rust file with exactly N lines of synthetic code.")
    p.add_argument("--out", default="synthetic.rs", help="Output Rust file path")
    p.add_argument("--lines", type=int, default=40_000, help="Exact target line count")
    p.add_argument("--seed", type=int, default=42, help="Deterministic RNG seed")
    p.add_argument("--approx-module-lines", type=int, default=220, help="Tuning knob for module sizes")
    p.add_argument("--overwrite", action="store_true", help="Overwrite output file if it exists")
    ns = p.parse_args()

    out = Path(ns.out).expanduser().resolve()
    if ns.lines < 1_000:
        raise SystemExit("--lines must be >= 1000")
    return Settings(
        out_file=out,
        target_lines=ns.lines,
        seed=ns.seed,
        approx_module_lines=ns.approx_module_lines,
        overwrite=ns.overwrite,
    )


def main() -> None:
    s = parse_args()
    if s.out_file.exists() and not s.overwrite:
        raise SystemExit(f"Refusing to overwrite existing file (use --overwrite): {s.out_file}")

    content = generate(s)
    s.out_file.parent.mkdir(parents=True, exist_ok=True)
    s.out_file.write_text(content, encoding="utf-8")

    # Simple sanity check: exact line count.
    actual_lines = content.count("\n")
    if actual_lines != s.target_lines:
        raise SystemExit(f"BUG: expected {s.target_lines} lines, wrote {actual_lines} lines")

    print(f"Wrote {s.out_file} ({actual_lines} lines)")
    print("Try:")
    print(f"  rustc {s.out_file.name}  # or put it in a crate as src/main.rs")


if __name__ == "__main__":
    main()
