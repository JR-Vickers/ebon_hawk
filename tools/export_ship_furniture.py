"""Export curated furniture collision from the retained Blender assembly.

Run Blender in background mode after import_ship_blender.py. These names refer
to original source objects, before the visual export renames lightmapped nodes.
"""
import argparse
import json
import sys
from pathlib import Path

import bpy

args = sys.argv[sys.argv.index('--') + 1:]
parser = argparse.ArgumentParser()
parser.add_argument('--assembly', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
options = parser.parse_args(args)

objects = {
    'central hologame table': ['mroom_holocentre'],
    'central room chairs': ['mroom_Chair24', 'mroom_Chair25', 'mroom_Chair26',
                            'mroom_Chair28', 'mroom_Chair29'],
    'curved panel behind central chairs': ['Object08', 'centrebendchair'],
    'medbay table and bed': ['medbay_table', 'MR_Bed'],
    'crew bunks': ['pcrbed03', 'pcrbed07', 'pcrbed08', 'pcrbed09',
                   'pcrbed10', 'pcrbed11'],
    'navigation chairs': ['cockpit_chair08', 'cockpit_chair09'],
    'cockpit chairs and pilot controls': ['cockpit_chair01', 'ck_panels', 'Object120'],
}

bpy.ops.wm.open_mainfile(filepath=str(options.assembly.resolve()))
bpy.ops.object.select_all(action='DESELECT')
for group, names in objects.items():
    for name in names:
        obj = bpy.data.objects.get(name)
        if obj is None or obj.type != 'MESH':
            raise RuntimeError(f'Missing collision source {name} ({group})')
        obj.select_set(True)
options.output.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(options.output.resolve()), export_format='GLB',
                          use_selection=True)
options.output.with_suffix('.json').write_text(json.dumps(objects, indent=2) + '\n')
print(f'Exported {sum(map(len, objects.values()))} furniture meshes')
