"""Run with Blender in background mode; imports the extracted KOTOR2 layout."""
import argparse
import json
import sys
from pathlib import Path

import bpy

args = sys.argv[sys.argv.index('--') + 1:]
p = argparse.ArgumentParser()
p.add_argument('--addon', required=True, type=Path)
p.add_argument('--input', required=True, type=Path)
p.add_argument('--output', required=True, type=Path)
a = p.parse_args(args)
sys.path.insert(0, str(a.addon.resolve()))
import io_scene_kotor
from io_scene_kotor.constants import ImportOptions
from io_scene_kotor.io import lyt

io_scene_kotor.register()
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
options = ImportOptions()
options.import_animations = False
options.import_walkmeshes = True
options.texture_search_paths = [str(a.input.resolve())]
options.lightmap_search_paths = [str(a.input.resolve())]
class Reporter:
    def report(self, level, message):
        print(f'{level}: {message}', flush=True)
lyt.load_lyt(Reporter(), str((a.input / '003ebo.lyt').resolve()), options)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
print('Imported mesh count:', len(meshes), flush=True)
if not meshes:
    raise RuntimeError('No ship meshes imported')
a.output.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(a.output.with_name('ebon_hawk.blend').resolve()))
walkmeshes = [o for o in meshes if o.kb.meshtype == 'AABB']
print('Walkmeshes:', len(walkmeshes), flush=True)
if not walkmeshes:
    raise RuntimeError('No walkmeshes imported')
a.output.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='DESELECT')
for obj in walkmeshes:
    obj.select_set(True)
collision = a.output.with_name('collision.glb')
bpy.ops.export_scene.gltf(filepath=str(collision.resolve()), export_format='GLB', use_selection=True)
for obj in walkmeshes:
    bpy.data.objects.remove(obj, do_unlink=True)
materials = {}
exceptions = []
texture_modes = {}
saved_images = set()
texture_dir = a.output.parent / 'lightmaps'
texture_dir.mkdir(exist_ok=True)

def alpha_mode(image, opacity):
    if image.name not in texture_modes:
        # KotOR uses alpha for reflectivity on environment/bump mapped textures.
        if image.kb.additive:
            mode = 'additive'
        elif image.kb.envmap or image.kb.bumpmap:
            mode = 'opaque'
        else:
            alpha = image.pixels[3::4]
            if not alpha or min(alpha) >= 0.999:
                mode = 'opaque'
            elif all(value <= 0.02 or value >= 0.98 for value in alpha):
                mode = 'cutout'
            else:
                mode = 'blend'
        texture_modes[image.name] = mode
    mode = texture_modes[image.name]
    return 'blend' if opacity < 0.999 and mode != 'additive' else mode

def save_texture(image, filename):
    if filename in saved_images:
        return
    # Save once for each source image rather than once per surface.
    image.filepath_raw = str((texture_dir / filename).resolve())
    image.file_format = 'PNG'
    image.save()
    saved_images.add(filename)

for index, obj in enumerate(o for o in meshes if o not in walkmeshes):
    if not obj.kb.lightmapped:
        continue
    source_name = obj.name
    obj.name = f'lightmapped_{index:04d}'
    uv = obj.data.uv_layers.get('UVMap_lm')
    material = obj.active_material
    node = material.node_tree.nodes.get('lightmap_tex') if material and material.use_nodes else None
    image = node.image if node else None
    diffuse_node = material.node_tree.nodes.get('diffuse_tex') if material and material.use_nodes else None
    diffuse = diffuse_node.image if diffuse_node else None
    if uv is None or image is None or diffuse is None or len(obj.data.uv_layers) < 2:
        exceptions.append(f'{source_name} ({obj.name}): missing diffuse, lightmap, or UV coordinates')
        continue
    # glTF exports UV layers in order; the shader reads the second as UV2.
    if obj.data.uv_layers[1] != uv:
        exceptions.append(f'{obj.name}: lightmap UV is not the second UV layer')
        continue
    filename = f'{image.name.split(".")[0].lower()}.png'
    save_texture(image, filename)
    diffuse_filename = f'{diffuse.name.split(".")[0].lower()}.png'
    save_texture(diffuse, diffuse_filename)
    materials[obj.name] = {'lightmap': f'lightmaps/{filename}',
                           'diffuse': f'lightmaps/{diffuse_filename}',
                           'alpha_mode': alpha_mode(diffuse, obj.kb.alpha),
                           'alpha_is_reflectivity': bool(diffuse.kb.envmap or diffuse.kb.bumpmap),
                           'source_name': source_name,
                           'self_illumination': list(obj.kb.selfillumcolor),
                           'alpha': obj.kb.alpha}
(a.output.parent / 'materials.json').write_text(json.dumps({
    'surfaces': materials, 'exceptions': exceptions}, indent=2) + '\n')
print(f'Lightmapped objects: {len(materials)}; exceptions: {len(exceptions)}', flush=True)
bpy.ops.export_scene.gltf(filepath=str(a.output.resolve()), export_format='GLB')
