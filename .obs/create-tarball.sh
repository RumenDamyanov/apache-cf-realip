#!/usr/bin/env bash
# Create source tarballs for OBS/packaging
# Usage: ./create-tarball.sh [version]
set -euo pipefail
export COPYFILE_DISABLE=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

if [ -n "${1:-}" ]; then
    VERSION="$1"
else
    VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "0.1.0")
    VERSION="${VERSION#v}"
fi

PACKAGE_NAME="apache-cf-remoteip"
PKG_DIR="${PACKAGE_NAME}-${VERSION}"
ORIG_TARBALL="${PACKAGE_NAME}_${VERSION}.orig.tar.gz"
DEBIAN_TARBALL="${PACKAGE_NAME}_${VERSION}-1.debian.tar.xz"
FULL_TARBALL="${PACKAGE_NAME}-${VERSION}.tar.gz"
OUTPUT_DIR="$SCRIPT_DIR/$VERSION"

echo "==> Creating tarballs for ${PACKAGE_NAME} version ${VERSION}"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT
WORK_DIR="$TEMP_DIR/$PKG_DIR"
mkdir -p "$WORK_DIR"

echo "==> Exporting source tree..."
git archive --format=tar HEAD | tar -x -C "$WORK_DIR"

# Strip dev-dependencies before vendoring to avoid WASM binding crates
echo "==> Stripping dev-dependencies for clean vendor..."
python3 -c "
import re
with open('$WORK_DIR/Cargo.toml') as f: content = f.read()
content = re.sub(r'\n\[dev-dependencies\].*', '', content, flags=re.DOTALL)
with open('$WORK_DIR/Cargo.toml', 'w') as f: f.write(content)
"
(cd "$WORK_DIR" && cargo generate-lockfile 2>/dev/null || true)

# Downgrade ICU crates for distro Rust compatibility (idna_adapter 1.2.0 -> ICU 1.5.x, MSRV ~1.67)
echo "==> Downgrading ICU crates for distro Rust compatibility..."
(cd "$WORK_DIR" && cargo update idna_adapter --precise 1.2.0 2>/dev/null || true)

# Vendor Rust crate dependencies for offline OBS build
echo "==> Vendoring Rust crate dependencies..."
(cd "$WORK_DIR" && cargo vendor 2>/dev/null || true)
mkdir -p "$WORK_DIR/.cargo"
cat > "$WORK_DIR/.cargo/config.toml" << 'CARGOCONF'
[source.crates-io]
replace-with = "vendored-sources"

[source.vendored-sources]
directory = "vendor"
CARGOCONF

# Remove .orig files from vendor/ and their checksum entries
find "$WORK_DIR/vendor" -name '*.orig' -delete 2>/dev/null || true
find "$WORK_DIR/vendor" -name '.cargo-checksum.json' -exec \
    python3 -c "
import json, sys
for path in sys.argv[1:]:
    with open(path) as f: data = json.load(f)
    files = data.get('files', {})
    data['files'] = {k: v for k, v in files.items() if not k.endswith('.orig')}
    with open(path, 'w') as f: json.dump(data, f, sort_keys=True)
" {} +

# Remove vendored crates not in Cargo.lock (prevents old cargo from parsing incompatible manifests)
echo "==> Pruning excess vendored crates..."
python3 -c "
import os, re
lockfile = os.path.join('$WORK_DIR', 'Cargo.lock')
with open(lockfile) as f: content = f.read()
locked = set()
for m in re.finditer(r'name = \"([^\"]+)\"\nversion = \"([^\"]+)\"', content):
    locked.add(m.group(1))
vendor = os.path.join('$WORK_DIR', 'vendor')
for d in os.listdir(vendor):
    dp = os.path.join(vendor, d)
    if not os.path.isdir(dp): continue
    # Strip version suffix for comparison (e.g. 'foo-1.2.3' -> 'foo')
    name = re.sub(r'-\d+\.\d+\.\d+.*$', '', d)
    if name not in locked:
        import shutil; shutil.rmtree(dp)
        print(f'  removed: {d}')
"

# Convert Cargo.lock from v4 to v3 for compatibility with older distro Rust
sed -i '' 's/^version = 4$/version = 3/' "$WORK_DIR/Cargo.lock" 2>/dev/null || \
    sed -i 's/^version = 4$/version = 3/' "$WORK_DIR/Cargo.lock" 2>/dev/null || true


echo "==> Creating orig tarball: $ORIG_TARBALL"
(cd "$TEMP_DIR" && tar --format=ustar -czf "$OUTPUT_DIR/$ORIG_TARBALL" \
    --exclude="$PKG_DIR/debian" --exclude="$PKG_DIR/.github" \
    --exclude="$PKG_DIR/.obs" --exclude="$PKG_DIR/.ai" \
    --exclude="$PKG_DIR/test" --exclude="$PKG_DIR/docs" \
    --exclude="$PKG_DIR/wiki" --exclude="$PKG_DIR/scripts" \
    --exclude="$PKG_DIR/.git*" --exclude="$PKG_DIR/.editorconfig" \
    --exclude="$PKG_DIR/.DS_Store" --exclude="._*" \
    "$PKG_DIR")

echo "==> Creating full tarball: $FULL_TARBALL"
(cd "$TEMP_DIR" && tar --format=ustar -czf "$OUTPUT_DIR/$FULL_TARBALL" \
    --exclude="$PKG_DIR/.github" --exclude="$PKG_DIR/.obs" \
    --exclude="$PKG_DIR/.ai" --exclude="$PKG_DIR/test" \
    --exclude="$PKG_DIR/docs" --exclude="$PKG_DIR/wiki" \
    --exclude="$PKG_DIR/scripts" --exclude="$PKG_DIR/.git*" \
    --exclude="$PKG_DIR/.editorconfig" --exclude="$PKG_DIR/.DS_Store" \
    --exclude="._*" "$PKG_DIR")

echo "==> Creating debian tarball: $DEBIAN_TARBALL"
DEBIAN_DIR="$TEMP_DIR/debian"
rm -rf "$DEBIAN_DIR"
mkdir -p "$DEBIAN_DIR/source"
cp "$SCRIPT_DIR/debian.changelog" "$DEBIAN_DIR/changelog"
cp "$SCRIPT_DIR/debian.control" "$DEBIAN_DIR/control"
cp "$SCRIPT_DIR/debian.rules" "$DEBIAN_DIR/rules"
chmod +x "$DEBIAN_DIR/rules"
echo "10" > "$DEBIAN_DIR/compat"
echo "3.0 (quilt)" > "$DEBIAN_DIR/source/format"

cat > "$DEBIAN_DIR/copyright" << 'COPYRIGHT_EOF'
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: apache-cf-remoteip
Upstream-Contact: Rumen Damyanov <contact@rumenx.com>
Source: https://github.com/RumenDamyanov/apache-cf-remoteip

Files: *
Copyright: 2026 Rumen Damyanov
License: Apache-2.0

License: Apache-2.0
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 .
     https://www.apache.org/licenses/LICENSE-2.0
 .
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
COPYRIGHT_EOF

tar --format=ustar --exclude='._*' --exclude='.DS_Store' -cJf "$OUTPUT_DIR/$DEBIAN_TARBALL" -C "$TEMP_DIR" debian

echo "==> Generating .dsc file..."
DSC_FILE="$OUTPUT_DIR/${PACKAGE_NAME}_${VERSION}-1.dsc"
ORIG_SIZE=$(stat -f%z "$OUTPUT_DIR/$ORIG_TARBALL" 2>/dev/null || stat -c%s "$OUTPUT_DIR/$ORIG_TARBALL")
ORIG_MD5=$(md5sum "$OUTPUT_DIR/$ORIG_TARBALL" 2>/dev/null | awk '{print $1}' || md5 -q "$OUTPUT_DIR/$ORIG_TARBALL")
ORIG_SHA1=$(shasum -a 1 "$OUTPUT_DIR/$ORIG_TARBALL" | awk '{print $1}')
ORIG_SHA256=$(shasum -a 256 "$OUTPUT_DIR/$ORIG_TARBALL" | awk '{print $1}')
DEB_SIZE=$(stat -f%z "$OUTPUT_DIR/$DEBIAN_TARBALL" 2>/dev/null || stat -c%s "$OUTPUT_DIR/$DEBIAN_TARBALL")
DEB_MD5=$(md5sum "$OUTPUT_DIR/$DEBIAN_TARBALL" 2>/dev/null | awk '{print $1}' || md5 -q "$OUTPUT_DIR/$DEBIAN_TARBALL")
DEB_SHA1=$(shasum -a 1 "$OUTPUT_DIR/$DEBIAN_TARBALL" | awk '{print $1}')
DEB_SHA256=$(shasum -a 256 "$OUTPUT_DIR/$DEBIAN_TARBALL" | awk '{print $1}')

cat > "$DSC_FILE" <<EOF
Format: 3.0 (quilt)
Source: ${PACKAGE_NAME}
Binary: ${PACKAGE_NAME}
Architecture: any
Version: ${VERSION}-1
DEBTRANSFORM-TAR: ${PACKAGE_NAME}_${VERSION}.orig.tar.gz
Maintainer: Rumen Damyanov <contact@rumenx.com>
Homepage: https://github.com/RumenDamyanov/${PACKAGE_NAME}
Standards-Version: 4.6.0
Build-Depends: debhelper-compat (= 13), rustc, cargo, apache2-dev, libldap-dev
Package-List:
 ${PACKAGE_NAME} deb httpd optional arch=any
Checksums-Sha1:
 ${ORIG_SHA1} ${ORIG_SIZE} ${PACKAGE_NAME}_${VERSION}.orig.tar.gz
 ${DEB_SHA1} ${DEB_SIZE} ${PACKAGE_NAME}_${VERSION}-1.debian.tar.xz
Checksums-Sha256:
 ${ORIG_SHA256} ${ORIG_SIZE} ${PACKAGE_NAME}_${VERSION}.orig.tar.gz
 ${DEB_SHA256} ${DEB_SIZE} ${PACKAGE_NAME}_${VERSION}-1.debian.tar.xz
EOF

cp "$SCRIPT_DIR/${PACKAGE_NAME}.spec" "$OUTPUT_DIR/"
cp "$SCRIPT_DIR/debian.changelog" "$OUTPUT_DIR/"
cp "$SCRIPT_DIR/debian.control" "$OUTPUT_DIR/"
cp "$SCRIPT_DIR/debian.rules" "$OUTPUT_DIR/"

echo ""
echo "==> Successfully created in $OUTPUT_DIR/:"
ls -lh "$OUTPUT_DIR/"
echo ""
echo "==> Ready for OBS upload"
