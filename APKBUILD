# Maintainer: Thiago Perrotta <thiago@perrotta.dev>
pkgname=pancake
pkgver=2026.01.27.0
pkgrel=0
pkgdesc="A potpourri of sweet ingredients"
url="https://github.com/thiagowfx/pancake"
arch="noarch"
license="BSD-2-Clause"
depends="bash"
makedepends="help2man"
subpackages="$pkgname-doc"
source="$pkgname-$pkgver.tar.gz::https://github.com/thiagowfx/pancake/archive/refs/tags/$pkgver.tar.gz"
builddir="$srcdir/$pkgname-$pkgver"

scripts_list() {
	cat <<'EOF'
apknew/apknew.sh apknew
aws_china_mfa/aws_china_mfa.sh aws_china_mfa
cache_prune/cache_prune.sh cache_prune
chromium_profile/chromium_profile.sh chromium_profile
copy/copy.sh copy
friendly_ping/friendly_ping.sh friendly_ping
github_ooo/github_ooo.sh github_ooo
helm_template_diff/helm_template_diff.sh helm_template_diff
http_server/http_server.sh http_server
img_optimize/img_optimize.sh img_optimize
is_online/is_online.sh is_online
murder/murder.sh murder
nato/nato.sh nato
notify/notify.sh notify
ocr/ocr.sh ocr
op_login_all/op_login_all.sh op_login_all
pdf_password_remove/pdf_password_remove.sh pdf_password_remove
pritunl_login/pritunl_login.sh pritunl_login
randwords/randwords.sh randwords
radio/radio.sh radio
retry/retry.sh retry
sd_world/sd_world.sh sd_world
spawn/spawn.sh spawn
ssh_mux_restart/ssh_mux_restart.sh ssh_mux_restart
timer/timer.sh timer
try/try.sh try
uwatch/uwatch.sh uwatch
vimtmp/vimtmp.sh vimtmp
wt/wt.sh git-wt
wt/wt.sh wt
EOF
}

build() {
	cd "$builddir"
	mkdir -p man

	scripts_list | while read -r script_path command; do
		chmod +x "$script_path"
		help2man --no-info --no-discard-stderr \
			--version-string="$pkgver" \
			--output "man/${command}.1" \
			--name "$command" \
			"./$script_path"
	done

	find man -type f -name '*.1' -exec gzip -9 {} +
}

check() {
	cd "$builddir"

	scripts_list | while read -r script_path _; do
		case "$script_path" in
			*.sh) bash -n "$script_path" ;;
		esac
	done
}

package() {
	cd "$builddir"

	scripts_list | while read -r script_path command; do
		install -Dm755 "$script_path" "$pkgdir/usr/bin/$command"
	done

	install -Dm644 LICENSE "$pkgdir/usr/share/licenses/$pkgname/LICENSE"
}

doc() {
	cd "$builddir"

	local docdir="$subpkgdir/usr/share/doc/$pkgname"
	local mandir="$subpkgdir/usr/share/man/man1"

	install -Dm644 README.md "$docdir/README.md"

	mkdir -p "$mandir"
	scripts_list | while read -r _ command; do
		install -Dm644 "man/${command}.1.gz" "$mandir/${command}.1.gz"
	done
}
