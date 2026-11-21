#!/usr/bin/env python3
"""Extract KOTOR II's 003EBO layout and its model and texture dependencies."""
import argparse
import hashlib
import json
import struct
from pathlib import Path

from pykotor.resource.formats.key import read_key
from pykotor.resource.formats.lyt import read_lyt
from pykotor.resource.formats.mdl import read_mdl
from pykotor.resource.formats.tpc import read_tpc, write_tpc
from pykotor.resource.type import ResourceType


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--game', type=Path, required=True, help='KOTOR2 GameData directory')
    parser.add_argument('--output', type=Path, default=Path('assets/extracted/ship'))
    args = parser.parse_args()
    root, out = args.game.expanduser(), args.output
    key = read_key(root / 'chitin.key')
    out.mkdir(parents=True, exist_ok=True)
    (out / '.gdignore').touch()
    tables = {}
    paths = {p.name.lower(): p for p in (root / 'data').iterdir()}
    sources = {}
    missing = []

    def from_key(name, typ):
        entry = key.get_resource(name, typ)
        if entry is None:
            return None
        filename = Path(key.bif_entries[entry.bif_index].filename.replace('\\', '/')).name
        path = paths[filename.lower()]
        if path not in tables:
            with path.open('rb') as f:
                magic, version, count, fixed, offset = struct.unpack('<4s4sIII', f.read(20))
                if magic != b'BIFF' or fixed:
                    raise ValueError(f'Unsupported BIF: {path}')
                f.seek(offset)
                tables[path] = [struct.unpack('<IIII', f.read(16)) for _ in range(count)]
        rid, offset, size, restype = tables[path][entry.res_index]
        if (rid & 0xfffff) != entry.res_index or restype != typ.type_id:
            raise ValueError(f'KEY/BIF mismatch for {name}.{typ.extension}')
        with path.open('rb') as f:
            f.seek(offset)
            data = f.read(size)
        sources[f'{name.lower()}.{typ.extension}'] = str(path.relative_to(root))
        return data

    layout = from_key('003ebo', ResourceType.LYT)
    if not layout:
        raise RuntimeError('003ebo layout missing')
    (out / '003ebo.lyt').write_bytes(layout)
    rooms = list(read_lyt(layout).all_room_models())
    textures = set()
    for name in rooms:
        model = from_key(name, ResourceType.MDL)
        mdx = from_key(name, ResourceType.MDX)
        wok = from_key(name, ResourceType.WOK)
        if not model or not mdx:
            raise RuntimeError(f'Missing model or MDX: {name}')
        for ext, data in [('mdl', model), ('mdx', mdx), ('wok', wok)]:
            if data is not None:
                (out / f'{name}.{ext}').write_bytes(data)
            else:
                missing.append(f'{name}.{ext}')
        parsed = read_mdl(model, source_ext=mdx)
        textures.update(t.lower() for t in parsed.all_textures() | parsed.all_lightmaps())
    def index_pack(path):
        with path.open('rb') as f:
            header = f.read(32)
            magic, version, _, _, count, _, keys, resources = struct.unpack('<4s4sIIIIII', header)
            if magic not in (b'ERF ', b'MOD ') or version != b'V1.0':
                raise ValueError(f'Unsupported texture pack: {path}')
            f.seek(keys)
            entries = [struct.unpack('<16sIHH', f.read(24)) for _ in range(count)]
            f.seek(resources)
            locations = [struct.unpack('<II', f.read(8)) for _ in range(count)]
        return {name.split(b'\0', 1)[0].decode('ascii').lower(): locations[i]
                for i, (name, _, kind, _) in enumerate(entries) if kind == ResourceType.TPC.type_id}

    packs = [root / 'TexturePacks' / f'swpc_tex_tp{x}.erf' for x in 'abc']
    indexes = [index_pack(path) for path in packs]
    overrides = {p.name.lower(): p for p in (root / 'override').iterdir() if p.is_file()}
    for name in sorted(textures):
        data = None
        for extension in ('tga', 'tpc'):
            path = overrides.get(f'{name}.{extension}')
            if path:
                data = path.read_bytes()
                sources[f'{name}.texture'] = str(path.relative_to(root))
                break
        if data is None:
            for pack, index in zip(packs, indexes):
                location = index.get(name)
                if location:
                    with pack.open('rb') as f:
                        f.seek(location[0])
                        data = f.read(location[1])
                    sources[f'{name}.texture'] = str(pack.relative_to(root))
                    break
        if data is None:
            data = from_key(name, ResourceType.TPC)
        if data is None:
            missing.append(f'{name}.texture')
            continue
        try:
            texture = read_tpc(data)
            write_tpc(texture, out / f'{name}.tga', ResourceType.TGA)
            override_txi = overrides.get(f'{name}.txi')
            txi = override_txi.read_text(errors='replace') if override_txi else texture.txi
            txi_path = out / f'{name}.txi'
            if txi.strip():
                txi_path.write_text(txi)
                if override_txi:
                    sources[f'{name}.txi'] = str(override_txi.relative_to(root))
            else:
                txi_path.unlink(missing_ok=True)
        except Exception as e:
            missing.append(f'{name}.texture: {e}')
    manifest = {'module': '003EBO', 'layout': '003ebo.lyt', 'rooms': rooms,
                'sources': sources, 'missing': missing,
                'layout_sha256': hashlib.sha256(layout).hexdigest(), 'pykotor': '2.3.12'}
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Extracted {len(rooms)} rooms and {len(textures)} textures; {len(missing)} missing or failed')
    for item in missing:
        print('MISSING:', item)

if __name__ == '__main__':
    main()
