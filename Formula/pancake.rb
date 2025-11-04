class Pancake < Formula
  desc "Collection of useful shell scripts"
  homepage "https://github.com/thiagowfx/pancake"
  url "https://github.com/thiagowfx/pancake/archive/refs/tags/2025.11.04.3.tar.gz"
  sha256 "8e81d998fad77a67d54e257e4ed7547903f7673043519ef0ceb31bcc3e756dd9"
  head "https://github.com/thiagowfx/pancake.git", branch: "master"

  # Script definitions: [directory, script_file, command_name]
  SCRIPTS = [
    # keep-sorted start
    ["aws_china_mfa", "aws_china_mfa.sh", "aws_china_mfa"],
    ["copy", "copy.sh", "copy"],
    ["helm_template_diff", "helm_template_diff.sh", "helm_template_diff"],
    ["img_optimize", "img_optimize.sh", "img_optimize"],
    ["op_login_all", "op_login_all.sh", "op_login_all"],
    ["pritunl_login", "pritunl_login.sh", "pritunl_login"],
    ["sd_world", "sd_world.sh", "sd_world"],
    ["ssh_mux_restart", "ssh_mux_restart.sh", "ssh_mux_restart"],
    # keep-sorted end
  ].freeze

  def install
    SCRIPTS.each do |dir, script, command|
      bin.install "#{dir}/#{script}" => command
    end
  end

  test do
    SCRIPTS.each do |_, _, command|
      assert_path_exists bin/command
      assert_predicate bin/command, :executable?
    end
  end
end
