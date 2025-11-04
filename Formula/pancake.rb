class Pancake < Formula
  desc "Collection of useful shell scripts"
  homepage "https://github.com/thiagowfx/pancake"
  url "https://github.com/thiagowfx/pancake/archive/refs/tags/2025.11.04.tar.gz"
  sha256 "15134e14ee8a96045755d6a41e5cbcee4c3beca139449707bcc50f1081627d75"
  head "https://github.com/thiagowfx/pancake.git", branch: "master"

  # Script definitions: [directory, script_file, command_name]
  SCRIPTS = [
    # keep-sorted start
    ["aws_china_mfa", "aws_china_mfa.sh", "aws_china_mfa"],
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
