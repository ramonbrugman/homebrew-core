class Node < Formula
  desc "Platform built on V8 to build network applications"
  homepage "https://nodejs.org/"
  url "https://nodejs.org/dist/v16.7.0/node-v16.7.0.tar.xz"
  sha256 "fa85fdfbd378e587fa04ad9548e7c9f50e690af9575730d3b330cba6fc3f2d37"
  license "MIT"
  head "https://github.com/nodejs/node.git"

  livecheck do
    url "https://nodejs.org/dist/"
    regex(%r{href=["']?v?(\d+(?:\.\d+)+)/?["' >]}i)
  end

  bottle do
    sha256 cellar: :any,                 arm64_big_sur: "e66ba7d690ea50b7155c3a842329735a815daa4f3fcea4c2b87f9bf6d0956c4e"
    sha256 cellar: :any,                 big_sur:       "81e084ec8665c37bdb37939cdbe554502b4d4e849c1e9a4979cddb1754378331"
    sha256 cellar: :any,                 catalina:      "0bd7325e2ad523fe5088bfa7168e482bd85fcfdc017ce86572986584964d8719"
    sha256 cellar: :any,                 mojave:        "9285b5064bccb1a7a1b0174a40a597679a4b3a092057ee58f433320187cd9c26"
    sha256 cellar: :any_skip_relocation, x86_64_linux:  "c503f19cc65fe6a4892fc4db57d1dab01fb1335917ebde7ab75da54a7a2b3c69"
  end

  depends_on "pkg-config" => :build
  depends_on "python@3.9" => :build
  depends_on "brotli"
  depends_on "c-ares"
  depends_on "icu4c"
  depends_on "libuv"
  depends_on "nghttp2"
  depends_on "openssl@1.1"

  uses_from_macos "zlib"

  on_linux do
    depends_on "gcc"
  end

  fails_with :clang do
    build 1099
    cause "Node requires Xcode CLT 11+"
  end

  fails_with gcc: "5"

  # We track major/minor from upstream Node releases.
  # We will accept *important* npm patch releases when necessary.
  resource "npm" do
    url "https://registry.npmjs.org/npm/-/npm-7.20.3.tgz"
    sha256 "bf73538dbcd933e5a9d9575c0c39539aee3e70b32e27837037681662d3bc2c0b"
  end

  # Fix build with brewed c-ares.
  # https://github.com/nodejs/node/pull/39739
  #
  # Remove when the following lands in a *c-ares* release:
  # https://github.com/c-ares/c-ares/commit/7712fcd17847998cf1ee3071284ec50c5b3c1978
  # https://github.com/c-ares/c-ares/pull/417
  patch do
    url "https://github.com/nodejs/node/commit/8699aa501c4d4e1567ebe8901e5ec80cadaa9323.patch?full_index=1"
    sha256 "678643c79258372d5054d3da16bc0c5db17130f151f0e72b6e4f20817987aac9"
  end

  def install
    # make sure subprocesses spawned by make are using our Python 3
    ENV["PYTHON"] = Formula["python@3.9"].opt_bin/"python3"

    # Never install the bundled "npm", always prefer our
    # installation from tarball for better packaging control.
    args = %W[
      --prefix=#{prefix}
      --without-npm
      --with-intl=system-icu
      --shared-libuv
      --shared-nghttp2
      --shared-openssl
      --shared-zlib
      --shared-brotli
      --shared-cares
      --shared-libuv-includes=#{Formula["libuv"].include}
      --shared-libuv-libpath=#{Formula["libuv"].lib}
      --shared-nghttp2-includes=#{Formula["nghttp2"].include}
      --shared-nghttp2-libpath=#{Formula["nghttp2"].lib}
      --shared-openssl-includes=#{Formula["openssl@1.1"].include}
      --shared-openssl-libpath=#{Formula["openssl@1.1"].lib}
      --shared-brotli-includes=#{Formula["brotli"].include}
      --shared-brotli-libpath=#{Formula["brotli"].lib}
      --shared-cares-includes=#{Formula["c-ares"].include}
      --shared-cares-libpath=#{Formula["c-ares"].lib}
    ]
    args << "--tag=head" if build.head?

    system "./configure", *args
    system "make", "install"

    # Allow npm to find Node before installation has completed.
    ENV.prepend_path "PATH", bin

    bootstrap = buildpath/"npm_bootstrap"
    bootstrap.install resource("npm")
    # These dirs must exists before npm install.
    mkdir_p libexec/"lib"
    system "node", bootstrap/"bin/npm-cli.js", "install", "-ddd", "--global",
            "--prefix=#{libexec}", resource("npm").cached_download

    # The `package.json` stores integrity information about the above passed
    # in `cached_download` npm resource, which breaks `npm -g outdated npm`.
    # This copies back over the vanilla `package.json` to fix this issue.
    cp bootstrap/"package.json", libexec/"lib/node_modules/npm"
    # These symlinks are never used & they've caused issues in the past.
    rm_rf libexec/"share"

    bash_completion.install bootstrap/"lib/utils/completion.sh" => "npm"
  end

  def post_install
    node_modules = HOMEBREW_PREFIX/"lib/node_modules"
    node_modules.mkpath
    # Kill npm but preserve all other modules across node updates/upgrades.
    rm_rf node_modules/"npm"

    cp_r libexec/"lib/node_modules/npm", node_modules
    # This symlink doesn't hop into homebrew_prefix/bin automatically so
    # we make our own. This is a small consequence of our
    # bottle-npm-and-retain-a-private-copy-in-libexec setup
    # All other installs **do** symlink to homebrew_prefix/bin correctly.
    # We ln rather than cp this because doing so mimics npm's normal install.
    ln_sf node_modules/"npm/bin/npm-cli.js", HOMEBREW_PREFIX/"bin/npm"
    ln_sf node_modules/"npm/bin/npx-cli.js", HOMEBREW_PREFIX/"bin/npx"

    # Create manpage symlinks (or overwrite the old ones)
    %w[man1 man5 man7].each do |man|
      # Dirs must exist first: https://github.com/Homebrew/legacy-homebrew/issues/35969
      mkdir_p HOMEBREW_PREFIX/"share/man/#{man}"
      # still needed to migrate from copied file manpages to symlink manpages
      rm_f Dir[HOMEBREW_PREFIX/"share/man/#{man}/{npm.,npm-,npmrc.,package.json.,npx.}*"]
      ln_sf Dir[node_modules/"npm/man/#{man}/{npm,package-,shrinkwrap-,npx}*"], HOMEBREW_PREFIX/"share/man/#{man}"
    end

    (node_modules/"npm/npmrc").atomic_write("prefix = #{HOMEBREW_PREFIX}\n")
  end

  test do
    path = testpath/"test.js"
    path.write "console.log('hello');"

    output = shell_output("#{bin}/node #{path}").strip
    assert_equal "hello", output
    output = shell_output("#{bin}/node -e 'console.log(new Intl.NumberFormat(\"en-EN\").format(1234.56))'").strip
    assert_equal "1,234.56", output

    output = shell_output("#{bin}/node -e 'console.log(new Intl.NumberFormat(\"de-DE\").format(1234.56))'").strip
    assert_equal "1.234,56", output

    # make sure npm can find node
    ENV.prepend_path "PATH", opt_bin
    ENV.delete "NVM_NODEJS_ORG_MIRROR"
    assert_equal which("node"), opt_bin/"node"
    assert_predicate HOMEBREW_PREFIX/"bin/npm", :exist?, "npm must exist"
    assert_predicate HOMEBREW_PREFIX/"bin/npm", :executable?, "npm must be executable"
    npm_args = ["-ddd", "--cache=#{HOMEBREW_CACHE}/npm_cache", "--build-from-source"]
    system "#{HOMEBREW_PREFIX}/bin/npm", *npm_args, "install", "npm@latest"
    system "#{HOMEBREW_PREFIX}/bin/npm", *npm_args, "install", "bufferutil" unless head?
    assert_predicate HOMEBREW_PREFIX/"bin/npx", :exist?, "npx must exist"
    assert_predicate HOMEBREW_PREFIX/"bin/npx", :executable?, "npx must be executable"
    assert_match "< hello >", shell_output("#{HOMEBREW_PREFIX}/bin/npx --yes cowsay hello")
  end
end
