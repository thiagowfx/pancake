class Pancake < Formula
  desc "A collection of useful shell scripts"
  homepage "https://github.com/thiagowfx/pancake"
  head "https://github.com/thiagowfx/pancake.git"

  def install
    # keep-sorted start
    bin.install "aws_china_mfa/aws_china_mfa.sh" => "aws_china_mfa"
    bin.install "img_optimize/img_optimize.sh" => "img_optimize"
    bin.install "op_login_all/op_login_all.sh" => "op_login_all"
    bin.install "pritunl_login/pritunl_login.sh" => "pritunl_login"
    bin.install "sd_world/sd_world.sh" => "sd_world"
    # keep-sorted end
  end

  test do
    # Basic test to ensure the scripts are installed and executable.
    # keep-sorted start
    assert_predicate bin/"aws_china_mfa", :executable?
    assert_predicate bin/"aws_china_mfa", :exist?
    assert_predicate bin/"img_optimize", :executable?
    assert_predicate bin/"img_optimize", :exist?
    assert_predicate bin/"op_login_all", :executable?
    assert_predicate bin/"op_login_all", :exist?
    assert_predicate bin/"pritunl_login", :executable?
    assert_predicate bin/"pritunl_login", :exist?
    assert_predicate bin/"sd_world", :executable?
    assert_predicate bin/"sd_world", :exist?
    # keep-sorted end
  end
end
