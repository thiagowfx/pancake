#!/usr/bin/env python3
"""
Playwright automation script for AWS SSO login.

This script automates the browser interaction required for AWS SSO authentication.
It navigates to the verification URL, fills in credentials, and completes the login flow.
"""

import argparse
import sys
from pathlib import Path

try:
    from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeout
except ImportError:
    print("Error: playwright library not found", file=sys.stderr)
    print("Install with: pip install playwright && playwright install chromium", file=sys.stderr)
    sys.exit(1)


def parse_args():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Automate AWS SSO login using headless browser"
    )
    parser.add_argument(
        "verification_url",
        help="AWS SSO verification URL from 'aws sso login --no-browser'"
    )
    parser.add_argument(
        "sso_password",
        help="AWS SSO password (retrieve from 1Password or provide directly)"
    )
    parser.add_argument(
        "--username",
        help="AWS SSO username/email (if required by your IdP)",
        default=None
    )
    parser.add_argument(
        "--headless",
        action="store_true",
        default=True,
        help="Run browser in headless mode (default: true)"
    )
    parser.add_argument(
        "--no-headless",
        dest="headless",
        action="store_false",
        help="Run browser in visible mode for debugging"
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=60000,
        help="Timeout in milliseconds for page operations (default: 60000)"
    )
    return parser.parse_args()


def aws_sso_login(verification_url, sso_password, username=None, headless=True, timeout=60000):
    """
    Automate AWS SSO login using Playwright.

    Args:
        verification_url: AWS SSO verification URL
        sso_password: SSO password
        username: Optional username (some IdPs require it)
        headless: Run browser in headless mode
        timeout: Timeout for page operations in milliseconds

    Returns:
        True if login successful, False otherwise
    """
    # Store browser state in user's home directory
    user_data_dir = Path.home() / ".aws_login_browser_data"
    user_data_dir.mkdir(exist_ok=True)

    try:
        with sync_playwright() as playwright:
            # Launch browser with persistent context to remember sessions
            browser = playwright.chromium.launch_persistent_context(
                user_data_dir=str(user_data_dir),
                headless=headless,
                args=[
                    "--no-sandbox",
                    "--disable-dev-shm-usage",
                ]
            )

            page = browser.pages[0] if browser.pages else browser.new_page()
            page.set_default_timeout(timeout)

            print(f"Navigating to: {verification_url}")
            page.goto(verification_url)

            # Wait for page to load
            page.wait_for_load_state("networkidle")

            # Wait a bit for JavaScript to render the form or auto-redirect
            page.wait_for_timeout(1500)

            # Check if we're on an Okta page
            if "okta.com" in page.url:
                print("Detected Okta login page")

                # Check if this is a SAML endpoint (auto-redirect scenario)
                if "/sso/saml" in page.url:
                    print("On SAML endpoint - checking if auto-redirect is happening...")

                    # Wait for either login form or success page (auto-redirect completed)
                    try:
                        # Wait up to 10 seconds for either:
                        # 1. Login form to appear (need to authenticate)
                        # 2. Page to redirect away (already authenticated)
                        page.wait_for_function(
                            """() => {
                                // Check if login form appeared
                                const hasForm = document.querySelector('input[name="username"], input[name="password"], input[type="password"]') !== null;
                                // Check if we redirected away from SAML endpoint
                                const redirected = !window.location.href.includes('/sso/saml');
                                return hasForm || redirected;
                            }""",
                            timeout=10000,
                            polling=200  # Poll every 200ms for faster detection
                        )

                        # Check what happened
                        if "/sso/saml" not in page.url:
                            print("Auto-redirect detected - already authenticated to Okta")
                            print(f"Redirected to: {page.url}")
                            # Continue to check for success
                        else:
                            print("Login form appeared")
                    except PlaywrightTimeout:
                        print("Warning: No form appeared and no redirect after 10 seconds", file=sys.stderr)
                else:
                    # Regular Okta login page
                    print("Waiting for login form...")
                    try:
                        page.wait_for_selector("input[name='username'], input[name='password'], input[type='password']", timeout=8000)
                    except PlaywrightTimeout:
                        print("Warning: Login form did not appear after 8 seconds", file=sys.stderr)

            # Check if we need to authenticate or if we're already past login
            needs_authentication = page.locator("input[type='password']").count() > 0 or \
                                   "okta.com/signin" in page.url.lower() or \
                                   "login" in page.url.lower()

            password_filled = False

            if needs_authentication:
                # Try to detect and fill username field if present
                # Different IdPs have different field selectors
                username_selectors = [
                    "input[name='username']",
                    "input[name='email']",
                    "input[type='email']",
                    "input[id='username']",
                    "input[id='email']",
                ]

                if username:
                    for selector in username_selectors:
                        try:
                            if page.locator(selector).count() > 0:
                                print(f"Filling username: {username}")
                                page.fill(selector, username)
                                break
                        except PlaywrightTimeout:
                            continue

                # Try to detect and fill password field
                password_selectors = [
                    "input[name='password']",
                    "input[type='password']",
                    "input[id='password']",
                    "input[id='passwordInput']",
                    "input[placeholder*='password' i]",
                    "input[placeholder*='Password' i]",
                    "input[aria-label*='password' i]",
                ]

                for selector in password_selectors:
                    try:
                        if page.locator(selector).count() > 0:
                            print(f"Found password field with selector: {selector}")
                            page.fill(selector, sso_password)
                            password_filled = True
                            break
                    except PlaywrightTimeout:
                        continue
            else:
                print("Skipping authentication - appears to be already authenticated")
                password_filled = True  # Skip password validation

            if not password_filled and needs_authentication:
                print("Warning: Could not find password field", file=sys.stderr)
                print("Page title:", page.title(), file=sys.stderr)
                print("Page URL:", page.url, file=sys.stderr)

                # Debug: print all input fields found on the page
                print("\nDebug - Input fields found on page:", file=sys.stderr)
                try:
                    inputs = page.locator("input").all()
                    for i, inp in enumerate(inputs):
                        try:
                            input_type = inp.get_attribute("type") or "text"
                            input_name = inp.get_attribute("name") or "(no name)"
                            input_id = inp.get_attribute("id") or "(no id)"
                            input_placeholder = inp.get_attribute("placeholder") or "(no placeholder)"
                            input_class = inp.get_attribute("class") or "(no class)"
                            is_visible = inp.is_visible()
                            print(f"  [{i}] type={input_type}, name={input_name}, id={input_id}, placeholder={input_placeholder}, class={input_class}, visible={is_visible}", file=sys.stderr)
                        except Exception:
                            pass
                except Exception as e:
                    print(f"Could not enumerate input fields: {e}", file=sys.stderr)

                # Check for iframes
                print("\nDebug - Checking for iframes:", file=sys.stderr)
                try:
                    frames = page.frames
                    print(f"  Found {len(frames)} frame(s)", file=sys.stderr)
                    for idx, frame in enumerate(frames):
                        print(f"  Frame [{idx}]: {frame.url}", file=sys.stderr)
                except Exception as e:
                    print(f"Could not enumerate frames: {e}", file=sys.stderr)

                if not headless:
                    input("Press Enter after manually logging in...")
                    browser.close()
                    return True
                browser.close()
                return False

            # Try to find and click submit button (only if we filled in password)
            if needs_authentication and password_filled:
                submit_selectors = [
                    "button[type='submit']",
                    "input[type='submit']",
                    "button:has-text('Sign in')",
                    "button:has-text('Sign In')",
                    "button:has-text('Login')",
                    "button:has-text('Continue')",
                ]

                submitted = False
                for selector in submit_selectors:
                    try:
                        if page.locator(selector).count() > 0:
                            print("Submitting login form")
                            page.click(selector)
                            submitted = True
                            break
                    except PlaywrightTimeout:
                        continue

                if not submitted:
                    print("Warning: Could not find submit button, trying Enter key")
                    page.keyboard.press("Enter")

            # Wait for either success page or error
            print("Waiting for authentication to complete...")
            try:
                # Common success indicators - check quickly with short timeout
                success_selectors = [
                    "text=success",
                    "text=authenticated",
                    "text=You may now close this window",
                    "text=You may close this browser",
                ]

                for selector in success_selectors:
                    try:
                        page.wait_for_selector(selector, timeout=5000)  # 5 second timeout per selector
                        print("✓ Authentication successful!")
                        browser.close()
                        return True
                    except PlaywrightTimeout:
                        continue

                # If no explicit success message, check for navigation away from login page
                page.wait_for_load_state("networkidle", timeout=5000)  # Reduced to 5 seconds
                current_url = page.url
                print(f"Final URL: {current_url}")

                if "signin" not in current_url.lower() and "login" not in current_url.lower():
                    print("✓ Authentication appears successful (navigated away from login page)")
                    browser.close()
                    return True

                print("✗ Could not confirm authentication success", file=sys.stderr)
                browser.close()
                return False

            except PlaywrightTimeout:
                print("✗ Timeout waiting for authentication confirmation", file=sys.stderr)
                browser.close()
                return False

    except Exception as error:
        print(f"✗ Error during authentication: {error}", file=sys.stderr)
        return False


def main():
    """Main entry point."""
    args = parse_args()

    success = aws_sso_login(
        verification_url=args.verification_url,
        sso_password=args.sso_password,
        username=args.username,
        headless=args.headless,
        timeout=args.timeout
    )

    if success:
        sys.exit(0)
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
