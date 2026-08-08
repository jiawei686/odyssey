"""Rapid named landmark capture for the Radiographic Anatomy POC.

Run inside Blender, then use the Anatomy tab in the 3D View sidebar. The modal
operator ray-casts each left-click onto the visible model, creates a named
marker, advances to the next queued landmark, and exports the current marker
set to JSON after every capture.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import blf
import bmesh
import bpy
from bpy.props import FloatProperty, PointerProperty, StringProperty
from bpy_extras import view3d_utils


DEFAULT_BATCH = ", ".join(
    (
        "DistalRadius",
        "DistalUlna",
        "IndexMCP",
        "IndexPIP",
        "IndexDIP",
        "IndexTip",
    )
)
DEFAULT_EXPORT_PATH = str(
    Path(__file__).resolve().parents[1]
    / "UpperLimbPOC"
    / "AnatomyLandmarks.user.json"
)
MARKER_PREFIX = "LM_"
MARKER_COLLECTION = "AnatomyLandmarks"


def _target_names(scene: bpy.types.Scene) -> list[str]:
    return [
        item.strip()
        for item in scene.anatomy_landmark_batch_names.split(",")
        if item.strip()
    ]


def _marker_object_name(target: str) -> str:
    safe_name = re.sub(r"[^A-Za-z0-9_]+", "_", target.strip()).strip("_")
    return f"{MARKER_PREFIX}{safe_name or 'Unnamed'}"


def _marker_collection(scene: bpy.types.Scene) -> bpy.types.Collection:
    collection = bpy.data.collections.get(MARKER_COLLECTION)
    if collection is None:
        collection = bpy.data.collections.new(MARKER_COLLECTION)
        scene.collection.children.link(collection)
    return collection


def _marker_material() -> bpy.types.Material:
    material = bpy.data.materials.get("LM_ClinicalReview")
    if material is None:
        material = bpy.data.materials.new("LM_ClinicalReview")
        material.diffuse_color = (1.0, 0.03, 0.03, 1.0)
        material.metallic = 0.0
        material.roughness = 0.35
    return material


def _create_marker_mesh(name: str, radius_m: float) -> bpy.types.Mesh:
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    builder = bmesh.new()
    bmesh.ops.create_icosphere(builder, subdivisions=2, radius=radius_m)
    builder.to_mesh(mesh)
    builder.free()
    return mesh


def _model_position(scene: bpy.types.Scene, world_location):
    anchor = scene.anatomy_landmark_model_space_anchor
    if anchor is None:
        return world_location.copy()
    return anchor.matrix_world.inverted() @ world_location


def _world_position(scene: bpy.types.Scene, model_location):
    anchor = scene.anatomy_landmark_model_space_anchor
    if anchor is None:
        return model_location.copy()
    return anchor.matrix_world @ model_location


def upsert_marker(
    scene: bpy.types.Scene,
    target: str,
    model_location,
) -> tuple[bpy.types.Object, tuple[float, float, float] | None]:
    object_name = _marker_object_name(target)
    marker = bpy.data.objects.get(object_name)
    previous_location = tuple(marker.location) if marker is not None else None

    if marker is None:
        mesh = _create_marker_mesh(object_name, scene.anatomy_landmark_radius_mm / 1000.0)
        marker = bpy.data.objects.new(object_name, mesh)
        _marker_collection(scene).objects.link(marker)
        marker.data.materials.append(_marker_material())

    anchor = scene.anatomy_landmark_model_space_anchor
    marker.parent = anchor
    marker.matrix_parent_inverse.identity()
    marker.location = model_location
    marker["landmark_name"] = target
    marker["coordinate_space"] = "model metres"
    marker.show_name = True
    marker.show_in_front = True
    marker.color = (1.0, 0.03, 0.03, 1.0)

    for selected in list(bpy.context.selected_objects):
        selected.select_set(False)
    marker.select_set(True)
    bpy.context.view_layer.objects.active = marker
    scene.cursor.location = _world_position(scene, model_location)
    return marker, previous_location


def export_landmarks(scene: bpy.types.Scene) -> Path:
    export_path = Path(bpy.path.abspath(scene.anatomy_landmark_export_path)).expanduser()
    export_path.parent.mkdir(parents=True, exist_ok=True)

    landmarks = []
    anchor = scene.anatomy_landmark_model_space_anchor
    for marker in sorted(
        (obj for obj in bpy.data.objects if obj.name.startswith(MARKER_PREFIX)),
        key=lambda obj: obj.name,
    ):
        world_location = marker.matrix_world.translation
        model_location = _model_position(scene, world_location)
        landmarks.append(
            {
                "name": marker.get("landmark_name", marker.name[len(MARKER_PREFIX) :]),
                "objectName": marker.name,
                "positionMetres": {
                    "x": round(float(model_location.x), 6),
                    "y": round(float(model_location.y), 6),
                    "z": round(float(model_location.z), 6),
                },
            }
        )

    payload = {
        "schemaVersion": 1,
        "coordinateSpace": (
            f"local to Blender object {anchor.name}"
            if anchor is not None
            else "Blender scene world / imported USD stage root"
        ),
        "modelSpaceAnchor": anchor.name if anchor is not None else None,
        "units": "metres",
        "clinicalStatus": "clinician-selected review landmarks; not diagnostic registration",
        "landmarks": landmarks,
    }
    export_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    return export_path


class ANATOMY_OT_start_landmark_batch(bpy.types.Operator):
    bl_idname = "anatomy.start_landmark_batch"
    bl_label = "Start Named Capture"
    bl_description = "Click the model once for each displayed landmark name"

    _targets: list[str]
    _index: int
    _history: list[tuple[str, tuple[float, float, float] | None]]
    _region: bpy.types.Region | None
    _rv3d: bpy.types.RegionView3D | None
    _handle = None

    def _current_prompt(self) -> str:
        if self._index >= len(self._targets):
            return "Batch complete"
        return (
            f"LANDMARK {self._index + 1}/{len(self._targets)}: "
            f"{self._targets[self._index]}  |  Left-click bone  |  "
            "Backspace undo  |  Esc stop"
        )

    def _update_prompt(self, context: bpy.types.Context) -> None:
        prompt = self._current_prompt()
        context.scene.anatomy_landmark_status = prompt
        if context.area is not None:
            context.area.header_text_set(prompt)
            context.area.tag_redraw()

    def _draw_prompt(self) -> None:
        if self._index >= len(self._targets):
            return
        text = f"Click: {self._targets[self._index]} ({self._index + 1}/{len(self._targets)})"
        blf.position(0, 28, 72, 0)
        blf.size(0, 22)
        blf.color(0, 1.0, 0.9, 0.15, 1.0)
        blf.draw(0, text)

    def _finish(self, context: bpy.types.Context, message: str):
        if self._handle is not None:
            bpy.types.SpaceView3D.draw_handler_remove(self._handle, "WINDOW")
            self._handle = None
        if context.area is not None:
            context.area.header_text_set(None)
            context.area.tag_redraw()
        context.scene.anatomy_landmark_status = message
        export_path = export_landmarks(context.scene)
        self.report({"INFO"}, f"{message}. Exported {export_path.name}")

    def invoke(self, context: bpy.types.Context, _event):
        if context.area is None or context.area.type != "VIEW_3D":
            self.report({"ERROR"}, "Start the batch from a 3D View")
            return {"CANCELLED"}

        self._targets = _target_names(context.scene)
        if not self._targets:
            self.report({"ERROR"}, "Enter at least one comma-separated landmark name")
            return {"CANCELLED"}

        self._region = next(
            (region for region in context.area.regions if region.type == "WINDOW"),
            None,
        )
        self._rv3d = context.space_data.region_3d
        if self._region is None or self._rv3d is None:
            self.report({"ERROR"}, "The 3D viewport is not ready")
            return {"CANCELLED"}

        self._index = 0
        self._history = []
        self._handle = bpy.types.SpaceView3D.draw_handler_add(
            self._draw_prompt,
            (),
            "WINDOW",
            "POST_PIXEL",
        )
        context.window_manager.modal_handler_add(self)
        self._update_prompt(context)
        return {"RUNNING_MODAL"}

    def modal(self, context: bpy.types.Context, event):
        if event.type == "ESC":
            self._finish(context, f"Stopped after {self._index}/{len(self._targets)} landmarks")
            return {"CANCELLED"}

        if event.type == "BACK_SPACE" and event.value == "PRESS":
            if self._history:
                object_name, previous_location = self._history.pop()
                marker = bpy.data.objects.get(object_name)
                if marker is not None:
                    if previous_location is None:
                        bpy.data.objects.remove(marker, do_unlink=True)
                    else:
                        marker.location = previous_location
                self._index = max(0, self._index - 1)
                export_landmarks(context.scene)
                self._update_prompt(context)
            return {"RUNNING_MODAL"}

        if event.type != "LEFTMOUSE" or event.value != "RELEASE":
            return {"PASS_THROUGH"}

        region = self._region
        rv3d = self._rv3d
        if region is None or rv3d is None:
            self._finish(context, "Viewport context was lost")
            return {"CANCELLED"}

        coordinate = (event.mouse_x - region.x, event.mouse_y - region.y)
        if not (0 <= coordinate[0] < region.width and 0 <= coordinate[1] < region.height):
            return {"PASS_THROUGH"}

        ray_origin = view3d_utils.region_2d_to_origin_3d(region, rv3d, coordinate)
        ray_direction = view3d_utils.region_2d_to_vector_3d(region, rv3d, coordinate)
        hit, location, _normal, _face, hit_object, _matrix = context.scene.ray_cast(
            context.evaluated_depsgraph_get(),
            ray_origin,
            ray_direction,
        )
        if not hit or hit_object is None:
            self.report({"WARNING"}, "No model surface under the click; try again")
            return {"RUNNING_MODAL"}
        if hit_object.name.startswith(MARKER_PREFIX):
            self.report({"WARNING"}, "Clicked an existing landmark; click the bone surface")
            return {"RUNNING_MODAL"}

        target = self._targets[self._index]
        model_location = _model_position(context.scene, location)
        marker, previous_location = upsert_marker(
            context.scene,
            target,
            model_location,
        )
        self._history.append((marker.name, previous_location))
        export_landmarks(context.scene)
        self._index += 1

        if self._index >= len(self._targets):
            self._finish(context, f"Completed {len(self._targets)} named landmarks")
            return {"FINISHED"}

        self._update_prompt(context)
        return {"RUNNING_MODAL"}


class ANATOMY_OT_export_landmarks(bpy.types.Operator):
    bl_idname = "anatomy.export_landmarks"
    bl_label = "Export Landmark JSON"

    def execute(self, context: bpy.types.Context):
        export_path = export_landmarks(context.scene)
        context.scene.anatomy_landmark_status = f"Exported {export_path}"
        self.report({"INFO"}, f"Exported {export_path.name}")
        return {"FINISHED"}


class VIEW3D_PT_anatomy_landmarks(bpy.types.Panel):
    bl_label = "Named Landmark Capture"
    bl_idname = "VIEW3D_PT_anatomy_landmarks"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "Anatomy"

    def draw(self, context: bpy.types.Context):
        layout = self.layout
        scene = context.scene
        layout.label(text="Comma-separated click order:")
        layout.prop(scene, "anatomy_landmark_batch_names", text="")
        layout.prop(scene, "anatomy_landmark_radius_mm")
        layout.prop(scene, "anatomy_landmark_model_space_anchor", text="Model anchor")
        if scene.anatomy_landmark_model_space_anchor is None:
            layout.label(
                text="Using imported USD stage / Blender world",
                icon="WORLD_DATA",
            )
        layout.operator("anatomy.start_landmark_batch", icon="RESTRICT_SELECT_OFF")
        layout.separator()
        layout.label(text=scene.anatomy_landmark_status, icon="INFO")
        layout.prop(scene, "anatomy_landmark_export_path", text="Export")
        layout.operator("anatomy.export_landmarks", icon="EXPORT")


CLASSES = (
    ANATOMY_OT_start_landmark_batch,
    ANATOMY_OT_export_landmarks,
    VIEW3D_PT_anatomy_landmarks,
)


def register() -> None:
    for cls in CLASSES:
        bpy.utils.register_class(cls)

    bpy.types.Scene.anatomy_landmark_batch_names = StringProperty(
        name="Landmark names",
        default=DEFAULT_BATCH,
        description="Comma-separated capture order",
    )
    bpy.types.Scene.anatomy_landmark_radius_mm = FloatProperty(
        name="Marker size (mm)",
        default=4.0,
        min=1.0,
        max=12.0,
        precision=1,
    )
    bpy.types.Scene.anatomy_landmark_export_path = StringProperty(
        name="Export path",
        default=DEFAULT_EXPORT_PATH,
        subtype="FILE_PATH",
    )
    bpy.types.Scene.anatomy_landmark_model_space_anchor = PointerProperty(
        name="Model-space anchor",
        type=bpy.types.Object,
        description=(
            "Optional parent transform for model-local export. Leave empty only "
            "when Blender scene world is the imported USD stage root"
        ),
    )
    bpy.types.Scene.anatomy_landmark_status = StringProperty(
        name="Status",
        default="Ready for named capture",
    )


def unregister() -> None:
    for property_name in (
        "anatomy_landmark_status",
        "anatomy_landmark_export_path",
        "anatomy_landmark_model_space_anchor",
        "anatomy_landmark_radius_mm",
        "anatomy_landmark_batch_names",
    ):
        if hasattr(bpy.types.Scene, property_name):
            delattr(bpy.types.Scene, property_name)

    for cls in reversed(CLASSES):
        bpy.utils.unregister_class(cls)


if __name__ == "__main__":
    register()
