class Pancake < Formula
  desc "Collection of useful shell scripts"
  homepage "https://github.com/thiagowfx/pancake"
  url "https://github.com/thiagowfx/pancake/archive/refs/tags/2025.11.27.11.tar.gz"
  sha256 "33ea012b637e9723ad839441aeeb195f970e2d15031e0a024b29675a0cbda28a"
  head "https://github.com/thiagowfx/pancake.git", branch: "master"

  depends_on "help2man" => :build

  # Script definitions: [directory, script_file, command_name]
  SCRIPTS = [
    # keep-sorted start
    ["aws_china_mfa", "aws_china_mfa.sh", "aws_china_mfa"],
    ["aws_login_headless", "aws_login_headless.sh", "aws_login_headless"],
    ["cache_prune", "cache_prune.sh", "cache_prune"],
    ["chromium_profile", "chromium_profile.sh", "chromium_profile"],
    ["copy", "copy.sh", "copy"],
    ["helm_template_diff", "helm_template_diff.sh", "helm_template_diff"],
    ["httpserver", "httpserver.sh", "httpserver"],
    ["img_optimize", "img_optimize.sh", "img_optimize"],
    ["is_online", "is_online.sh", "is_online"],
    ["murder", "murder.sh", "murder"],
    ["nato", "nato.sh", "nato"],
    ["notify", "notify.sh", "notify"],
    ["ocr", "ocr.sh", "ocr"],
    ["op_login_all", "op_login_all.sh", "op_login_all"],
    ["pdf_password_remove", "pdf_password_remove.sh", "pdf_password_remove"],
    ["pritunl_login", "pritunl_login.sh", "pritunl_login"],
    ["radio", "radio.sh", "radio"],
    ["retry", "retry.sh", "retry"],
    ["sd_world", "sd_world.sh", "sd_world"],
    ["ssh_mux_restart", "ssh_mux_restart.sh", "ssh_mux_restart"],
    ["timer", "timer.sh", "timer"],
    ["vimtmp", "vimtmp.sh", "vimtmp"],
    ["wt", "wt.sh", "wt"],
    # keep-sorted end
  ].freeze

  def install
    SCRIPTS.each do |dir, script, command|
      bin.install "#{dir}/#{script}" => command
    end

    # aws_login_headless requires additional Python script
    bin.install "aws_login_headless/aws_login_headless_playwright.py"

    # Generate and install man pages
    SCRIPTS.each do |_, _, command|
      system "help2man", "--no-info", "--no-discard-stderr",
             "--version-string=#{version}", "--output=#{command}.1",
             "--name=#{command}", bin/command
      man1.install "#{command}.1"
    end
  end

  test do
    SCRIPTS.each do |_, _, command|
      assert_path_exists bin/command
      assert_predicate bin/command, :executable?
    end
  end
end
