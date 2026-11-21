#!/usr/bin/env python3
"""Extract the local 003EBO soundscape and its original placement metadata."""
import argparse
import json
import struct
from pathlib import Path

from pykotor.resource.formats.key import read_key
from pykotor.resource.formats.rim import read_rim
from pykotor.resource.formats.twoda import read_2da
from pykotor.resource.formats.wav import get_playable_bytes, read_wav
from pykotor.resource.generics.git import read_git
from pykotor.resource.generics.uts import read_uts
from pykotor.resource.type import ResourceType


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game', required=True, type=Path)
    parser.add_argument('--output', type=Path, default=Path('assets/generated/ship_audio'))
    args = parser.parse_args()
    root, out = args.game.expanduser(), args.output
    key = read_key(root / 'chitin.key')
    data_paths = {p.name.lower(): p for p in (root / 'data').iterdir()}
    overrides = {p.name.lower(): p for p in (root / 'override').iterdir() if p.is_file()}
    streams = {p.stem.lower(): p for folder in ('StreamSounds', 'StreamMusic')
               for p in (root / folder).iterdir() if p.is_file() and p.suffix.lower() == '.wav'}
    module = read_rim(root / 'Modules/003EBO.rim')
    templates = read_rim(root / 'Modules/003EBO_s.rim')

    def from_key(name, kind):
        entry = key.get_resource(name, kind)
        if entry is None:
            return None
        path = data_paths[Path(key.bif_entries[entry.bif_index].filename.replace('\\', '/')).name.lower()]
        with path.open('rb') as f:
            magic, version, count, fixed, offset = struct.unpack('<4s4sIII', f.read(20))
            if magic != b'BIFF' or fixed or entry.res_index >= count:
                raise ValueError(f'Unsupported BIF: {path}')
            f.seek(offset + entry.res_index * 16)
            rid, position, size, restype = struct.unpack('<IIII', f.read(16))
            if (rid & 0xfffff) != entry.res_index or restype != kind.type_id:
                raise ValueError(f'KEY/BIF mismatch: {name}')
            f.seek(position)
            return f.read(size)

    def resource(name, kind, archive=None):
        override = overrides.get(f'{name.lower()}.{kind.extension}')
        return override.read_bytes() if override else (archive.get(name, kind) if archive else None) or from_key(name, kind)

    git = read_git(resource('003ebo', ResourceType.GIT, module))
    def table_sound(table, row):
        data = resource(table, ResourceType.TwoDA)
        if data is None:
            raise ValueError(f'Missing {table}.2da')
        return read_2da(data).get_cell(row, 'resource').lower()

    music = table_sound('ambientmusic', git.music_standard_id)
    ambient = table_sound('ambientsound', git.ambient_sound_id)
    sound_names = {music, ambient}
    emitters = []
    for instance in git.sounds:
        template = str(instance.resref).lower()
        raw = resource(template, ResourceType.UTS, templates)
        if raw is None:
            raise ValueError(f'Missing sound template {template}')
        sound = read_uts(raw)
        if not sound.active:
            continue
        names = [str(name).lower() for name in sound.sounds]
        sound_names.update(names)
        pos = instance.position
        emitters.append({'template': template, 'position': [pos.x, pos.z, -pos.y],
                         'sounds': names, 'loop': sound.looping, 'continuous': sound.continuous,
                         'random_pick': sound.random_pick, 'interval_ms': sound.interval,
                         'interval_variation_ms': sound.interval_variation,
                         'volume': sound.volume, 'volume_variation': sound.volume_variation,
                         'min_distance': sound.min_distance, 'max_distance': sound.max_distance})
    out.mkdir(parents=True, exist_ok=True)
    missing = []
    for name in sorted(sound_names):
        override = overrides.get(name + '.wav')
        source = override.read_bytes() if override else (streams[name].read_bytes() if name in streams else from_key(name, ResourceType.WAV))
        if source is None:
            missing.append(name)
            continue
        try:
            (out / (name + '.wav')).write_bytes(get_playable_bytes(read_wav(source)))
        except Exception as error:
            missing.append(f'{name}: {error}')
    if missing:
        raise ValueError('Missing or unreadable audio: ' + ', '.join(missing))
    manifest = {'version': 1, 'music': music, 'ambient': ambient,
                'ambient_volume': git.ambient_volume, 'music_delay_ms': git.music_delay,
                'emitters': emitters}
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'Extracted {len(sound_names)} clips and {len(emitters)} active emitters to {out}')

if __name__ == '__main__':
    main()
