"""
Generates the greybox prop scenes and the Siddhashrama level scene.

    python tools/build_level.py

Writes:
    scenes/props/*.tscn
    scenes/levels/siddhashrama.tscn
    scenes/levels/siddhashrama_navmesh.tres   (parameters only; bake with
                                               tools/bake_navmesh.tscn)

Re-running overwrites those files, so once you start hand-editing the level in
Godot, edit it there instead of here.

Layout (Rama walks toward -Z):
    S0  Forest path         z    0 .. -36   intro captions
    S1  Sentries            z  -36 .. -76   stealth: 3 unaware sentries
    S2  Rakshasa camp       z  -84 .. -124  2 waves of grunts
    S3  Ravine              z -132 .. -182  archers on ledges, fire arrows, pots
    S4  Ruined shrine       z -190 .. -230  chakra, brute ambush, bell puzzle
    S5  Yagna               z -238 .. -292  defend the fire (3 waves) -> Tataka
"""

import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


# --- tiny .tscn writer --------------------------------------------------------

def fmt(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(round(float(v), 4)) if isinstance(v, float) else str(v)
    return v  # already formatted


def v3(x, y, z):
    return f"Vector3({fmt(float(x))}, {fmt(float(y))}, {fmt(float(z))})"


def col(r, g, b, a=1.0):
    return f"Color({r}, {g}, {b}, {a})"


def q(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def strings(lines):
    return "PackedStringArray(" + ", ".join(q(l) for l in lines) + ")"


class Scene:
    def __init__(self):
        self.ext = []      # (type, path, id)
        self.sub = []      # (type, id, props)
        self.nodes = []    # text blocks
        self._ext_ids = {}
        self._n = 0

    def ext_res(self, type_, path):
        if path not in self._ext_ids:
            rid = f"{len(self.ext) + 1}_{Path(path).stem}"
            self._ext_ids[path] = rid
            self.ext.append((type_, path, rid))
        return f'ExtResource("{self._ext_ids[path]}")'

    def sub_res(self, type_, **props):
        self._n += 1
        rid = f"{type_}_{self._n}"
        self.sub.append((type_, rid, props))
        return f'SubResource("{rid}")'

    def node(self, name, type_=None, parent=None, instance=None, groups=None, **props):
        head = f'[node name="{name}"'
        if type_:
            head += f' type="{type_}"'
        if parent is not None:
            head += f' parent="{parent}"'
        if instance:
            head += f" instance={instance}"
        if groups:
            head += " groups=[" + ", ".join(q(g) for g in groups) + "]"
        head += "]"
        body = "".join(f"{k} = {fmt(v)}\n" for k, v in props.items())
        self.nodes.append(head + "\n" + body)
        return name if parent is None else (name if parent == "." else f"{parent}/{name}")

    def write(self, path):
        out = ["[gd_scene format=3]\n"]
        for type_, p, rid in self.ext:
            out.append(f'[ext_resource type="{type_}" path="{p}" id="{rid}"]')
        out.append("")
        for type_, rid, props in self.sub:
            out.append(f'[sub_resource type="{type_}" id="{rid}"]')
            out.extend(f"{k} = {fmt(v)}" for k, v in props.items())
            out.append("")
        out.extend(self.nodes)
        full = ROOT / path
        full.parent.mkdir(parents=True, exist_ok=True)
        full.write_text("\n".join(out), encoding="utf-8")
        print("wrote", path)


def mat(scene, color, rough=0.9, metal=0.0, emission=None, energy=1.0, unshaded=False):
    props = {"albedo_color": color, "roughness": rough}
    if metal:
        props["metallic"] = metal
    if emission:
        props.update(emission_enabled=True, emission=emission, emission_energy_multiplier=energy)
    if unshaded:
        props = {"shading_mode": 0, "albedo_color": color}
    return scene.sub_res("StandardMaterial3D", **props)


def mesh_node(scene, name, parent, mesh, pos=(0, 0, 0), rot=None, shadow=True):
    props = {"position": v3(*pos), "mesh": mesh}
    if rot:
        props["rotation_degrees"] = v3(*rot)
    if not shadow:
        props["cast_shadow"] = 0
    return scene.node(name, "MeshInstance3D", parent, **props)


# --- prop scenes --------------------------------------------------------------

def build_torch():
    s = Scene()
    script = s.ext_res("Script", "res://scripts/props/torch.gd")
    wood = mat(s, col(0.22, 0.14, 0.08))
    iron = mat(s, col(0.2, 0.2, 0.22), 0.5, 0.7)
    flame = mat(s, col(1, 0.55, 0.15), unshaded=True)
    ember_mat = s.sub_res("StandardMaterial3D", shading_mode=0, transparency=1, blend_mode=1,
                          billboard_mode=3, vertex_color_use_as_albedo=True, albedo_color=col(1.6, 1.6, 1.6))
    s.node("Torch", "Node3D", script=script)
    mesh_node(s, "Pole", ".", s.sub_res("CylinderMesh", material=wood, top_radius=0.06, bottom_radius=0.09, height=2.3), (0, 1.15, 0))
    mesh_node(s, "Bowl", ".", s.sub_res("CylinderMesh", material=iron, top_radius=0.22, bottom_radius=0.1, height=0.2), (0, 2.3, 0))
    mesh_node(s, "Flame", ".", s.sub_res("SphereMesh", material=flame, radius=0.16, height=0.42), (0, 2.5, 0), shadow=False)
    s.node("Light", "OmniLight3D", ".", position=v3(0, 2.7, 0), light_color=col(1, 0.55, 0.22),
           light_energy=2.2, omni_range=9.0)
    ramp = s.sub_res("Gradient", offsets="PackedFloat32Array(0, 0.3, 1)",
                     colors="PackedColorArray(1, 0.8, 0.4, 1, 1, 0.4, 0.1, 0.9, 0.4, 0.05, 0, 0)")
    s.node("Embers", "CPUParticles3D", ".", position=v3(0, 2.6, 0),
           mesh=s.sub_res("QuadMesh", material=ember_mat, size="Vector2(0.06, 0.06)"),
           amount=10, lifetime=1.4, direction=v3(0, 1, 0), spread=25.0, gravity=v3(0.2, 1.2, 0),
           initial_velocity_min=0.3, initial_velocity_max=0.9, color_ramp=ramp)
    s.write("scenes/props/torch.tscn")


def build_pot():
    s = Scene()
    script = s.ext_res("Script", "res://scripts/props/explosive_pot.gd")
    clay = mat(s, col(0.55, 0.22, 0.12))
    band = mat(s, col(1, 0.5, 0.1), emission=col(1, 0.45, 0.05), energy=2.0)
    s.node("ExplosivePot", "StaticBody3D", script=script)
    s.node("CollisionShape3D", "CollisionShape3D", ".", position=v3(0, 0.45, 0),
           shape=s.sub_res("SphereShape3D", radius=0.45))
    mesh_node(s, "Pot", ".", s.sub_res("SphereMesh", material=clay, radius=0.45, height=0.85), (0, 0.45, 0))
    mesh_node(s, "Band", ".", s.sub_res("TorusMesh", material=band, inner_radius=0.4, outer_radius=0.47), (0, 0.55, 0))
    mesh_node(s, "Neck", ".", s.sub_res("CylinderMesh", material=clay, top_radius=0.16, bottom_radius=0.22, height=0.25), (0, 0.95, 0))
    s.write("scenes/props/explosive_pot.tscn")


def build_bell():
    s = Scene()
    script = s.ext_res("Script", "res://scripts/props/bell.gd")
    bronze = mat(s, col(0.65, 0.45, 0.2), 0.35, 0.85)
    wood = mat(s, col(0.25, 0.16, 0.09))
    s.node("Bell", "StaticBody3D", script=script)
    s.node("CollisionShape3D", "CollisionShape3D", ".", position=v3(0, -0.2, 0),
           shape=s.sub_res("SphereShape3D", radius=0.7))
    mesh_node(s, "Beam", ".", s.sub_res("BoxMesh", material=wood, size=v3(1.4, 0.15, 0.2)), (0, 0.45, 0))
    s.node("Bell", "Node3D", ".")
    mesh_node(s, "Body", "Bell", s.sub_res("CylinderMesh", material=bronze, top_radius=0.22, bottom_radius=0.5, height=0.75), (0, -0.05, 0))
    mesh_node(s, "Clapper", "Bell", s.sub_res("SphereMesh", material=bronze, radius=0.1, height=0.2), (0, -0.45, 0))
    s.node("Glow", "OmniLight3D", ".", position=v3(0, -0.3, 0), light_color=col(1, 0.8, 0.35),
           light_energy=2.5, omni_range=5.0)
    s.write("scenes/props/bell.tscn")


def build_gate():
    s = Scene()
    script = s.ext_res("Script", "res://scripts/props/gate.gd")
    wood = mat(s, col(0.2, 0.12, 0.07))
    glyph = mat(s, col(1, 0.55, 0.15), emission=col(1, 0.45, 0.1), energy=1.5)
    s.node("Gate", "StaticBody3D", script=script)
    s.node("CollisionShape3D", "CollisionShape3D", ".", position=v3(0, 2.5, 0),
           shape=s.sub_res("BoxShape3D", size=v3(6.4, 5, 0.6)))
    mesh_node(s, "Doors", ".", s.sub_res("BoxMesh", material=wood, size=v3(6.4, 5, 0.5)), (0, 2.5, 0))
    for i, x in enumerate((-2.2, 0.0, 2.2)):
        mesh_node(s, f"Glyph{i}", ".", s.sub_res("BoxMesh", material=glyph, size=v3(0.18, 3.6, 0.55)), (x, 2.5, 0))
    s.write("scenes/props/gate.tscn")


def build_herb():
    s = Scene()
    script = s.ext_res("Script", "res://scripts/props/healing_herb.gd")
    leaf = mat(s, col(0.3, 1, 0.55), emission=col(0.2, 1, 0.45), energy=1.5)
    s.node("HealingHerb", "Area3D", script=script)
    s.node("CollisionShape3D", "CollisionShape3D", ".", position=v3(0, 0.5, 0),
           shape=s.sub_res("SphereShape3D", radius=0.9))
    s.node("Plant", "Node3D", ".", position=v3(0, 0.3, 0))
    leaf_mesh = s.sub_res("CylinderMesh", material=leaf, top_radius=0.0, bottom_radius=0.12, height=0.6)
    for i, (x, z, r) in enumerate(((0, 0, 0), (0.15, 0.05, 25), (-0.12, 0.1, -25), (0.02, -0.15, 20))):
        mesh_node(s, f"Leaf{i}", "Plant", leaf_mesh, (x, 0.3, z), (r, 0, r), shadow=False)
    s.node("Light", "OmniLight3D", ".", position=v3(0, 0.8, 0), light_color=col(0.4, 1, 0.6),
           light_energy=1.0, omni_range=3.0)
    s.write("scenes/props/healing_herb.tscn")


def build_chakra_pickup():
    s = Scene()
    script = s.ext_res("Script", "res://scripts/props/chakra_pickup.gd")
    gold = mat(s, col(1, 0.8, 0.3), 0.25, 0.9, emission=col(1, 0.7, 0.2), energy=2.5)
    s.node("ChakraPickup", "Area3D", script=script)
    s.node("CollisionShape3D", "CollisionShape3D", ".", position=v3(0, 1, 0),
           shape=s.sub_res("SphereShape3D", radius=2.4))
    s.node("Chakra", "Node3D", ".", position=v3(0, 1.6, 0))
    mesh_node(s, "Ring", "Chakra", s.sub_res("CylinderMesh", material=gold, top_radius=0.4, bottom_radius=0.4, height=0.06), shadow=False)
    spike = s.sub_res("BoxMesh", material=gold, size=v3(1.1, 0.05, 0.1))
    for i, r in enumerate((0, 60, 120)):
        mesh_node(s, f"Spike{i}", "Chakra", spike, rot=(0, r, 0), shadow=False)
    s.node("Light", "OmniLight3D", ".", position=v3(0, 2, 0), light_color=col(1, 0.8, 0.4),
           light_energy=3.0, omni_range=8.0)
    s.write("scenes/props/chakra_pickup.tscn")


def build_altar():
    s = Scene()
    script = s.ext_res("Script", "res://scripts/props/yagna_altar.gd")
    stone = mat(s, col(0.5, 0.42, 0.36))
    brick = mat(s, col(0.55, 0.28, 0.18))
    flame = mat(s, col(1, 0.6, 0.2), unshaded=True)
    ember_mat = s.sub_res("StandardMaterial3D", shading_mode=0, transparency=1, blend_mode=1,
                          billboard_mode=3, vertex_color_use_as_albedo=True, albedo_color=col(1.8, 1.8, 1.8))
    s.node("YagnaAltar", "StaticBody3D", script=script)
    s.node("CollisionShape3D", "CollisionShape3D", ".", position=v3(0, 0.5, 0),
           shape=s.sub_res("BoxShape3D", size=v3(3.2, 1, 3.2)))
    mesh_node(s, "Base", ".", s.sub_res("BoxMesh", material=stone, size=v3(3.2, 0.4, 3.2)), (0, 0.2, 0))
    mesh_node(s, "Kund", ".", s.sub_res("BoxMesh", material=brick, size=v3(2.2, 0.6, 2.2)), (0, 0.7, 0))
    s.node("Flame", "Node3D", ".", position=v3(0, 1.0, 0))
    mesh_node(s, "Core", "Flame", s.sub_res("SphereMesh", material=flame, radius=0.6, height=1.6), (0, 0.6, 0), shadow=False)
    ramp = s.sub_res("Gradient", offsets="PackedFloat32Array(0, 0.35, 1)",
                     colors="PackedColorArray(1, 0.85, 0.4, 1, 1, 0.4, 0.08, 0.9, 0.3, 0.05, 0, 0)")
    s.node("Fire", "CPUParticles3D", "Flame", position=v3(0, 0.3, 0),
           mesh=s.sub_res("QuadMesh", material=ember_mat, size="Vector2(0.5, 0.5)"),
           amount=40, lifetime=0.9, emission_shape=1, emission_sphere_radius=0.6, direction=v3(0, 1, 0),
           spread=12.0, gravity=v3(0, 3, 0), initial_velocity_min=0.5, initial_velocity_max=1.5, color_ramp=ramp)
    s.node("Light", "OmniLight3D", ".", position=v3(0, 2.2, 0), light_color=col(1, 0.5, 0.18),
           light_energy=5.0, omni_range=16.0)
    s.write("scenes/props/yagna_altar.tscn")


def build_vishwamitra():
    s = Scene()
    saffron = mat(s, col(0.95, 0.5, 0.12))
    skin = mat(s, col(0.62, 0.45, 0.32))
    white = mat(s, col(0.92, 0.92, 0.9))
    beads = mat(s, col(0.35, 0.15, 0.08))
    s.node("Vishwamitra", "StaticBody3D")
    s.node("CollisionShape3D", "CollisionShape3D", ".", position=v3(0, 0.6, 0),
           shape=s.sub_res("CylinderShape3D", radius=0.7, height=1.2))
    mesh_node(s, "Lap", ".", s.sub_res("CylinderMesh", material=saffron, top_radius=0.5, bottom_radius=0.75, height=0.45), (0, 0.22, 0))
    mesh_node(s, "Torso", ".", s.sub_res("CapsuleMesh", material=saffron, radius=0.3, height=0.9), (0, 0.8, 0))
    mesh_node(s, "Head", ".", s.sub_res("SphereMesh", material=skin, radius=0.19, height=0.38), (0, 1.4, 0))
    mesh_node(s, "Beard", ".", s.sub_res("SphereMesh", material=white, radius=0.16, height=0.42), (0, 1.25, -0.1))
    mesh_node(s, "Bun", ".", s.sub_res("SphereMesh", material=white, radius=0.11, height=0.22), (0, 1.62, 0.04))
    mesh_node(s, "Beads", ".", s.sub_res("TorusMesh", material=beads, inner_radius=0.2, outer_radius=0.25), (0, 1.05, -0.05), (70, 0, 0))
    s.write("scenes/props/vishwamitra.tscn")


# --- the level ----------------------------------------------------------------

class Level:
    def __init__(self):
        self.s = Scene()
        s = self.s
        self.res = {
            "torch": s.ext_res("PackedScene", "res://scenes/props/torch.tscn"),
            "pot": s.ext_res("PackedScene", "res://scenes/props/explosive_pot.tscn"),
            "bell": s.ext_res("PackedScene", "res://scenes/props/bell.tscn"),
            "gate": s.ext_res("PackedScene", "res://scenes/props/gate.tscn"),
            "herb": s.ext_res("PackedScene", "res://scenes/props/healing_herb.tscn"),
            "chakra": s.ext_res("PackedScene", "res://scenes/props/chakra_pickup.tscn"),
            "altar": s.ext_res("PackedScene", "res://scenes/props/yagna_altar.tscn"),
            "sage": s.ext_res("PackedScene", "res://scenes/props/vishwamitra.tscn"),
            "grunt": s.ext_res("PackedScene", "res://scenes/enemies/grunt.tscn"),
            "archer": s.ext_res("PackedScene", "res://scenes/enemies/archer.tscn"),
            "brute": s.ext_res("PackedScene", "res://scenes/enemies/brute.tscn"),
            "tataka": s.ext_res("PackedScene", "res://scenes/enemies/tataka.tscn"),
            "player": s.ext_res("PackedScene", "res://scenes/player/player.tscn"),
            "level_gd": s.ext_res("Script", "res://scripts/levels/level.gd"),
            "section_gd": s.ext_res("Script", "res://scripts/levels/section.gd"),
            "encounter_gd": s.ext_res("Script", "res://scripts/levels/encounter.gd"),
            "spawn_gd": s.ext_res("Script", "res://scripts/levels/spawn_point.gd"),
            "caption_gd": s.ext_res("Script", "res://scripts/levels/caption_trigger.gd"),
            "puzzle_gd": s.ext_res("Script", "res://scripts/props/bell_puzzle.gd"),
            "boss_gd": s.ext_res("Script", "res://scripts/levels/boss_encounter.gd"),
            "rig_gd": s.ext_res("Script", "res://scripts/camera/camera_rig.gd"),
            "hud_gd": s.ext_res("Script", "res://scripts/ui/hud.gd"),
            "navmesh": s.ext_res("NavigationMesh", "res://scenes/levels/siddhashrama_navmesh.tres"),
            "terrain_gd": s.ext_res("Script", "res://scripts/world/terrain_patch.gd"),
            "scatter_gd": s.ext_res("Script", "res://scripts/world/forest_scatter.gd"),
            "battlement_gd": s.ext_res("Script", "res://scripts/world/battlement.gd"),
            "rock_gd": s.ext_res("Script", "res://scripts/world/rock.gd"),
            "stone_shader": s.ext_res("Shader", "res://shaders/stone_blocks.gdshader"),
            "rock_shader": s.ext_res("Shader", "res://shaders/rock.gdshader"),
            "bark_shader": s.ext_res("Shader", "res://shaders/bark.gdshader"),
        }
        grad = s.sub_res("Gradient", colors="PackedColorArray(0.55, 0.55, 0.55, 1, 1, 1, 1, 1)")
        noise = s.sub_res("FastNoiseLite", frequency=0.04)
        tex = s.sub_res("NoiseTexture2D", seamless=True, color_ramp=grad, noise=noise)

        def tri(color, scale, rough=0.95):
            return s.sub_res("StandardMaterial3D", albedo_color=color, albedo_texture=tex, roughness=rough,
                             uv1_scale=v3(scale, scale, scale), uv1_triplanar=True)

        self.m_ground = tri(col(0.24, 0.2, 0.15), 0.12, 1.0)
        self.m_cliff = tri(col(0.28, 0.27, 0.27), 0.15)
        self.m_stone = tri(col(0.48, 0.45, 0.43), 0.3)
        self.m_rock = tri(col(0.33, 0.3, 0.29), 0.3)
        self.m_bark = tri(col(0.2, 0.13, 0.09), 0.5)
        self.m_leaf = s.sub_res("StandardMaterial3D", albedo_color=col(0.07, 0.14, 0.09), roughness=1.0)
        self.m_tent = s.sub_res("StandardMaterial3D", albedo_color=col(0.32, 0.18, 0.12), roughness=1.0)
        self.m_crate = tri(col(0.3, 0.2, 0.12), 0.5)
        self.m_stone = s.sub_res("ShaderMaterial", shader=self.res["stone_shader"])
        self.m_cliff = s.sub_res("ShaderMaterial", shader=self.res["rock_shader"], **{"shader_parameter/moss_amount": 0.35, "shader_parameter/scale": 0.35})
        self.m_moss_rock = s.sub_res("ShaderMaterial", shader=self.res["rock_shader"])
        self.m_wood = s.sub_res("ShaderMaterial", shader=self.res["bark_shader"], **{"shader_parameter/moss_amount": 0.0})
        self.m_tent_cloth = s.sub_res("StandardMaterial3D", albedo_color=col(0.42, 0.3, 0.2), roughness=1.0)
        self.m_roof = s.sub_res("StandardMaterial3D", albedo_color=col(0.3, 0.15, 0.1), roughness=0.95)
        self.m_banner = s.sub_res("StandardMaterial3D", albedo_color=col(0.55, 0.06, 0.06), roughness=0.9, cull_mode=2)
        self.m_banner_saffron = s.sub_res("StandardMaterial3D", albedo_color=col(1.0, 0.55, 0.1), roughness=0.9, cull_mode=2)
        self.count = 0

    # geometry helpers (all under NavRegion/Geometry so they shape the navmesh)
    def _name(self, base):
        self.count += 1
        return f"{base}{self.count}"

    def box(self, base, pos, size, material=None, rot=None, collide=True):
        props = {"position": v3(*pos), "use_collision": collide, "size": v3(*size),
                 "material": material or self.m_stone}
        if rot:
            props["rotation_degrees"] = v3(*rot)
        self.s.node(self._name(base), "CSGBox3D", "NavRegion/Geometry", **props)

    def cyl(self, base, pos, radius, height, material=None, cone=False, sides=10, collide=True):
        props = {"position": v3(*pos), "use_collision": collide, "radius": radius, "height": height,
                 "sides": sides, "material": material or self.m_stone}
        if cone:
            props["cone"] = True
        self.s.node(self._name(base), "CSGCylinder3D", "NavRegion/Geometry", **props)

    def floor(self, x0, x1, z0, z1, tile=20.0):
        # Split big floors into tiles: the web renderer lights each mesh with at most 8 lights.
        nx = max(1, round((x1 - x0) / tile))
        nz = max(1, round(abs(z1 - z0) / tile))
        w = (x1 - x0) / nx
        d = (z1 - z0) / nz
        for i in range(nx):
            for j in range(nz):
                cx = x0 + w * (i + 0.5)
                cz = z0 + d * (j + 0.5)
                self.box("Floor", (cx, -0.5, cz), (abs(w), 1, abs(d)), self.m_ground)

    def wall_x(self, x, z0, z1, height=6.0):
        """Wall running along Z at a fixed X."""
        self.box("Cliff", (x, height / 2, (z0 + z1) / 2), (2, height, abs(z1 - z0)), self.m_cliff)

    def wall_z(self, z, x0, x1, height=6.0):
        """Wall running along X at a fixed Z."""
        if abs(x1 - x0) < 0.01:
            return
        self.box("Cliff", ((x0 + x1) / 2, height / 2, z), (abs(x1 - x0), height, 2), self.m_cliff)

    def cross_wall(self, z, half_width, opening=3.0):
        self.wall_z(z, -half_width - 1, -opening)
        self.wall_z(z, opening, half_width + 1)

    def corridor(self, z0, z1, half=4.0):
        self.floor(-half, half, z0, z1)
        self.wall_x(-half, z0, z1)
        self.wall_x(half, z0, z1)

    def tree(self, x, z, height=7.0):
        self.cyl("Trunk", (x, height / 2, z), 0.4, height, self.m_bark, sides=8)
        self.cyl("Canopy", (x, height + 0.5, z), 2.4, 3.0, self.m_leaf, cone=True, sides=8, collide=False)

    # gameplay helpers
    def torch(self, parent, x, z, y=0.0):
        self.s.node(self._name("Torch"), None, parent, instance=self.res["torch"], position=v3(x, y, z))

    def herb(self, parent, x, z):
        self.s.node(self._name("Herb"), None, parent, instance=self.res["herb"], position=v3(x, 0, z))

    def area(self, parent, name, script, pos, size, **props):
        path = self.s.node(name, "Area3D", parent, position=v3(*pos), **({"script": script} if script else {}), **props)
        self.s.node("Shape", "CollisionShape3D", path,
                    shape=self.s.sub_res("BoxShape3D", size=v3(*size)))
        return path

    def caption(self, parent, name, pos, size, speaker, lines, banner=""):
        props = {"speaker": q(speaker), "lines": strings(lines)}
        if banner:
            props["banner"] = q(banner)
        self.area(parent, name, self.res["caption_gd"], pos, size, **props)

    def section(self, index, title, spawn_z, checkpoint_z, half_width, exit_gate_z=None):
        path = f"Sections/S{index}"
        props = {"script": self.res["section_gd"], "index": index, "title": q(title)}
        if exit_gate_z is not None:
            props["exit_gate_path"] = 'NodePath("ExitGate")'
        self.s.node(f"S{index}", "Node3D", "Sections", **props)
        self.s.node("Spawn", "Marker3D", path, position=v3(0, 0, spawn_z))
        self.area(path, "CheckpointArea", None, (0, 1.5, checkpoint_z), (half_width * 2, 3, 3))
        if exit_gate_z is not None:
            self.s.node("ExitGate", None, path, instance=self.res["gate"], position=v3(0, 0, exit_gate_z))
        return path

    def encounter(self, parent, name, trigger=None, banner="", objective=None, lock_gate=None, alert_all=True):
        props = {"script": self.res["encounter_gd"]}
        if banner:
            props["start_banner"] = q(banner)
        if objective:
            props["objective_path"] = f'NodePath("{objective}")'
        if lock_gate:
            props["lock_gate_path"] = f'NodePath("{lock_gate}")'
        if not alert_all:
            props["alert_all_on_start"] = False
        path = self.s.node(name, "Node3D", parent, **props)
        if trigger:
            pos, size = trigger
            self.area(path, "Trigger", None, pos, size)
        return path

    def placed(self, enc, kind, x, z, y=0.0, yaw=0.0, aware=False, patrol=None, **extra):
        if not any(n.startswith(f'[node name="Placed" type="Node3D" parent="{enc}"]') for n in self.s.nodes):
            self.s.node("Placed", "Node3D", enc)
        props = {"position": v3(x, y, z), "start_aware": aware, "start_yaw_degrees": float(yaw)}
        if patrol:
            props["patrol_points"] = "Array[Vector3]([" + ", ".join(v3(*p) for p in patrol) + "])"
        props.update(extra)
        self.s.node(self._name(kind.capitalize()), None, f"{enc}/Placed", instance=self.res[kind], **props)

    def wave(self, enc, number, spawns):
        wave_path = self.s.node(f"Wave{number}", "Node3D", enc)
        for kind, x, z, *rest in spawns:
            props = {"position": v3(x, 0, z), "script": self.res["spawn_gd"], "enemy_scene": self.res[kind]}
            if rest:
                props["rotation_degrees"] = v3(0, rest[0], 0)
            self.s.node(self._name("Spawn"), "Marker3D", wave_path, **props)

    # --- world-building helpers ----------------------------------------------
    def boundary(self, pos, size):
        """Invisible wall: keeps Rama in the play area where hills and trees frame it."""
        path = self.s.node(self._name("Boundary"), "StaticBody3D", "NavRegion/Geometry", position=v3(*pos), collision_mask=0)
        self.s.node("Shape", "CollisionShape3D", path, shape=self.s.sub_res("BoxShape3D", size=v3(*size)))

    def battlement(self, kind, pos, length, height, rot_y=0.0, towers=False, thickness=1.4, decorative=False):
        props = {"position": v3(*pos), "script": self.res["battlement_gd"], "kind": 0 if kind == "palisade" else 1,
                 "length": float(length), "height": float(height), "thickness": float(thickness)}
        if rot_y:
            props["rotation_degrees"] = v3(0, rot_y, 0)
        if towers:
            props["towers"] = True
        if decorative:
            props["decorative"] = True
        self.s.node(self._name("Battlement"), "Node3D", "NavRegion/Geometry", **props)

    def fort_gate(self, z, half_width, opening=3.2):
        """Stone wall across the level at z with an opening and a tower each side of it."""
        for x0, x1 in ((-half_width - 2, -opening), (opening, half_width + 2)):
            self.battlement("fort", ((x0 + x1) / 2, 0, z), abs(x1 - x0), 5.0, thickness=2.0)
        for x in (-opening - 1.2, opening + 1.2):
            self.cyl("GateTower", (x, 3.5, z), 1.5, 7.0, self.m_stone, sides=10)
            self.cyl("GateRoof", (x, 8.1, z), 2.0, 2.2, self.m_roof, cone=True, sides=10, collide=False)

    def stone_corridor(self, z0, z1, half=4.0):
        for x in (-half, half):
            self.battlement("fort", (x, 0, (z0 + z1) / 2), abs(z1 - z0), 4.5, rot_y=90, thickness=1.6)

    def terrain(self, z_near, z_far, play_half, path_half=2.2, inner=0.45, hill=5.0, mounds=(),
                edge_trees=90, inner_trees=0, bushes=60, grass=900, keep_clear=(), edge_min_x=-1.0, seed=1):
        """Two terrain halves (left/right) for one band of the level, each with its own forest.
        (Halves, because the web renderer lights each mesh with at most 8 lights.)"""
        width = play_half + 24
        for side, xr in (("L", (-width, 0)), ("R", (0, width))):
            props = {"script": self.res["terrain_gd"], "x_range": f"Vector2({xr[0]}, {xr[1]})",
                     "z_range": f"Vector2({z_near}, {z_far})", "play_half_width": float(play_half),
                     "path_half_width": float(path_half), "inner_amplitude": float(inner), "hill_height": float(hill)}
            if mounds:
                props["mounds"] = "Array[Vector3]([" + ", ".join(v3(*m) for m in mounds) + "])"
            path = self.s.node(self._name("Terrain" + side), "Node3D", "NavRegion/Geometry", **props)
            scatter = {"script": self.res["scatter_gd"], "seed": seed * 10 + (1 if side == "L" else 2),
                       "edge_trees": edge_trees // 2, "inner_trees": inner_trees // 2, "bushes": bushes // 2,
                       "grass": grass // 2, "edge_min_x": float(edge_min_x)}
            if keep_clear:
                rects = ", ".join(f"Rect2({r[0]}, {r[1]}, {r[2]}, {r[3]})" for r in keep_clear)
                scatter["keep_clear"] = f"Array[Rect2]([{rects}])"
            self.s.node("Forest", "Node3D", path, **scatter)

    def boulder(self, pos, size, rot=0):
        self.s.node(self._name("Boulder"), "Node3D", "NavRegion/Geometry", position=v3(pos[0], 0.0, pos[2]),
                    rotation_degrees=v3(0, rot, 0), script=self.res["rock_gd"],
                    size=v3(size[0], size[1], size[2]), rock_seed=self.count + 3)

    def tent(self, x, z, rot=0):
        """A-frame hide tent (triangular prism) with poles at each end."""
        path = self.s.node(self._name("Tent"), "StaticBody3D", "NavRegion/Geometry", position=v3(x, 0, z),
                           rotation_degrees=v3(0, rot, 0), collision_mask=0)
        self.s.node("Cloth", "MeshInstance3D", path, position=v3(0, 1.15, 0),
                    mesh=self.s.sub_res("PrismMesh", size=v3(3.2, 2.3, 4.4), material=self.m_tent_cloth))
        self.s.node("Shape", "CollisionShape3D", path, position=v3(0, 0.9, 0),
                    shape=self.s.sub_res("BoxShape3D", size=v3(2.6, 1.8, 4.4)))
        for dz in (-2.25, 2.25):
            self.s.node(f"Pole{'A' if dz < 0 else 'B'}", "MeshInstance3D", path, position=v3(0, 1.3, dz),
                        mesh=self.s.sub_res("CylinderMesh", top_radius=0.05, bottom_radius=0.06, height=2.6,
                                            material=self.m_wood))

    def watchtower(self, x, z, height=5.0):
        for dx in (-1.1, 1.1):
            for dz in (-1.1, 1.1):
                self.cyl("TowerPost", (x + dx, height / 2, z + dz), 0.14, height, self.m_wood, sides=6)
        self.box("TowerDeck", (x, height, z), (3.0, 0.2, 3.0), self.m_wood, collide=False)
        for dx, dz, sx, sz in ((0, -1.45, 3.0, 0.12), (0, 1.45, 3.0, 0.12), (-1.45, 0, 0.12, 3.0), (1.45, 0, 0.12, 3.0)):
            self.box("TowerRail", (x + dx, height + 0.55, z + dz), (sx, 0.9, sz), self.m_wood, collide=False)
        self.cyl("TowerRoof", (x, height + 2.1, z), 2.2, 1.4, self.m_roof, cone=True, sides=4, collide=False)

    def banner(self, x, z, color_mat):
        self.cyl("BannerPole", (x, 2.2, z), 0.05, 4.4, self.m_wood, sides=6, collide=False)
        self.box("Banner", (x + 0.45, 3.6, z), (0.9, 1.4, 0.04), color_mat, collide=False)

    # --- build ------------------------------------------------------------------
    def build(self):
        s = self.s
        r = self.res
        # Evening: deep blue sky, rose-violet glow on the horizon, soft cool light.
        sky_mat = s.sub_res("ProceduralSkyMaterial", sky_top_color=col(0.09, 0.12, 0.3),
                            sky_horizon_color=col(0.72, 0.42, 0.5), ground_bottom_color=col(0.05, 0.06, 0.07),
                            ground_horizon_color=col(0.35, 0.3, 0.4), sun_angle_max=10.0, sun_curve=0.1)
        sky = s.sub_res("Sky", sky_material=sky_mat)
        env = s.sub_res("Environment", background_mode=2, sky=sky, ambient_light_source=2,
                        ambient_light_color=col(0.48, 0.53, 0.68), ambient_light_energy=1.0,
                        tonemap_mode=3, tonemap_exposure=1.1, glow_enabled=True, glow_intensity=0.6,
                        glow_bloom=0.04, fog_enabled=True, fog_light_color=col(0.3, 0.34, 0.48),
                        fog_density=0.014, fog_sky_affect=0.25, adjustment_enabled=True,
                        adjustment_contrast=1.08, adjustment_saturation=1.05)

        s.node("Siddhashrama", "Node3D", script=r["level_gd"])
        s.node("WorldEnvironment", "WorldEnvironment", ".", environment=env)
        # Low evening sun: soft rose light, long shadows through the trees.
        s.node("Sun", "DirectionalLight3D", ".", rotation_degrees=v3(-30, -35, 0), light_color=col(1.0, 0.78, 0.74),
               light_energy=1.05, shadow_enabled=True, shadow_opacity=0.75, shadow_blur=1.5,
               directional_shadow_max_distance=45.0)
        s.node("NavRegion", "NavigationRegion3D", ".", navigation_mesh=r["navmesh"])
        s.node("Geometry", "Node3D", "NavRegion")
        s.node("Sections", "Node3D", ".")

        self.build_forest()
        self.build_sentries()
        self.build_camp()
        self.build_ravine()
        self.build_shrine()
        self.build_yagna()

        s.node("Player", None, ".", instance=r["player"], position=v3(0, 0, 0))
        s.node("CameraRig", "Node3D", ".", script=r["rig_gd"], target_path='NodePath("../Player")')
        s.node("Camera3D", "Camera3D", "CameraRig", fov=60.0, far=140.0)
        s.node("HUD", "CanvasLayer", ".", script=r["hud_gd"])
        s.write("scenes/levels/siddhashrama.tscn")

    def build_forest(self):
        # S0: a winding trail through deep forest, z 8 .. -36
        self.terrain(8, -36, 6.5, path_half=1.8, edge_trees=110, bushes=70, grass=900, seed=1,
                     keep_clear=[(-3, -36, 6, 44)])
        self.boundary((-8, 4, -14), (2, 8, 44))
        self.boundary((8, 4, -14), (2, 8, 44))
        self.boundary((0, 4, 7), (18, 8, 2))
        self.boulder((-4.5, 0.3, -20), (1.3, 0.9, 1.1), 25)
        self.boulder((4.8, 0.2, -11), (1.0, 0.7, 1.2), 70)
        sec = self.section(0, "Siddhashrama Forest", -6, -6, 7)
        self.caption(sec, "Intro", (0, 1.5, -9), (14, 3, 3), "Vishwamitra", [
            "Stay close, Rama. Rakshasas prowl these woods after dark.",
            "Where you can, move unseen. Press C to sneak.",
            "Come upon them from behind, and your blades will end them silently.",
        ])
        self.torch(sec, -5.0, -16)
        self.torch(sec, 5.0, -29)

    def build_sentries(self):
        # S1: a wooded hollow with boulders and hills to sneak around, z -36 .. -76
        self.terrain(-36, -80, 15, mounds=[(-9, -55, 1.3), (10, -49, 1.0), (4, -70, 0.7)],
                     edge_trees=100, inner_trees=8, bushes=90, grass=1100, seed=2,
                     keep_clear=[(-4, -80, 8, 46), (-11.5, -64.5, 4, 5), (8, -71, 4, 6), (-9, -52, 18, 4)])
        self.boundary((-17, 4, -56), (2, 8, 40))
        self.boundary((17, 4, -56), (2, 8, 40))
        for x0, x1 in ((-17, -8), (8, 17)):
            self.boundary(((x0 + x1) / 2, 4, -36), (abs(x1 - x0), 8, 2))
        self.fort_gate(-76, 16)
        self.stone_corridor(-76, -84)
        for pos, size, rot in (((-6, 0.6, -46), (1.8, 1.3, 1.4), 10), ((5, 0.7, -53), (2.2, 1.5, 1.3), -15),
                               ((-3, 0.6, -64), (1.5, 1.2, 1.8), 30), ((7, 0.6, -65), (1.3, 1.2, 1.3), 0),
                               ((-13, 0.9, -46), (1.8, 1.8, 2.2), 5), ((12, 0.7, -57), (1.8, 1.5, 1.8), 40)):
            self.boulder(pos, size, rot)
        sec = self.section(1, "The Sentries", -38, -38, 16, exit_gate_z=-76)
        self.caption(sec, "Stealth", (0, 1.5, -40), (30, 3, 3), "Vishwamitra", [
            "Three sentries guard the path. Take them unseen if you can.",
            "Stay out of their sight. Get behind one and strike: Left click or F.",
        ])
        enc = self.encounter(sec, "Sentries", alert_all=False)
        self.placed(enc, "grunt", 0, -50, yaw=0, patrol=[(-7, 0, 0), (7, 0, 0)])
        self.placed(enc, "grunt", -10, -62, yaw=0)
        self.placed(enc, "grunt", 10, -68, yaw=20)
        self.torch(sec, -12, -60)
        self.torch(sec, 12, -66)
        self.torch(sec, 0, -73)
        self.herb(sec, 14, -44)

    def build_camp(self):
        # S2: a rakshasa war camp behind log palisades, z -84 .. -124
        self.terrain(-80, -128, 17.5, inner=0.25, edge_trees=90, bushes=40, grass=600, seed=3,
                     keep_clear=[(-17, -128, 34, 48)], edge_min_x=18.5)
        for x in (-17.2, 17.2):
            self.battlement("palisade", (x, 0, -104), 40, 4.0, rot_y=90, thickness=0.8)
        self.fort_gate(-84, 16)
        self.fort_gate(-124, 16)
        self.stone_corridor(-124, -132)
        for x, z, rot in ((-11, -96, 90), (11, -100, 90), (-10, -116, 0), (12, -117, 0)):
            self.tent(x, z, rot)
        self.watchtower(-14.5, -88)
        self.watchtower(14.5, -121)
        for x, z in ((-6.5, -86.5), (6.5, -86.5), (-15, -110), (15, -96)):
            self.banner(x, z, self.m_banner)
        for pos in ((-5, 0.5, -95), (6, 0.5, -112), (-13, 0.5, -106), (13, 0.5, -108), (-4.2, 0.5, -95.6)):
            self.box("Crate", pos, (1.1, 1.0, 1.1), self.m_crate, rot=(0, 20, 0))
        sec = self.section(2, "Rakshasa Camp", -87, -87, 16, exit_gate_z=-124)
        enc = self.encounter(sec, "CampFight", trigger=((0, 1.5, -92), (30, 3, 4)), banner="Ambush!")
        self.wave(enc, 1, [("grunt", -8, -112, 180), ("grunt", 8, -112, 180), ("grunt", 0, -120, 180),
                           ("grunt", -3, -116, 180)])
        self.wave(enc, 2, [("grunt", -12, -104, 90), ("grunt", 12, -104, -90),
                           ("grunt", -6, -120, 180), ("grunt", 6, -120, 180), ("archer", 0, -122, 180)])
        self.torch(sec, -6, -104)
        self.torch(sec, 6, -108)
        self.torch(sec, 0, -119)
        self.herb(sec, -14, -121)

    def build_ravine(self):
        # S3: a rocky ravine; archers behind log battlements on the ledges, z -132 .. -182
        self.terrain(-128, -186, 7.5, inner=0.3, hill=3.0, edge_trees=70, bushes=30, grass=500, seed=4,
                     edge_min_x=15.5)
        self.box("CliffL", (-15, 4.5, -157), (2, 9, 50), self.m_cliff)
        self.box("CliffR", (15, 4.5, -157), (2, 9, 50), self.m_cliff)
        self.fort_gate(-182, 14)
        self.stone_corridor(-182, -190)
        self.box("LedgeL", (-11, 1.75, -158), (6, 3.5, 40), self.m_cliff)
        self.box("LedgeR", (11, 1.75, -158), (6, 3.5, 40), self.m_cliff)
        for x in (-8.4, 8.4):
            self.battlement("palisade", (x, 3.5, -158), 38, 1.0, rot_y=90, thickness=0.4, decorative=True)
        sec = self.section(3, "The Ravine", -129, -134, 14, exit_gate_z=-182)
        self.caption(sec, "Bow", (0, 1.5, -136), (14, 3, 3), "Vishwamitra", [
            "Archers on the cliffs! Hold right click to aim your bow, then left click to loose. Hold it to charge a piercing shot.",
            "Tab switches your target. An arrow that flies past a torch will catch fire.",
            "Those clay pots are full of oil. Strike one and it will burst.",
        ])
        enc = self.encounter(sec, "Ravine", trigger=((0, 1.5, -138), (14, 3, 4)))
        for x, z, yaw in ((-10.5, -146, -90), (10.5, -158, 90), (-10.5, -170, -90)):
            self.placed(enc, "archer", x, z, y=3.5, yaw=yaw, stationary=True, vision_range=28.0)
        self.wave(enc, 1, [("grunt", 0, -152, 180), ("grunt", 3, -166, 180)])
        self.wave(enc, 2, [("grunt", -3, -176, 180), ("grunt", 3, -176, 180)])
        for x, z in ((-9.2, -148), (9.2, -156), (-9.2, -168)):
            self.s.node(self._name("Pot"), None, sec, instance=self.res["pot"], position=v3(x, 3.5, z))
        self.s.node(self._name("Pot"), None, sec, instance=self.res["pot"], position=v3(4, 0, -171))
        self.torch(sec, -5, -148)
        self.torch(sec, 5, -160)
        self.torch(sec, -5, -172)

    def build_shrine(self):
        # S4: an overgrown ruined shrine in a forest clearing, z -190 .. -230
        self.terrain(-186, -234, 13, inner=0.3, mounds=[(-11, -225, 0.8), (11, -197, 0.7)],
                     edge_trees=100, bushes=70, grass=900, seed=5,
                     keep_clear=[(-11, -228, 22, 34)], edge_min_x=14.5)
        self.boundary((-15, 4, -210), (2, 8, 40))
        self.boundary((15, 4, -210), (2, 8, 40))
        self.fort_gate(-190, 14)
        self.fort_gate(-230, 14)
        self.stone_corridor(-230, -238)
        self.box("Pedestal", (0, 0.6, -206), (2, 1.2, 2), self.m_stone)
        self.box("PedestalStep", (0, 0.15, -206), (3.2, 0.3, 3.2), self.m_stone)
        bell_pillars = [(-7.8, -205.5), (7.8, -214.5), (0, -220)]
        plain_pillars = [(7.8, -205.5), (-7.8, -214.5)]
        for x, z in bell_pillars:
            self.cyl("Pillar", (x, 2.1, z), 0.7, 4.2, self.m_stone, sides=12)
        for x, z in plain_pillars:
            self.cyl("Pillar", (x, 1.3, z), 0.7, 2.6, self.m_stone, sides=12)
        self.box("Ruin", (-12, 0.9, -200), (1.2, 1.8, 6), self.m_stone, rot=(0, 8, 4))
        self.box("Ruin", (12.5, 1.1, -222), (1.2, 2.2, 5), self.m_stone, rot=(0, -12, -3))
        self.boulder((-10, 0.4, -217), (1.3, 0.9, 1.2), 20)
        sec = self.section(4, "The Ruined Shrine", -187, -192, 14, exit_gate_z=-230)
        self.caption(sec, "Shrine", (0, 1.5, -193), (28, 3, 3), "Vishwamitra", [
            "This shrine is older than Ayodhya. Something divine still rests here.",
        ])
        self.s.node("ChakraPickup", None, sec, instance=self.res["chakra"], position=v3(0, 0, -206),
                    speaker=q("Vishwamitra"), lines=strings([
                        "The chakra of the gods. It answers your hand, Rama.",
                        "Throw it with Q. It seeks the nearest foe, cuts all in its path, and returns to you. Its reach is short.",
                        "That brute's shield guards his front. Strike his back with the chakra!",
                        "When the fight is won, ring the three bells to open the way. An arrow will reach them.",
                    ]))
        enc = self.encounter(sec, "ShrineAmbush", trigger=((0, 1.5, -206), (6, 3, 6)), banner="Ambush!")
        self.wave(enc, 1, [("brute", 0, -225, 180), ("grunt", -10, -222, 180), ("grunt", 10, -222, 180)])
        puzzle = self.s.node("Bells", "Node3D", sec, script=self.res["puzzle_gd"])
        for i, (x, z) in enumerate(bell_pillars):
            self.s.node(f"Bell{i + 1}", None, puzzle, instance=self.res["bell"], position=v3(x, 5.0, z))
        self.torch(sec, -11, -198)
        self.torch(sec, 11, -222)
        self.herb(sec, 12, -196)

    def build_yagna(self):
        # S5: Vishwamitra's yagna inside an old stone fort, z -238 .. -292
        self.terrain(-234, -300, 21, inner=0.15, hill=6.0, edge_trees=90, bushes=40, grass=1100, seed=6,
                     keep_clear=[(-22, -294, 44, 58)], edge_min_x=25.0)
        for x in (-23, 23):
            self.battlement("fort", (x, 0, -265), 56, 6.0, rot_y=90, thickness=2.0)
        self.battlement("fort", (0, 0, -293), 48, 6.0, thickness=2.0)
        for x, z in ((-23, -293), (23, -293), (-23, -238), (23, -238)):
            self.cyl("FortTower", (x, 4.5, z), 2.2, 9.0, self.m_stone, sides=12)
            self.cyl("FortRoof", (x, 10.2, z), 2.8, 2.6, self.m_roof, cone=True, sides=12, collide=False)
        self.fort_gate(-238, 22)
        for x, z in ((-19, -288), (19, -288)):
            self.watchtower(x, z, 5.5)
        for x, z in ((-8, -241), (8, -241)):
            self.banner(x, z, self.m_banner_saffron)
        sec = self.section(5, "The Yagna", -235, -240, 22)
        self.s.node("EntryGate", None, sec, instance=self.res["gate"], position=v3(0, 0, -238), start_open=True)
        self.s.node("YagnaAltar", None, sec, instance=self.res["altar"], position=v3(0, 0, -262))
        self.s.node("Vishwamitra", None, sec, instance=self.res["sage"], position=v3(0, 0, -265.5),
                    rotation_degrees=v3(0, 180, 0))
        self.caption(sec, "YagnaIntro", (0, 1.5, -241), (40, 3, 3), "Vishwamitra", [
            "Here, Rama. I begin the rite. The fire must not go out until dawn.",
        ])
        enc = self.encounter(sec, "YagnaEncounter", trigger=((0, 1.5, -244), (40, 3, 4)),
                             banner="Defend the yagna!", objective="../YagnaAltar", lock_gate="../EntryGate")
        self.wave(enc, 1, [("grunt", -14, -284, 180), ("grunt", 14, -284, 180),
                           ("grunt", -20, -270, 90), ("grunt", 20, -270, -90), ("grunt", 0, -289, 180)])
        self.wave(enc, 2, [("grunt", -18, -252, 90), ("grunt", 18, -252, -90), ("grunt", 0, -288, 180),
                           ("archer", -18, -286, 150), ("archer", 18, -286, -150)])
        self.wave(enc, 3, [("brute", 0, -288, 180), ("grunt", -16, -280, 135),
                           ("grunt", 16, -280, -135), ("grunt", 0, -248, 0), ("archer", -18, -286, 150)])
        boss = self.s.node("Boss", "Node3D", sec, script=self.res["boss_gd"], tataka_path='NodePath("Tataka")',
                           intro_lines=strings([
                               "Little prince of Ayodhya... you trespass in MY forest.",
                               "I will grind your bones into the ash of that fire!",
                           ]))
        self.s.node("Tataka", None, boss, instance=self.res["tataka"], position=v3(0, 0, -280))
        adds = self.s.node("AddSpawns", "Node3D", boss)
        for i, (x, z) in enumerate(((-15, -285), (15, -285), (-20, -262), (20, -262))):
            self.s.node(f"Add{i + 1}", "Marker3D", adds, position=v3(x, 0, z))
        for i in range(6):
            a = math.radians(30 + 60 * i)
            self.torch(sec, round(14 * math.cos(a), 2), round(-262 + 14 * math.sin(a), 2))
        self.herb(sec, -20, -244)
        self.herb(sec, 20, -244)


def build_navmesh_params():
    text = """[gd_resource type="NavigationMesh" format=3]

[resource]
geometry_parsed_geometry_type = 1
geometry_source_geometry_mode = 0
cell_size = 0.25
cell_height = 0.25
agent_height = 2.0
agent_radius = 0.5
agent_max_climb = 0.25
agent_max_slope = 30.0
"""
    path = ROOT / "scenes/levels/siddhashrama_navmesh.tres"
    path.write_text(text, encoding="utf-8")
    print("wrote scenes/levels/siddhashrama_navmesh.tres (unbaked)")


if __name__ == "__main__":
    build_torch()
    build_pot()
    build_bell()
    build_gate()
    build_herb()
    build_chakra_pickup()
    build_altar()
    build_vishwamitra()
    build_navmesh_params()
    Level().build()
