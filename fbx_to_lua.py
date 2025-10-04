#!/usr/bin/env python3
"""
FBX to Lua Converter for Picotron 3D Engine
Converts FBX/OBJ mesh files to Lua table format

For FBX support, install Blender and use this script with Blender's Python:
  blender --background --python fbx_to_lua.py -- input.fbx output.lua

For OBJ files, no dependencies needed.
"""

import sys
import os

# Try to import FBX SDK
try:
    from fbx import *
    HAS_FBX_SDK = True
except ImportError:
    HAS_FBX_SDK = False


def convert_fbx_to_lua(fbx_path, output_path=None):
    """Convert FBX file to Lua format"""
    if not output_path:
        output_path = os.path.splitext(fbx_path)[0] + ".lua"

    print("Error: FBX conversion not supported")
    print("Please export your model as OBJ format instead.")
    print("Most 3D software (Blender, Maya, 3DS Max, etc.) can export to OBJ.")
    sys.exit(1)


def convert_obj_to_lua(obj_path, output_path=None):
    """Simple OBJ converter as fallback"""
    if not output_path:
        output_path = os.path.splitext(obj_path)[0] + ".lua"

    vertices = []
    uvs = []
    faces = []

    with open(obj_path, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if not parts:
                continue

            if parts[0] == 'v':
                # Vertex position
                vertices.append((float(parts[1]), float(parts[2]), float(parts[3])))
            elif parts[0] == 'vt':
                # UV coordinate
                uvs.append((float(parts[1]), float(parts[2])))
            elif parts[0] == 'f':
                # Face (format: v/vt/vn or v/vt or v)
                face_verts = []
                face_uvs = []
                for vert in parts[1:]:
                    indices = vert.split('/')
                    v_idx = int(indices[0])
                    face_verts.append(v_idx)
                    if len(indices) > 1 and indices[1]:
                        uv_idx = int(indices[1])
                        face_uvs.append(uv_idx)

                # Triangulate if needed (invert winding order for backface culling)
                for i in range(len(face_verts) - 2):
                    tri = (face_verts[0], face_verts[i+2], face_verts[i+1])  # Inverted order
                    if face_uvs:
                        tri_uvs = (face_uvs[0], face_uvs[i+2], face_uvs[i+1])  # Inverted order
                        faces.append((tri, tri_uvs))
                    else:
                        faces.append((tri, None))

    # Write Lua file
    with open(output_path, 'w') as f:
        f.write("-- Auto-generated from: {}\n".format(os.path.basename(obj_path)))
        f.write("-- Picotron 3D Engine mesh format\n\n")

        f.write("local mesh_verts = {\n")
        for v in vertices:
            f.write(f"\tvec({v[0]:.4f}, {v[1]:.4f}, {v[2]:.4f}),\n")
        f.write("}\n\n")

        f.write("local mesh_faces = {\n")
        for face_data in faces:
            tri, tri_uvs = face_data
            if tri_uvs and uvs:
                uv1 = uvs[tri_uvs[0] - 1]
                uv2 = uvs[tri_uvs[1] - 1]
                uv3 = uvs[tri_uvs[2] - 1]
                f.write(f"\t{{{tri[0]}, {tri[1]}, {tri[2]}, 0, ")
                f.write(f"vec({uv1[0]*16:.2f},{(1-uv1[1])*16:.2f}), ")
                f.write(f"vec({uv2[0]*16:.2f},{(1-uv2[1])*16:.2f}), ")
                f.write(f"vec({uv3[0]*16:.2f},{(1-uv3[1])*16:.2f})}},\n")
            else:
                f.write(f"\t{{{tri[0]}, {tri[1]}, {tri[2]}, 0, ")
                f.write(f"vec(0,0), vec(16,0), vec(16,16)}},\n")
        f.write("}\n\n")

        f.write("return {\n")
        f.write("\tverts = mesh_verts,\n")
        f.write("\tfaces = mesh_faces,\n")
        f.write('\tname = "mesh"\n')
        f.write("}\n")

    print(f"Converted {obj_path} -> {output_path}")
    print(f"Vertices: {len(vertices)}, Faces: {len(faces)}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python fbx_to_lua.py <input.fbx|input.obj> [output.lua]")
        print("\nExample:")
        print("  python fbx_to_lua.py building.fbx")
        print("  python fbx_to_lua.py model.obj custom_output.lua")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else None

    if not os.path.exists(input_file):
        print(f"Error: File not found: {input_file}")
        sys.exit(1)

    ext = os.path.splitext(input_file)[1].lower()

    if ext == '.fbx':
        convert_fbx_to_lua(input_file, output_file)
    elif ext == '.obj':
        convert_obj_to_lua(input_file, output_file)
    else:
        print(f"Error: Unsupported file format: {ext}")
        print("Supported: .fbx, .obj")
        sys.exit(1)
