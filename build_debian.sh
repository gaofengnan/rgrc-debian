rgrc_VERSION=$1
BUILD_VERSION=$2
ARCH=${3:-amd64}  # Default to amd64 if no architecture specified

if [ -z "$rgrc_VERSION" ] || [ -z "$BUILD_VERSION" ]; then
    echo "Usage: $0 <rgrc_version> <build_version> [architecture]"
    echo "Example: $0 0.6.35 1 arm64"
    echo "Example: $0 0.6.35 1 all    # Build for all architectures"
    echo "Supported architectures: amd64, arm64, armhf, i386, all"
    exit 1
fi

# Function to map Debian architecture to rgrc release name
get_rgrc_release() {
    local arch=$1
    case "$arch" in
        "amd64")
            echo "rgrc-x86_64-unknown-linux-musl"
            ;;
        "arm64")
            echo "rgrc-aarch64-unknown-linux-musl"
            ;;
        "armhf")
            echo "rgrc-arm-unknown-linux-musleabihf"
            ;;
        "i386")
            echo "rgrc-i686-unknown-linux-musl"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Release binaries ship only the rgrc executable. The man page, the main
# rgrc.conf and the per-command conf.* files live in the upstream source tree,
# and completions are printed by the binary itself. Both are architecture
# independent, so they are prepared once into rgrc-extras/.
prepare_extras() {
    local host_release
    local src_dir="rgrc-${rgrc_VERSION}"

    rm -rf rgrc-extras "$src_dir" "rgrc-src.tar.gz" || true

    if ! wget -q "https://github.com/lazywalker/rgrc/archive/refs/tags/v${rgrc_VERSION}.tar.gz" -O rgrc-src.tar.gz; then
        echo "❌ Failed to download rgrc source tarball"
        return 1
    fi
    tar -xf rgrc-src.tar.gz
    rm -f rgrc-src.tar.gz

    if [ ! -f "$src_dir/doc/rgrc.1" ] || [ ! -f "$src_dir/etc/rgrc.conf" ] || [ ! -d "$src_dir/share" ]; then
        echo "❌ Unexpected rgrc source layout (missing doc/rgrc.1, etc/rgrc.conf or share/)"
        return 1
    fi

    mkdir -p rgrc-extras/share rgrc-extras/completions
    cp "$src_dir/doc/rgrc.1" "$src_dir/etc/rgrc.conf" rgrc-extras/
    cp "$src_dir"/share/conf.* rgrc-extras/share/
    rm -rf "$src_dir"

    # Generate completions with a binary that runs on the build host
    case "$(uname -m)" in
        x86_64)  host_release="rgrc-x86_64-unknown-linux-musl" ;;
        aarch64) host_release="rgrc-aarch64-unknown-linux-musl" ;;
        *) echo "❌ Unsupported build host $(uname -m) for completion generation"; return 1 ;;
    esac
    mkdir -p rgrc-host
    if ! wget -q "https://github.com/lazywalker/rgrc/releases/download/v${rgrc_VERSION}/${host_release}.tar.gz" -O rgrc-host.tar.gz; then
        echo "❌ Failed to download host rgrc binary for completions"
        return 1
    fi
    tar -xf rgrc-host.tar.gz -C rgrc-host
    rm -f rgrc-host.tar.gz
    ./rgrc-host/rgrc --completions bash > rgrc-extras/completions/rgrc
    ./rgrc-host/rgrc --completions zsh > rgrc-extras/completions/_rgrc
    ./rgrc-host/rgrc --completions fish > rgrc-extras/completions/rgrc.fish
    rm -rf rgrc-host

    for f in rgrc rgrc.fish _rgrc; do
        if [ ! -s "rgrc-extras/completions/$f" ]; then
            echo "❌ Completion generation produced an empty $f"
            return 1
        fi
    done
}

# Function to build for a specific architecture
build_architecture() {
    local build_arch=$1
    local rgrc_release

    rgrc_release=$(get_rgrc_release "$build_arch")
    if [ -z "$rgrc_release" ]; then
        echo "❌ Unsupported architecture: $build_arch"
        echo "Supported architectures: amd64, arm64, armhf, i386"
        return 1
    fi

    echo "Building for architecture: $build_arch using $rgrc_release"

    # Clean up any previous builds for this architecture
    rm -rf "$rgrc_release" || true
    rm -f "${rgrc_release}.tar.gz" || true

    # Download and extract rgrc binary for this architecture
    if ! wget "https://github.com/lazywalker/rgrc/releases/download/v${rgrc_VERSION}/${rgrc_release}.tar.gz"; then
        echo "❌ Failed to download rgrc binary for $build_arch"
        return 1
    fi

    # rgrc tarballs are flat (just the binary), extract into a per-release directory
    mkdir -p "$rgrc_release"
    if ! tar -xf "${rgrc_release}.tar.gz" -C "$rgrc_release"; then
        echo "❌ Failed to extract rgrc binary for $build_arch"
        return 1
    fi

    rm -f "${rgrc_release}.tar.gz"

    if [ ! -f "$rgrc_release/rgrc" ]; then
        echo "❌ rgrc binary not found in $rgrc_release (tarball layout changed?)"
        return 1
    fi

    # One package for every suite: upstream ships one binary per architecture,
    # so only the old ~<suite> version suffix ever differed. The fixed ~griffo
    # keeps it below the distro's own build of the same version.
    FULL_VERSION="$rgrc_VERSION-${BUILD_VERSION}~griffo_${build_arch}"
    echo "  Building $FULL_VERSION"

    if ! docker build . -t "rgrc-$build_arch" \
        --build-arg rgrc_VERSION="$rgrc_VERSION" \
        --build-arg BUILD_VERSION="$BUILD_VERSION" \
        --build-arg FULL_VERSION="$FULL_VERSION" \
        --build-arg ARCH="$build_arch" \
        --build-arg RGRC_RELEASE="$rgrc_release"; then
        echo "❌ Failed to build Docker image for $build_arch"
        return 1
    fi

    id="$(docker create "rgrc-$build_arch")"
    if ! docker cp "$id:/rgrc_$FULL_VERSION.deb" - > "./rgrc_$FULL_VERSION.deb"; then
        echo "❌ Failed to extract .deb package for $build_arch"
        return 1
    fi

    if ! tar -xf "./rgrc_$FULL_VERSION.deb"; then
        echo "❌ Failed to extract .deb contents for $build_arch"
        return 1
    fi

    # Clean up extracted directory
    rm -rf "$rgrc_release" || true

    echo "✅ Successfully built for $build_arch"
    return 0
}

if ! prepare_extras; then
    exit 1
fi

# Main build logic
if [ "$ARCH" = "all" ]; then
    echo "🚀 Building rgrc $rgrc_VERSION-$BUILD_VERSION for all supported architectures..."
    echo ""

    # All supported architectures
    ARCHITECTURES=("amd64" "arm64" "armhf" "i386")

    for build_arch in "${ARCHITECTURES[@]}"; do
        echo "==========================================="
        echo "Building for architecture: $build_arch"
        echo "==========================================="

        if ! build_architecture "$build_arch"; then
            echo "❌ Failed to build for $build_arch"
            exit 1
        fi

        echo ""
    done

    echo "🎉 All architectures built successfully!"
    echo "Generated packages:"
    ls -la rgrc_*.deb
else
    # Build for single architecture
    if ! build_architecture "$ARCH"; then
        exit 1
    fi
fi

rm -rf rgrc-extras
