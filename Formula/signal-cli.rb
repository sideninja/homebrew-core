class SignalCli < Formula
  desc "CLI and dbus interface for WhisperSystems/libsignal-service-java"
  homepage "https://github.com/AsamK/signal-cli"
  url "https://github.com/AsamK/signal-cli/releases/download/v0.8.1/signal-cli-0.8.1.tar.gz"
  sha256 "2ead51489d5521ae8c1538936c6a8dcbb22a96227019eb9e826ff5f9146dbbe2"
  license "GPL-3.0-or-later"

  depends_on "gradle" => :build
  depends_on "protobuf" => :build
  # the libsignal-client build targets a specific rustc (nightly-2020-11-09)
  # which doesn't automatically happen if we use brew-installed rust. rustup-init
  # allows us to use a toolchain that lives in HOMEBREW_CACHE
  depends_on "rustup-init" => :build

  depends_on "openjdk"

  resource "libsignal-client" do
    # per https://github.com/AsamK/signal-cli/wiki/Provide-native-lib-for-libsignal#libsignal-client
    # we want the specific libsignal-client version from 'signal-cli-0.8.1/lib/signal-client-XXXX-X.X.X.jar'
    version "java-0.2.3"
    url "https://github.com/signalapp/libsignal-client/archive/refs/tags/#{version}.tar.gz"
    sha256 "730c1dc113da5227920716656d8f888e1af167208e095a8cac3de9c0d83890c4"
  end

  resource "libzkgroup" do
    # per https://github.com/AsamK/signal-cli/wiki/Provide-native-lib-for-libsignal#libzkgroup
    # we want the latest release version
    url "https://github.com/signalapp/zkgroup/archive/refs/tags/v0.7.2.tar.gz"
    sha256 "fdd03bbf584533963d1be40ab238d4e6199b379e8112f6aaf5cd9493b7f1fb47"
  end

  def install
    libexec.install Dir["lib", "bin"]
    (bin/"signal-cli").write_env_script libexec/"bin/signal-cli", JAVA_HOME: Formula["openjdk"].opt_prefix

    # this will install the necessary cargo/rustup toolchain bits in HOMEBREW_CACHE
    system "#{Formula["rustup-init"].bin}/rustup-init", "-qy", "--no-modify-path"
    ENV.prepend_path "PATH", HOMEBREW_CACHE/"cargo_cache/bin"

    resource("libsignal-client").stage do
      # https://github.com/AsamK/signal-cli/wiki/Provide-native-lib-for-libsignal#building-libsignal-client-yourself

      # rm originally-embedded libsignal_jni lib
      system "zip", "-d", "#{libexec}/lib/signal-client-java-0.2.3.jar", "libsignal_jni.so"

      # build & embed library for current platform
      cd "java" do
        inreplace "settings.gradle", ", ':android'", ""
        system "./build_jni.sh", "desktop"
        cd "java/src/main/resources" do
          on_macos do
            system "zip", "-u", "#{libexec}/lib/signal-client-java-0.2.3.jar", "./libsignal_jni.dylib"
          end
          on_linux do
            system "zip", "-u", "#{libexec}/lib/signal-client-java-0.2.3.jar", "./libsignal_jni.so"
          end
        end
      end
    end

    resource("libzkgroup").stage do
      # https://github.com/AsamK/signal-cli/wiki/Provide-native-lib-for-libsignal#libzkgroup

      # rm originally-embedded libzkgroup library
      system "zip", "-d", "#{libexec}/lib/zkgroup-java-0.7.0.jar", "libzkgroup.so"

      # build & embed library for current platform
      on_macos do
        system "make", "mac_dylib"
        # system "make", "libzkgroup" # above is deprecated and will go away in a future version
        cd "ffi/java/src/main/resources" do
          system "zip", "-u", "#{libexec}/lib/zkgroup-java-0.7.0.jar", "./libzkgroup.dylib"
        end
      end
      on_linux do
        system "make", "libzkgroup"
        cd "ffi/java/src/main/resources" do
          system "zip", "-u", "#{libexec}/lib/zkgroup-java-0.7.0.jar", "./libzkgroup.so"
        end
      end
    end
  end

  test do
    # test 1: checks class loading is working and version is correct
    output = shell_output("#{bin}/signal-cli --version")
    assert_match "signal-cli #{version}", output

    # test 2: ensure crypto is working
    begin
      io = IO.popen("#{bin}/signal-cli link", err: [:child, :out])
      sleep 8
    ensure
      Process.kill("SIGINT", io.pid)
      Process.wait(io.pid)
    end
    assert_match "tsdevice:/?uuid=", io.read
  end
end
