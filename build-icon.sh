#!/bin/sh
set -eu
cd "$(dirname "$0")"
ICONSET=$(mktemp -d "${TMPDIR:-/tmp}/touchline-icon.XXXXXX")
trap 'rm -rf "$ICONSET"' EXIT
mkdir "$ICONSET/TouchlineLive.iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" assets/TouchlineLive.png --out "$ICONSET/TouchlineLive.iconset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" assets/TouchlineLive.png --out "$ICONSET/TouchlineLive.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
# Package the resized PNG representations in the native ICNS container.
python3 - "$ICONSET/TouchlineLive.iconset" <<'PYICON'
import pathlib, struct, sys
folder = pathlib.Path(sys.argv[1])
representations = [('icp4',16,False),('icp5',32,False),('ic07',128,False),('ic08',256,False),('ic09',512,False),('ic11',16,True),('ic12',32,True),('ic13',128,True),('ic14',256,True),('ic10',512,True)]
chunks = []
def without_private_metadata(png):
    # sips can add EXIF. Keep all visual/color chunks and compressed pixel bytes unchanged.
    output = bytearray(png[:8]); offset = 8
    while offset < len(png):
        size = struct.unpack_from('>I', png, offset)[0]
        kind = png[offset+4:offset+8]
        if kind not in {b'eXIf', b'tEXt', b'zTXt', b'iTXt', b'caBX'}:
            output.extend(png[offset:offset+size+12])
        offset += size+12
    return bytes(output)
for kind, size, retina in representations:
    suffix = '@2x' if retina else ''
    png = without_private_metadata((folder / f'icon_{size}x{size}{suffix}.png').read_bytes())
    chunks.append(kind.encode('ascii') + struct.pack('>I', len(png)+8) + png)
payload = b''.join(chunks)
pathlib.Path('assets/TouchlineLive.icns').write_bytes(b'icns' + struct.pack('>I', len(payload)+8) + payload)
PYICON
