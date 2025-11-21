class Pancake < Formula
  desc "Collection of useful shell scripts"
  homepage "https://github.com/thiagowfx/pancake"
  url "https://github.com/thiagowfx/pancake/archive/refs/tags/2025.11.21.3.tar.gz"
  sha256 "9d11afa63367989329ad33fd490000a31438eaa269b50d9920a561abec20d7ed"
  head "https://github.com/thiagowfx/pancake.git", branch: "master"

  # Script definitions: [directory, script_file, command_name]
  SCRIPTS = [
    # keep-sorted start
    ["aws_china_mfa", "aws_china_mfa.sh", "aws_china_mfa"],
    ["aws_login_headless", "aws_login_headless.sh", "aws_login_headless"],
    ["cache_prune", "cache_prune.sh", "cache_prune"],
    ["chromium_profile", "chromium_profile.sh", "chromium_profile"],
    ["copy", "copy.sh", "copy"],
    ["helm_template_diff", "helm_template_diff.sh", "helm_template_diff"],
    ["img_optimize", "img_optimize.sh", "img_optimize"],
    ["op_login_all", "op_login_all.sh", "op_login_all"],
    ["pdf_password_remove", "pdf_password_remove.sh", "pdf_password_remove"],
    ["pritunl_login", "pritunl_login.sh", "pritunl_login"],
    ["sd_world", "sd_world.sh", "sd_world"],
    ["ssh_mux_restart", "ssh_mux_restart.sh", "ssh_mux_restart"],
    # keep-sorted end
  ].freeze

  def install
    SCRIPTS.each do |dir, script, command|
      bin.install "#{dir}/#{script}" => command
    end

    # aws_login_headless requires additional Python script
    bin.install "aws_login_headless/aws_login_headless_playwright.py"
  end

  test do
    SCRIPTS.each do |_, _, command|
      assert_path_exists bin/command
      assert_predicate bin/command, :executable?
    end
  end
end
