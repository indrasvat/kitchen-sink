#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "browser-use>=0.10.1",
#     "boto3>=1.35.0",
# ]
# ///
"""
ChatGPT Receipt Downloader v5
Using Browser-Use + LLM

Automates monthly download of ChatGPT Plus receipts using your existing
Chrome profile and an LLM to intelligently navigate the billing interface.

v5 Changes:
  - Fixed email attachment flow with working Attach→Browse→Upload→Escape sequence
  - max_actions_per_step=1 for email agent to prevent action batching issues
  - Comprehensive diagnostic logging throughout
  - Improved modularity with separate agent runners
  - Better error handling and failure diagnostics
  - AWS Bedrock support with Claude Opus 4.5 (action name compatibility fixes)
  - AWS_PROFILE support for Bedrock authentication
  - Generous timeouts for large thinking models (10min download, 8min email)

Usage:
  uv run download_chatgpt_receipt_v5.py
  uv run download_chatgpt_receipt_v5.py --email-to=receipts@example.com
  uv run download_chatgpt_receipt_v5.py --provider bedrock  # Uses Claude Opus 4.5
  uv run download_chatgpt_receipt_v5.py --provider openai
  uv run download_chatgpt_receipt_v5.py --headless
  uv run download_chatgpt_receipt_v5.py --help

First run (Anthropic):
  export ANTHROPIC_API_KEY="sk-ant-..."
  uv run download_chatgpt_receipt_v5.py

First run (AWS Bedrock with Claude Opus 4.5):
  export AWS_PROFILE="your-profile"
  uv run download_chatgpt_receipt_v5.py --provider bedrock

Requirements:
  - uv (https://docs.astral.sh/uv/)
  - Google Chrome with an active ChatGPT login
  - API key for Anthropic, OpenAI, Google, or AWS credentials for Bedrock
  - (For email) Microsoft 365 account logged in via Chrome
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
import platform
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import datetime
from enum import StrEnum
from pathlib import Path
from typing import TYPE_CHECKING, Self

if TYPE_CHECKING:
    from browser_use import Browser


# ══════════════════════════════════════════════════════════════════════════════
# CONSTANTS & ENUMS
# ══════════════════════════════════════════════════════════════════════════════


class LLMProvider(StrEnum):
    """Supported LLM providers."""

    ANTHROPIC = "anthropic"
    OPENAI = "openai"
    GOOGLE = "google"
    BEDROCK = "bedrock"


class ExitCode(StrEnum):
    """Exit codes for the script."""

    SUCCESS = "0"
    ENV_ERROR = "1"
    RUNTIME_ERROR = "2"
    USER_ABORT = "3"


class Colors:
    """ANSI escape codes for colored terminal output."""

    RESET = "\033[0m"
    BOLD = "\033[1m"
    RED = "\033[91m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    BLUE = "\033[94m"
    MAGENTA = "\033[95m"
    CYAN = "\033[96m"


# ══════════════════════════════════════════════════════════════════════════════
# SCREEN SIZE DETECTION
# ══════════════════════════════════════════════════════════════════════════════


def get_main_screen_size() -> tuple[int, int]:
    """
    Get the main screen size on macOS using system_profiler.

    Returns:
        Tuple of (width, height) in pixels. Falls back to (2560, 1440) if detection fails.
    """
    try:
        result = subprocess.run(
            ["system_profiler", "SPDisplaysDataType", "-json"],
            capture_output=True,
            text=True,
            check=True,
            timeout=10,
        )
        data = json.loads(result.stdout)
        displays = data.get("SPDisplaysDataType", [{}])[0].get("spdisplays_ndrvs", [])

        for display in displays:
            if display.get("spdisplays_main") == "spdisplays_yes":
                pixels = display.get("_spdisplays_pixels", "2560 x 1440")
                w, h = pixels.split(" x ")
                return int(w), int(h)

        if displays:
            pixels = displays[0].get("_spdisplays_pixels", "2560 x 1440")
            w, h = pixels.split(" x ")
            return int(w), int(h)

    except (subprocess.TimeoutExpired, json.JSONDecodeError, KeyError, ValueError) as e:
        logging.debug(f"Screen size detection failed: {e}")

    return 2560, 1440


def calculate_window_geometry(
    screen_width: int, screen_height: int
) -> tuple[int, int, int, int]:
    """
    Calculate browser window size and position for left 1/3 of screen.

    Returns:
        Tuple of (window_width, window_height, pos_x, pos_y)
    """
    window_width = screen_width // 3
    window_height = screen_height - 150
    pos_x = 50
    pos_y = 50
    return window_width, window_height, pos_x, pos_y


# ══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ══════════════════════════════════════════════════════════════════════════════


@dataclass(frozen=True, slots=True)
class MacOSPaths:
    """Standard macOS application paths."""

    chrome_binary: Path = Path(
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    )
    chrome_user_data: Path = Path.home() / "Library/Application Support/Google/Chrome"
    downloads: Path = Path.home() / "Downloads"
    config_dir: Path = (
        Path.home() / "Library/Application Support/ChatGPTReceiptDownloader"
    )
    cache_dir: Path = Path.home() / "Library/Caches/ChatGPTReceiptDownloader"
    log_dir: Path = Path.home() / "Library/Logs/ChatGPTReceiptDownloader"
    receipts_dir: Path = Path.home() / "Documents/ChatGPT-Receipts"
    state_file: Path = (
        Path.home() / "Library/Application Support/ChatGPTReceiptDownloader/state.json"
    )


@dataclass(slots=True)
class Config:
    """Runtime configuration for the receipt downloader."""

    # LLM settings
    provider: LLMProvider = LLMProvider.ANTHROPIC
    anthropic_model: str = "claude-sonnet-4-20250514"
    openai_model: str = "gpt-4.1-mini"
    google_model: str = "gemini-3-pro-preview"
    bedrock_model: str = "global.anthropic.claude-opus-4-5-20251101-v1:0"
    bedrock_region: str = "us-east-1"

    # Browser settings
    chrome_profile: str = "Default"
    headless: bool = False

    # Execution settings
    # Opus 4.5 is a large thinking model - needs generous timeouts
    max_steps_download: int = 50
    max_steps_email: int = 40
    timeout_download: int = 600  # 10 minutes - Opus 4.5 thinks deeply
    timeout_email: int = 480  # 8 minutes

    # Email settings
    email_to: str | None = None

    # Logging
    log_level: str = "DEBUG"
    save_logs: bool = True

    # Paths
    paths: MacOSPaths = field(default_factory=MacOSPaths)

    @classmethod
    def from_args(cls, args: argparse.Namespace) -> Self:
        """Create config from parsed command-line arguments."""
        return cls(
            provider=LLMProvider(args.provider),
            chrome_profile=args.profile,
            headless=args.headless,
            email_to=args.email_to,
            log_level="INFO" if args.quiet else "DEBUG",
            save_logs=not args.no_log_file,
        )

    @property
    def api_key_env_var(self) -> str:
        """Get the environment variable name for the configured provider."""
        match self.provider:
            case LLMProvider.ANTHROPIC:
                return "ANTHROPIC_API_KEY"
            case LLMProvider.OPENAI:
                return "OPENAI_API_KEY"
            case LLMProvider.GOOGLE:
                return "GOOGLE_API_KEY"
            case LLMProvider.BEDROCK:
                # Bedrock uses AWS credentials - check for profile or access key
                if os.environ.get("AWS_PROFILE"):
                    return "AWS_PROFILE"
                return "AWS_ACCESS_KEY_ID"

    @property
    def model_name(self) -> str:
        """Get the model name for the configured provider."""
        match self.provider:
            case LLMProvider.ANTHROPIC:
                return self.anthropic_model
            case LLMProvider.OPENAI:
                return self.openai_model
            case LLMProvider.GOOGLE:
                return self.google_model
            case LLMProvider.BEDROCK:
                return self.bedrock_model


# ══════════════════════════════════════════════════════════════════════════════
# LOGGING SETUP
# ══════════════════════════════════════════════════════════════════════════════


class ColoredFormatter(logging.Formatter):
    """Custom formatter with colors and box-drawing characters."""

    LEVEL_COLORS = {
        logging.DEBUG: Colors.CYAN,
        logging.INFO: Colors.GREEN,
        logging.WARNING: Colors.YELLOW,
        logging.ERROR: Colors.RED,
        logging.CRITICAL: Colors.MAGENTA,
    }

    def format(self, record: logging.LogRecord) -> str:
        color = self.LEVEL_COLORS.get(record.levelno, Colors.RESET)
        timestamp = datetime.fromtimestamp(record.created).strftime("%H:%M:%S")
        level = f"{record.levelname:<8}"
        return f"{Colors.BLUE}{timestamp}{Colors.RESET} | {color}{level}{Colors.RESET} | {record.getMessage()}"


def setup_logging(config: Config) -> logging.Logger:
    """Configure logging with both console and optional file output."""
    logger = logging.getLogger("chatgpt_receipt")
    logger.setLevel(getattr(logging, config.log_level))
    logger.handlers.clear()

    # Console handler
    console = logging.StreamHandler(sys.stdout)
    console.setLevel(logging.DEBUG)
    console.setFormatter(ColoredFormatter())
    logger.addHandler(console)

    # File handler
    if config.save_logs:
        config.paths.log_dir.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        log_file = config.paths.log_dir / f"receipt_download_v5_{timestamp}.log"

        file_handler = logging.FileHandler(log_file, encoding="utf-8")
        file_handler.setLevel(logging.DEBUG)
        file_handler.setFormatter(
            logging.Formatter(
                fmt="%(asctime)s | %(levelname)-8s | %(message)s",
                datefmt="%Y-%m-%d %H:%M:%S",
            )
        )
        logger.addHandler(file_handler)
        logger.info(f"Log file: {log_file}")

    return logger


# ══════════════════════════════════════════════════════════════════════════════
# ENVIRONMENT VALIDATION
# ══════════════════════════════════════════════════════════════════════════════


@dataclass
class ValidationResult:
    """Result of environment validation."""

    is_valid: bool
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


def validate_environment(config: Config, logger: logging.Logger) -> ValidationResult:
    """Validate that all required components are available."""
    logger.info("=" * 60)
    logger.info("VALIDATING ENVIRONMENT")
    logger.info("=" * 60)

    result = ValidationResult(is_valid=True)

    # Check 1: macOS
    logger.info("[1/5] Checking platform...")
    if platform.system() != "Darwin":
        result.errors.append(
            f"This script is designed for macOS, not {platform.system()}"
        )
        result.is_valid = False
        logger.error(f"      FAIL: Unsupported platform: {platform.system()}")
    else:
        logger.info(f"      OK: macOS {platform.mac_ver()[0]}")

    # Check 2: Chrome Installation
    logger.info("[2/5] Checking Chrome installation...")
    if config.paths.chrome_binary.exists():
        logger.info("      OK: Chrome found")
    else:
        result.errors.append(f"Chrome not found at {config.paths.chrome_binary}")
        result.is_valid = False
        logger.error("      FAIL: Chrome not found at expected path")

    # Check 3: Chrome Profile
    logger.info("[3/5] Checking Chrome profile...")
    profile_path = config.paths.chrome_user_data / config.chrome_profile

    if config.paths.chrome_user_data.exists():
        if profile_path.exists():
            logger.info(f"      OK: Profile '{config.chrome_profile}' exists")
        else:
            available = [
                p.name
                for p in config.paths.chrome_user_data.iterdir()
                if p.is_dir() and (p.name == "Default" or p.name.startswith("Profile"))
            ]
            result.warnings.append(
                f"Profile '{config.chrome_profile}' not found. Available: {available}"
            )
            logger.warning(f"      WARN: Profile '{config.chrome_profile}' not found")
            logger.warning(f"      Available profiles: {', '.join(available)}")
    else:
        result.errors.append("Chrome user data directory not found")
        result.is_valid = False
        logger.error("      FAIL: Chrome user data not found")

    # Check 4: API Key
    logger.info("[4/5] Checking API key...")
    api_key = os.environ.get(config.api_key_env_var, "")

    if api_key:
        masked = f"{api_key[:8]}...{api_key[-4:]}" if len(api_key) > 12 else "***"
        logger.info(f"      OK: {config.api_key_env_var} is set ({masked})")
    else:
        result.errors.append(f"{config.api_key_env_var} environment variable not set")
        result.is_valid = False
        logger.error(f"      FAIL: {config.api_key_env_var} not set")
        logger.error(f"      Run: export {config.api_key_env_var}='your-key'")

    # Check 5: Chrome Running?
    logger.info("[5/5] Checking if Chrome is running...")
    try:
        result_proc = subprocess.run(
            ["pgrep", "-x", "Google Chrome"],
            capture_output=True,
            text=True,
            check=False,
        )
        if result_proc.returncode == 0:
            result.warnings.append(
                "Chrome is currently running - close it for exclusive profile access"
            )
            logger.warning("      WARN: Chrome is running!")
            logger.warning(
                "      Close Chrome before proceeding for reliable automation"
            )
        else:
            logger.info("      OK: Chrome is not running")
    except FileNotFoundError:
        logger.warning(
            "      WARN: Could not check if Chrome is running (pgrep not found)"
        )

    # Summary
    logger.info("-" * 60)
    if result.is_valid:
        if result.warnings:
            logger.warning(f"Validation passed with {len(result.warnings)} warning(s)")
        else:
            logger.info("Validation passed")
    else:
        logger.error(f"Validation failed with {len(result.errors)} error(s)")
    logger.info("-" * 60)

    return result


# ══════════════════════════════════════════════════════════════════════════════
# STATE MANAGEMENT (Idempotency)
# ══════════════════════════════════════════════════════════════════════════════


def get_current_month() -> str:
    """Get current month in YYYY-MM format."""
    return datetime.now().strftime("%Y-%m")


def load_state(config: Config) -> dict:
    """Load state from state file."""
    state_file = config.paths.state_file
    if state_file.exists():
        try:
            return json.loads(state_file.read_text())
        except (json.JSONDecodeError, OSError):
            return {}
    return {}


def save_state(config: Config, state: dict) -> None:
    """Save state to state file."""
    state_file = config.paths.state_file
    state_file.parent.mkdir(parents=True, exist_ok=True)
    state_file.write_text(json.dumps(state, indent=2))


def was_email_sent_this_month(config: Config, logger: logging.Logger) -> bool:
    """Check if email was already sent this month."""
    current_month = get_current_month()
    state = load_state(config)
    last_email = state.get("last_email_sent_month", "")

    if last_email == current_month:
        logger.info(f"Email already sent for {current_month} (per state file)")
        return True
    return False


def record_email_sent(config: Config, logger: logging.Logger) -> None:
    """Record that email was successfully sent this month."""
    current_month = get_current_month()
    state = load_state(config)

    state["last_email_sent_month"] = current_month
    state["last_email_sent_timestamp"] = datetime.now().isoformat()

    save_state(config, state)
    logger.info(f"Recorded: email sent for {current_month}")


def record_full_success(config: Config, logger: logging.Logger) -> None:
    """Record full success (download + email) for this month."""
    current_month = get_current_month()
    state = load_state(config)

    state["last_success_month"] = current_month
    state["last_success_timestamp"] = datetime.now().isoformat()
    state["last_email_sent_month"] = current_month
    state["run_count"] = state.get("run_count", 0) + 1

    save_state(config, state)
    logger.info(f"Recorded: full success for {current_month}")


# ══════════════════════════════════════════════════════════════════════════════
# LLM INITIALIZATION
# ══════════════════════════════════════════════════════════════════════════════


# Action name mapping for Bedrock models
# Claude models via Bedrock sometimes output action names that don't match
# browser-use's schema. This maps common mismatches to correct names.
# Valid browser-use actions: done, search, navigate, go_back, wait, click, input,
# upload_file, switch, close, extract, scroll, send_keys, find_text, screenshot,
# dropdown_options, select_dropdown, write_file, replace_file, read_file, evaluate
ACTION_NAME_FIXES = {
    # Tab switching
    "switch_tab": "switch",
    "switch_tabs": "switch",
    # Navigation
    "go_to_url": "navigate",
    "goto": "navigate",
    "open_url": "navigate",
    # Input/typing - model sometimes uses input_text instead of input
    "input_text": "input",
    "type": "input",
    "type_text": "input",
    # File upload - model sometimes uses file_path instead of path
    "file_path": "path",
    "filepath": "path",
}


def fix_action_names_in_data(data: dict | list) -> dict | list:
    """
    Recursively fix action names in LLM response data.

    Claude models via AWS Bedrock sometimes output action names like 'switch_tab'
    when browser-use expects 'switch'. This function fixes those mismatches.
    """
    if isinstance(data, list):
        return [
            fix_action_names_in_data(item) if isinstance(item, (dict, list)) else item
            for item in data
        ]

    if not isinstance(data, dict):
        return data

    fixed = {}
    for key, value in data.items():
        # Check if this key is an action that needs fixing
        if key in ACTION_NAME_FIXES:
            new_key = ACTION_NAME_FIXES[key]
            fixed[new_key] = (
                fix_action_names_in_data(value)
                if isinstance(value, (dict, list))
                else value
            )
        elif isinstance(value, (dict, list)):
            fixed[key] = fix_action_names_in_data(value)
        else:
            fixed[key] = value

    return fixed


def create_patched_bedrock_class(logger: logging.Logger):
    """
    Create a patched version of ChatAWSBedrock that fixes action names.

    This patches the Pydantic model_validate method to fix action names
    before validation occurs.
    """
    from browser_use.llm.aws.chat_bedrock import ChatAWSBedrock

    class PatchedChatAWSBedrock(ChatAWSBedrock):
        """ChatAWSBedrock with action name fixing for browser-use compatibility."""

        _action_logger: logging.Logger | None = None

        def __init__(
            self, *args, action_logger: logging.Logger | None = None, **kwargs
        ):
            super().__init__(*args, **kwargs)
            self._action_logger = action_logger

        async def ainvoke(self, messages, output_format=None):
            """Override ainvoke to fix action names before validation."""
            if output_format is not None:
                # Wrap the output_format's model_validate to fix action names first
                original_validate = output_format.model_validate
                action_logger = self._action_logger  # Capture for closure

                def patched_validate(obj, *args, **kwargs):
                    if isinstance(obj, dict):
                        # Fix action names in the 'action' field
                        if "action" in obj and isinstance(obj["action"], list):
                            fixed_actions = fix_action_names_in_data(obj["action"])
                            if fixed_actions != obj["action"]:
                                if action_logger:
                                    action_logger.debug(
                                        f"Fixed action names: {obj['action']} -> {fixed_actions}"
                                    )
                                obj = {**obj, "action": fixed_actions}
                    return original_validate(obj, *args, **kwargs)

                # Temporarily patch the model_validate method
                output_format.model_validate = patched_validate

            try:
                return await super().ainvoke(messages, output_format)
            finally:
                # Restore original method
                if output_format is not None:
                    output_format.model_validate = original_validate

    return PatchedChatAWSBedrock


def get_llm(config: Config, logger: logging.Logger):
    """Initialize the LLM based on configuration."""
    logger.debug(
        f"Initializing LLM: provider={config.provider.value}, model={config.model_name}"
    )

    match config.provider:
        case LLMProvider.ANTHROPIC:
            from browser_use import ChatAnthropic

            llm = ChatAnthropic(
                model=config.anthropic_model,
                timeout=60.0,
                max_retries=2,
            )

        case LLMProvider.OPENAI:
            from browser_use import ChatOpenAI

            llm = ChatOpenAI(
                model=config.openai_model,
                timeout=60.0,
                max_retries=2,
            )

        case LLMProvider.GOOGLE:
            from browser_use import ChatGoogle

            llm = ChatGoogle(
                model=config.google_model,
            )

        case LLMProvider.BEDROCK:
            import boto3

            # Use patched class that fixes action name mismatches
            # (Claude via Bedrock outputs 'switch_tab' but browser-use expects 'switch')
            PatchedChatAWSBedrock = create_patched_bedrock_class(logger)

            # Create boto3 session - this respects AWS_PROFILE env var
            aws_profile = os.environ.get("AWS_PROFILE")
            if aws_profile:
                logger.info(f"Using AWS profile: {aws_profile}")
                session = boto3.Session(
                    profile_name=aws_profile, region_name=config.bedrock_region
                )
            else:
                logger.debug("Using default AWS credential chain")
                session = boto3.Session(region_name=config.bedrock_region)

            llm = PatchedChatAWSBedrock(
                model=config.bedrock_model,
                aws_region=config.bedrock_region,
                session=session,
                action_logger=logger,
            )

    logger.info(f"LLM initialized: {config.provider.value} / {config.model_name}")
    return llm


# ══════════════════════════════════════════════════════════════════════════════
# BROWSER CONFIGURATION
# ══════════════════════════════════════════════════════════════════════════════


def get_browser(config: Config, logger: logging.Logger) -> "Browser":
    """Configure browser to use existing Chrome profile."""
    from browser_use import Browser, BrowserProfile

    logger.info("=" * 60)
    logger.info("CONFIGURING BROWSER")
    logger.info("=" * 60)

    # Screen detection
    screen_width, screen_height = get_main_screen_size()
    window_width, window_height, pos_x, pos_y = calculate_window_geometry(
        screen_width, screen_height
    )

    logger.info(f"   Binary: {config.paths.chrome_binary}")
    logger.info(f"   User data: {config.paths.chrome_user_data}")
    logger.info(f"   Profile: {config.chrome_profile}")
    logger.info(f"   Headless: {config.headless}")
    logger.info(f"   Screen: {screen_width}x{screen_height}")
    logger.info(f"   Window: {window_width}x{window_height} at ({pos_x}, {pos_y})")

    extra_args = [
        "--disable-blink-features=AutomationControlled",
        "--no-first-run",
        "--no-default-browser-check",
        "--enable-javascript",
        "--enable-features=NetworkService,NetworkServiceInProcess",
        "--disable-features=IsolateOrigins,site-per-process,TranslateUI",
        "--disable-features=SameSiteByDefaultCookies,CookiesWithoutSameSiteMustBeSecure",
        "--disable-web-security",
        "--allow-running-insecure-content",
        "--disable-gpu-sandbox",
        "--enable-webgl",
        "--disable-popup-blocking",
    ]

    browser_config = BrowserProfile(
        headless=config.headless,
        browser_binary_path=str(config.paths.chrome_binary),
        user_data_dir=str(config.paths.chrome_user_data),
        profile_directory=config.chrome_profile,
        extra_browser_args=extra_args,
        window_size={"width": window_width, "height": window_height},
        window_position={"width": pos_x, "height": pos_y},
        minimum_wait_page_load_time=5.0,  # Increased for complex pages
        wait_for_network_idle_page_load_time=5.0,  # Increased for slow-loading pages
    )

    browser = Browser(browser_profile=browser_config)
    logger.info("   Browser configured successfully")

    return browser


# ══════════════════════════════════════════════════════════════════════════════
# TASK PROMPTS
# ══════════════════════════════════════════════════════════════════════════════


def build_download_task_prompt() -> str:
    """Build the task prompt for downloading the receipt."""
    current_date = datetime.now().strftime("%B %d, %Y")

    return f"""
You are helping to download the most recent ChatGPT Plus subscription receipt.

TODAY'S DATE: {current_date}

IMPORTANT CONTEXT:
- The user is already logged into ChatGPT (using their existing Chrome profile)
- We want to download the MOST RECENT receipt/invoice from billing history
- The billing portal is powered by Stripe

===============================================================================
STEP-BY-STEP INSTRUCTIONS
===============================================================================

STEP 1: Navigate to ChatGPT
---------------------------
- Go to https://chatgpt.com
- Wait for the page to fully load
- Confirm you see the ChatGPT interface with the sidebar

STEP 2: Open Account Menu
-------------------------
- Look at the BOTTOM LEFT of the sidebar
- Find and click on the user's name/account icon (it shows the account name)
- A popup menu should appear with options

STEP 3: Go to Settings -> Account
---------------------------------
- In the popup menu, click "Settings"
- Once in Settings, look for "Account" in the left navigation
- Click on "Account" to see account details

STEP 4: Access Payment Management (CRITICAL)
--------------------------------------------
- In the Account section, find "Payment"
- Click the "Manage" button next to Payment ONLY ONCE
- CRITICAL: After clicking "Manage", the page will redirect to Stripe
- WAIT at least 10 seconds for the Stripe page to fully load
- DO NOT click "Manage" again - it only needs ONE click
- VERIFY: Check the URL has changed to pay.openai.com before proceeding

STEP 5: Find Invoice History (on Stripe billing page)
-----------------------------------------------------
- You are now on the Stripe billing page (pay.openai.com domain)
- WAIT for the page to fully load - this can take 5-10 seconds!
- Look for "INVOICE HISTORY" section (usually near the bottom)
- You should see a list of past invoices with dates and amounts

STEP 6: Select Most Recent Invoice (OPENS IN NEW TAB!)
------------------------------------------------------
- In the INVOICE HISTORY section, click on the TOPMOST (most recent) invoice
- IMPORTANT: This will open the invoice detail page in a NEW BROWSER TAB
- After clicking, you MUST SWITCH TO THE NEW TAB to continue
- Use the switch_tab action to switch to the newly opened tab (invoice.stripe.com)
- WAIT at least 8 seconds for the invoice detail page to fully load

STEP 7: Download the Receipt
----------------------------
- You should now be on the invoice detail page in the NEW TAB
- The URL will be like: invoice.stripe.com/i/acct_xxx/...
- There are TWO buttons near the bottom:
  1. "Download invoice" (outline/secondary button on the left)
  2. "Download receipt" (filled/primary button on the right - THIS IS THE ONE WE WANT)
- Click the "Download receipt" button
- Wait for the PDF to start downloading

STEP 8: Confirm Success
-----------------------
- Verify the download started
- Report the invoice date and amount in your final message

===============================================================================
CRITICAL RULES - MUST FOLLOW
===============================================================================

1. NEVER click the same button twice in a row
   - If you clicked a button and get "element not found", the page ALREADY NAVIGATED
   - DO NOT retry the click - instead, check where you are now and proceed

2. After clicking "Manage" button:
   - WAIT 10 seconds
   - CHECK the URL - it should now be pay.openai.com
   - If URL changed, proceed to Step 5 - DO NOT click Manage again

3. After clicking an invoice row:
   - A NEW TAB will open with invoice.stripe.com
   - You MUST switch to the new tab using switch_tab action
   - DO NOT click the invoice row again

4. The Stripe billing page loads SLOWLY
   - Wait for "INVOICE HISTORY" text to appear before clicking
   - If page seems empty, wait 10 seconds and take a fresh snapshot

SUCCESS CRITERIA:
- Downloaded the most recent ChatGPT Plus receipt PDF
- Report the invoice date and amount when complete
"""


def build_email_task_prompt(
    email_to: str, receipt_path: str, invoice_month_year: str
) -> str:
    """
    Build the task prompt for emailing the receipt via Outlook.

    v5: Working flow with Attach->Browse->Upload->Escape sequence.
    """
    return f"""
You are helping to email a ChatGPT Plus receipt via Microsoft Outlook.

TASK PARAMETERS:
- Recipient email: {email_to}
- Receipt file to attach: {receipt_path}
- Invoice period: {invoice_month_year}

===============================================================================
STEP-BY-STEP INSTRUCTIONS
===============================================================================

STEP 1: Navigate directly to Outlook Web
-----------------------------------------
- Go to: https://outlook.office.com/mail/
- Wait for the page to fully load (this may take 5-10 seconds)
- The user should already be logged in via their Chrome profile
- You should see the Outlook inbox with "New mail" button visible at the top left
- If you see a sign-in page, wait - auto-login should complete

STEP 2: Create New Email
------------------------
- In Outlook, look for the "New mail" button
- It's typically at the top left of the interface
- Click "New mail" to start composing a new email
- Wait for the compose window to appear

STEP 3: Enter Recipient
-----------------------
- Find the "To" field in the compose window
- Click on the "To" field
- Type the email address: {email_to}
- Press Tab or click elsewhere to confirm the address

STEP 4: Enter Subject
---------------------
- Find the "Subject" field (usually below the To field)
- Click on the Subject field
- Type exactly: ChatGPT Receipt for {invoice_month_year}

STEP 5: Attach the Receipt
--------------------------
This is a STRICT 5-action sequence. Do ONE action, then STOP and observe.

ACTION 5.1: Click Attach button
- Click the paperclip "Attach file" button ONCE
- STOP. Wait for dropdown menu to appear.

ACTION 5.2: Click "Browse this computer"
- Click "Browse this computer" in the dropdown
- STOP. A file input element will become available.

ACTION 5.3: Upload the file
- Find input element with data-testid="local-computer-filein"
- Use upload_file action with path: {receipt_path}
- STOP. Do NOT click anything else yet.

ACTION 5.4: Press Escape key
- Use send_keys with key="Escape" to close any modal
- STOP. Wait 3 seconds.

ACTION 5.5: Verify attachment
- Take a snapshot and look for the attachment chip showing the filename
- The attachment appears below the Subject line as a clickable chip
- If you see the filename, proceed to STEP 6
- If NOT visible, repeat from ACTION 5.1 (max 2 attempts)

STEP 6: Send Email (ONLY after seeing attachment)
-------------------------------------------------
PREREQUISITE: You MUST have seen the attachment filename in the compose window.

ACTION 6.1: Click Send
- Click the "Send" button exactly ONCE
- The compose window will close

ACTION 6.2: Call done() IMMEDIATELY
- Do NOT click anything else
- Do NOT navigate anywhere
- Just call: done(text="Email sent successfully with attachment", success=True)

===============================================================================
CRITICAL RULES
===============================================================================

1. ONE action at a time - click once, then observe the result
2. After upload_file -> MUST press Escape -> MUST verify attachment visible
3. NEVER click Send unless you SEE the attachment filename in the compose window
4. If Send fails or nothing happens, do NOT retry - check what went wrong first

===============================================================================
FAILURE CONDITIONS
===============================================================================

Call done(success=False) if:
- Attachment not visible after 2 upload attempts
- Send button doesn't work after clicking once
- Any unexpected error

DO NOT send an email without a visible attachment. Report failure instead.
"""


# ══════════════════════════════════════════════════════════════════════════════
# AGENT EXECUTION - DOWNLOAD
# ══════════════════════════════════════════════════════════════════════════════


async def run_download_agent(
    config: Config, logger: logging.Logger, browser: "Browser"
) -> tuple[bool, str, list[Path], str]:
    """
    Execute the browser automation agent to download the receipt.

    Returns:
        Tuple of (success, message, downloaded_files, invoice_month_year)
    """
    from browser_use import Agent

    logger.info("=" * 60)
    logger.info("RUNNING DOWNLOAD AGENT")
    logger.info("=" * 60)

    llm = get_llm(config, logger)
    task = build_download_task_prompt()

    logger.info("Starting browser automation for receipt download...")
    if not config.headless:
        logger.info("   Watch the Chrome window to see the agent work!")

    agent = Agent(
        task=task,
        llm=llm,
        browser=browser,
        max_actions_per_step=2,
        wait_between_actions=5.0,  # Give pages time to settle between actions
    )

    downloaded_files: list[Path] = []
    invoice_month_year = datetime.now().strftime("%B %Y")

    try:
        logger.info(
            f"Agent working... (max {config.max_steps_download} steps, timeout {config.timeout_download}s)"
        )

        result = await asyncio.wait_for(
            agent.run(max_steps=config.max_steps_download),
            timeout=config.timeout_download,
        )

        logger.info("-" * 60)
        logger.info("Download agent completed!")

        # Collect downloaded files (v5: correct attribute location)
        if hasattr(agent, "available_file_paths") and agent.available_file_paths:
            logger.debug(f"Agent available_file_paths: {agent.available_file_paths}")
            for file_path in agent.available_file_paths:
                p = Path(file_path)
                if p.exists():
                    downloaded_files.append(p)
                    logger.info(f"   Downloaded: {p.name}")

        if result:
            result_str = str(result)

            # Extract month/year from result
            month_pattern = r"(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{0,2},?\s*(\d{4})"
            match = re.search(month_pattern, result_str)
            if match:
                invoice_month_year = f"{match.group(1)} {match.group(2)}"
                logger.info(f"   Invoice period: {invoice_month_year}")

            log_result = (
                result_str[:500] + "..." if len(result_str) > 500 else result_str
            )
            logger.info(f"   Result: {log_result}")
            return True, result_str, downloaded_files, invoice_month_year
        else:
            logger.warning("Agent completed but returned no result")
            return False, "No result returned", downloaded_files, invoice_month_year

    except asyncio.TimeoutError:
        logger.error(f"Download agent timed out after {config.timeout_download}s")
        return False, "Timeout", downloaded_files, invoice_month_year

    except Exception as e:
        logger.error(f"Download agent failed: {type(e).__name__}: {e}")
        import traceback

        logger.debug(f"Traceback: {traceback.format_exc()}")
        return False, str(e), downloaded_files, invoice_month_year


# ══════════════════════════════════════════════════════════════════════════════
# AGENT EXECUTION - EMAIL
# ══════════════════════════════════════════════════════════════════════════════


async def run_email_agent(
    config: Config,
    logger: logging.Logger,
    browser: "Browser",
    receipt_path: Path,
    invoice_month_year: str,
) -> tuple[bool, str]:
    """
    Execute the browser automation agent to email the receipt.

    v5: Uses max_actions_per_step=1 to ensure sequential attachment flow.

    Returns:
        Tuple of (success, message)
    """
    from browser_use import Agent

    logger.info("=" * 60)
    logger.info("RUNNING EMAIL AGENT")
    logger.info("=" * 60)
    logger.info(f"   To: {config.email_to}")
    logger.info(f"   Attachment: {receipt_path}")
    logger.info(f"   Attachment exists: {receipt_path.exists()}")
    logger.info(
        f"   Attachment size: {receipt_path.stat().st_size if receipt_path.exists() else 'N/A'} bytes"
    )
    logger.info(f"   Period: {invoice_month_year}")

    llm = get_llm(config, logger)
    task = build_email_task_prompt(
        email_to=config.email_to,
        receipt_path=str(receipt_path),
        invoice_month_year=invoice_month_year,
    )

    # v5: max_actions_per_step=1 is CRITICAL for attachment flow
    # This prevents the agent from batching actions that need to be sequential
    agent = Agent(
        task=task,
        llm=llm,
        browser=browser,
        max_actions_per_step=1,  # Force one action at a time for attachment flow
        wait_between_actions=6.0,  # Give Outlook UI time to settle between actions
        available_file_paths=[str(receipt_path)],
    )

    logger.info("Agent configured with max_actions_per_step=1 (attachment flow)")
    logger.info(
        f"Agent working... (max {config.max_steps_email} steps, timeout {config.timeout_email}s)"
    )

    try:
        result = await asyncio.wait_for(
            agent.run(max_steps=config.max_steps_email),
            timeout=config.timeout_email,
        )

        logger.info("-" * 60)
        logger.info("Email agent completed!")

        if result:
            result_str = str(result)
            log_result = (
                result_str[:500] + "..." if len(result_str) > 500 else result_str
            )
            logger.info(f"   Result: {log_result}")

            # Check for failure indicators
            if (
                "FAILED" in result_str.upper()
                or "could not attach" in result_str.lower()
            ):
                logger.error("Email agent reported attachment failure")
                return False, result_str

            return True, result_str
        else:
            logger.warning("Email agent completed but returned no result")
            return False, "No result returned"

    except asyncio.TimeoutError:
        logger.error(f"Email agent timed out after {config.timeout_email}s")
        return False, "Timeout"

    except Exception as e:
        logger.error(f"Email agent failed: {type(e).__name__}: {e}")
        import traceback

        logger.debug(f"Traceback: {traceback.format_exc()}")
        return False, str(e)


# ══════════════════════════════════════════════════════════════════════════════
# MAIN AGENT ORCHESTRATION
# ══════════════════════════════════════════════════════════════════════════════


async def run_agent(
    config: Config, logger: logging.Logger
) -> tuple[bool, str, list[Path]]:
    """
    Execute the browser automation agent(s).

    Note: browser-use resets the browser session after each agent completes,
    so we need to create a NEW browser instance for each agent.

    Returns:
        Tuple of (success, message, downloaded_files)
    """
    downloaded_files: list[Path] = []

    # Step 1: Download the receipt (with its own browser instance)
    logger.info("Creating browser for download agent...")
    download_browser = get_browser(config, logger)

    try:
        (
            download_success,
            download_message,
            downloaded_files,
            invoice_month_year,
        ) = await run_download_agent(config, logger, download_browser)
    finally:
        logger.info("Closing download browser...")
        try:
            if hasattr(download_browser, "stop"):
                await download_browser.stop()
            logger.info("Download browser closed")
        except Exception as e:
            logger.debug(f"Download browser close note: {e}")

    if not download_success:
        logger.error(f"Download failed: {download_message}")
        return False, download_message, downloaded_files

    logger.info(f"Download succeeded. Files: {[str(f) for f in downloaded_files]}")

    # Step 2: Email the receipt (if --email-to is specified)
    # IMPORTANT: Create a NEW browser instance since the previous one was reset
    if config.email_to:
        # IDEMPOTENCY CHECK: Don't send duplicate emails
        if was_email_sent_this_month(config, logger):
            logger.info("Skipping email - already sent this month")
            return (
                True,
                f"Receipt downloaded. Email skipped (already sent this month to {config.email_to})",
                downloaded_files,
            )

        if downloaded_files:
            receipt_path = downloaded_files[0]

            # Verify the file still exists before proceeding
            if not receipt_path.exists():
                logger.error(f"Receipt file no longer exists: {receipt_path}")
                return (
                    True,
                    "Receipt downloaded but file disappeared before email",
                    downloaded_files,
                )

            logger.info("-" * 60)
            logger.info(f"Proceeding to email receipt to: {config.email_to}")
            logger.info(f"Using receipt file: {receipt_path}")
            logger.info("-" * 60)

            # Create a NEW browser instance for email agent
            logger.info("Creating NEW browser for email agent...")
            email_browser = get_browser(config, logger)

            try:
                email_success, email_message = await run_email_agent(
                    config, logger, email_browser, receipt_path, invoice_month_year
                )
            finally:
                logger.info("Closing email browser...")
                try:
                    if hasattr(email_browser, "stop"):
                        await email_browser.stop()
                    logger.info("Email browser closed")
                except Exception as e:
                    logger.debug(f"Email browser close note: {e}")

            if email_success:
                # IMMEDIATELY record email sent to prevent duplicates on retry
                record_email_sent(config, logger)
                record_full_success(config, logger)
                return (
                    True,
                    f"Receipt downloaded and emailed to {config.email_to}",
                    downloaded_files,
                )
            else:
                logger.warning(f"Email failed: {email_message}")
                return (
                    True,
                    f"Receipt downloaded but email failed: {email_message}",
                    downloaded_files,
                )
        else:
            logger.warning("No downloaded files found for email attachment")
            return (
                True,
                "Receipt downloaded but no file found for email",
                downloaded_files,
            )

    return download_success, download_message, downloaded_files


# ══════════════════════════════════════════════════════════════════════════════
# POST-PROCESSING
# ══════════════════════════════════════════════════════════════════════════════


def find_recent_receipts(
    config: Config,
    logger: logging.Logger,
    agent_downloads: list[Path] | None = None,
) -> list[Path]:
    """Find recently downloaded receipt PDFs."""
    logger.info("=" * 60)
    logger.info("CHECKING DOWNLOADS")
    logger.info("=" * 60)

    recent_pdfs: list[Path] = []
    seen_inodes: set[tuple[int, int]] = set()  # (device, inode) to detect same file

    def add_if_unique(pdf: Path, source: str) -> bool:
        """Add PDF if it's a unique file (not already seen via different path)."""
        try:
            stat = pdf.stat()
            file_id = (stat.st_dev, stat.st_ino)
            if file_id in seen_inodes:
                logger.debug(
                    f"   Skipping duplicate: {pdf.name} (same file as existing)"
                )
                return False
            seen_inodes.add(file_id)
            recent_pdfs.append(pdf)
            logger.info(f"   {source}: {pdf.name}")
            return True
        except OSError:
            return False

    # First, check files directly returned by the agent
    if agent_downloads:
        for pdf in agent_downloads:
            if pdf.exists() and pdf.suffix.lower() == ".pdf":
                add_if_unique(pdf, "Agent download")

    # Also check common download locations as fallback
    search_dirs = [
        config.paths.downloads,
        config.paths.receipts_dir,
        Path("/tmp"),
    ]

    cutoff = datetime.now().timestamp() - 300  # Last 5 minutes
    keywords = {"receipt", "invoice", "openai", "stripe", "chatgpt"}

    for directory in search_dirs:
        if not directory.exists():
            continue

        logger.debug(f"   Searching: {directory}")

        for pdf in directory.glob("*.pdf"):
            try:
                if pdf.stat().st_mtime > cutoff:
                    name_lower = pdf.name.lower()
                    if any(kw in name_lower for kw in keywords):
                        add_if_unique(pdf, "Found")
            except OSError:
                continue

        # Search browser-use temp download subdirs
        for subdir in directory.glob("browser-use-downloads-*"):
            if subdir.is_dir():
                for pdf in subdir.glob("*.pdf"):
                    try:
                        if pdf.stat().st_mtime > cutoff:
                            add_if_unique(pdf, "Found in temp")
                    except OSError:
                        continue

    if recent_pdfs:
        logger.info(f"Found {len(recent_pdfs)} recent receipt(s)")
    else:
        logger.warning("No recent receipt PDFs found")
        logger.info("   Check your browser's default Downloads folder")

    return recent_pdfs


def archive_receipts(
    files: list[Path], config: Config, logger: logging.Logger
) -> list[Path]:
    """Move receipts to archive folder with dated filenames."""
    if not files:
        return []

    config.paths.receipts_dir.mkdir(parents=True, exist_ok=True)
    archived: list[Path] = []

    for pdf in files:
        month_year = datetime.now().strftime("%Y-%m")
        new_name = f"ChatGPT-Plus-Receipt-{month_year}.pdf"
        dest = config.paths.receipts_dir / new_name

        counter = 1
        while dest.exists():
            new_name = f"ChatGPT-Plus-Receipt-{month_year}-{counter}.pdf"
            dest = config.paths.receipts_dir / new_name
            counter += 1

        try:
            shutil.move(str(pdf), str(dest))
            logger.info(f"   Archived: {dest}")
            archived.append(dest)
        except Exception as e:
            logger.error(f"   Failed to archive {pdf}: {e}")

    return archived


# ══════════════════════════════════════════════════════════════════════════════
# CLI ARGUMENT PARSING
# ══════════════════════════════════════════════════════════════════════════════


def parse_args() -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description="Download ChatGPT Plus receipts automatically (v5 - robust email)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  uv run download_chatgpt_receipt_v5.py
  uv run download_chatgpt_receipt_v5.py --email-to=receipts@example.com
  uv run download_chatgpt_receipt_v5.py --provider openai
  uv run download_chatgpt_receipt_v5.py --provider openai --profile "Profile 2"
  uv run download_chatgpt_receipt_v5.py --headless --quiet

Environment Variables:
  ANTHROPIC_API_KEY    Required if using Anthropic (default)
  OPENAI_API_KEY       Required if using OpenAI
  GOOGLE_API_KEY       Required if using Google
        """,
    )

    parser.add_argument(
        "--provider",
        "-p",
        choices=["anthropic", "openai", "google", "bedrock"],
        default="anthropic",
        help="LLM provider to use (default: anthropic). Bedrock uses Claude Opus 4.5 via AWS.",
    )

    parser.add_argument(
        "--profile",
        default="Default",
        help="Chrome profile name (default: Default)",
    )

    parser.add_argument(
        "--headless",
        action="store_true",
        help="Run browser in headless mode (invisible)",
    )

    parser.add_argument(
        "--quiet",
        "-q",
        action="store_true",
        help="Reduce logging verbosity",
    )

    parser.add_argument(
        "--no-log-file",
        action="store_true",
        help="Don't save logs to file",
    )

    parser.add_argument(
        "--auto",
        "-y",
        action="store_true",
        help="Skip confirmation prompt (for scheduled runs)",
    )

    parser.add_argument(
        "--email-to",
        metavar="EMAIL",
        help="Email address to send the receipt to (uses Outlook via M365)",
    )

    return parser.parse_args()


# ══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ══════════════════════════════════════════════════════════════════════════════


def print_banner():
    """Print the startup banner."""
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print()
    print(f"{Colors.CYAN}+{'=' * 60}+{Colors.RESET}")
    print(
        f"{Colors.CYAN}|{Colors.BOLD}{'ChatGPT Receipt Downloader v5':^60}{Colors.RESET}{Colors.CYAN}|{Colors.RESET}"
    )
    print(f"{Colors.CYAN}|{now:^60}|{Colors.RESET}")
    print(f"{Colors.CYAN}+{'=' * 60}+{Colors.RESET}")
    print()


async def async_main() -> int:
    """Async main entry point."""
    args = parse_args()
    config = Config.from_args(args)

    print_banner()

    # Setup logging
    logger = setup_logging(config)
    logger.info("ChatGPT Receipt Downloader v5 starting")
    logger.info(f"   Provider: {config.provider.value}")
    logger.info(f"   Model: {config.model_name}")

    if config.email_to:
        logger.info(f"   Email mode: will send to {config.email_to}")

    # Suppress duplicate logging from browser-use library
    for lib_logger_name in [
        "browser_use",
        "Agent",
        "tools",
        "BrowserSession",
        "utils",
        "bubus",
    ]:
        lib_logger = logging.getLogger(lib_logger_name)
        lib_logger.setLevel(logging.INFO)

    # Validate environment
    validation = validate_environment(config, logger)
    if not validation.is_valid:
        logger.error("Cannot proceed due to environment issues")
        for error in validation.errors:
            logger.error(f"   - {error}")
        return int(ExitCode.ENV_ERROR)

    # Confirmation prompt (unless --auto)
    if not args.auto:
        print()
        logger.info(
            f"{Colors.YELLOW}Make sure Chrome is CLOSED before proceeding!{Colors.RESET}"
        )
        print()
        try:
            response = (
                input(f"{Colors.BOLD}Ready to proceed? [Y/n]: {Colors.RESET}")
                .strip()
                .lower()
            )
            if response and response != "y":
                logger.info("Aborted by user")
                return int(ExitCode.USER_ABORT)
        except (KeyboardInterrupt, EOFError):
            print()
            logger.info("Aborted by user")
            return int(ExitCode.USER_ABORT)

    print()

    # Run the agent
    agent_downloads: list[Path] = []
    try:
        success, message, agent_downloads = await run_agent(config, logger)
    except KeyboardInterrupt:
        logger.info("\nInterrupted by user")
        return int(ExitCode.USER_ABORT)

    # Post-processing
    downloaded = find_recent_receipts(config, logger, agent_downloads)
    archived = archive_receipts(downloaded, config, logger)

    # Summary
    logger.info("=" * 60)
    logger.info("SUMMARY")
    logger.info("=" * 60)

    if success and archived:
        logger.info("SUCCESS: Receipt downloaded and archived!")
        for path in archived:
            logger.info(f"   {path}")
        if config.email_to and "emailed" in message.lower():
            logger.info(f"   Email sent to: {config.email_to}")
        elif config.email_to:
            logger.warning(f"   Email to {config.email_to} may not have been sent")
            logger.info(f"   Message: {message}")
        return int(ExitCode.SUCCESS)
    elif success:
        logger.warning("PARTIAL: Agent reported success but no file found locally")
        logger.warning("   Check your browser's default Downloads folder")
        return int(ExitCode.SUCCESS)
    else:
        logger.error("FAILED: Could not download receipt")
        logger.error(f"   Reason: {message}")
        return int(ExitCode.RUNTIME_ERROR)


def main() -> int:
    """Main entry point."""
    return asyncio.run(async_main())


if __name__ == "__main__":
    sys.exit(main())
