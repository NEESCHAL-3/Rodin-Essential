#include <stddef.h>
#include <stdio.h>
#include "embedder.h"

#define RUST_CONST(name, value) \
  printf("pub const " name ": usize = %zu;\n", (size_t)(value))

int main(void) {
  RUST_CONST("FLUTTER_RENDERER_CONFIG_SIZE", sizeof(FlutterRendererConfig));
  RUST_CONST("OFF_RENDERER_TYPE", offsetof(FlutterRendererConfig, type));
  RUST_CONST("OFF_RENDERER_SOFTWARE", offsetof(FlutterRendererConfig, software));
  RUST_CONST("FLUTTER_SOFTWARE_RENDERER_CONFIG_SIZE",
             sizeof(FlutterSoftwareRendererConfig));
  RUST_CONST("OFF_SOFTWARE_STRUCT_SIZE",
             offsetof(FlutterSoftwareRendererConfig, struct_size));
  RUST_CONST("OFF_SOFTWARE_PRESENT",
             offsetof(FlutterSoftwareRendererConfig, surface_present_callback));

  RUST_CONST("FLUTTER_PROJECT_ARGS_SIZE", sizeof(FlutterProjectArgs));
  RUST_CONST("OFF_PROJECT_STRUCT_SIZE", offsetof(FlutterProjectArgs, struct_size));
  RUST_CONST("OFF_PROJECT_ASSETS_PATH", offsetof(FlutterProjectArgs, assets_path));
  RUST_CONST("OFF_PROJECT_ICU_DATA_PATH", offsetof(FlutterProjectArgs, icu_data_path));
  RUST_CONST("OFF_PROJECT_COMMAND_LINE_ARGC",
             offsetof(FlutterProjectArgs, command_line_argc));
  RUST_CONST("OFF_PROJECT_COMMAND_LINE_ARGV",
             offsetof(FlutterProjectArgs, command_line_argv));
  RUST_CONST("OFF_PROJECT_VM_DATA", offsetof(FlutterProjectArgs, vm_snapshot_data));
  RUST_CONST("OFF_PROJECT_VM_DATA_SIZE",
             offsetof(FlutterProjectArgs, vm_snapshot_data_size));
  RUST_CONST("OFF_PROJECT_VM_INSTRUCTIONS",
             offsetof(FlutterProjectArgs, vm_snapshot_instructions));
  RUST_CONST("OFF_PROJECT_VM_INSTRUCTIONS_SIZE",
             offsetof(FlutterProjectArgs, vm_snapshot_instructions_size));
  RUST_CONST("OFF_PROJECT_ISOLATE_DATA",
             offsetof(FlutterProjectArgs, isolate_snapshot_data));
  RUST_CONST("OFF_PROJECT_ISOLATE_DATA_SIZE",
             offsetof(FlutterProjectArgs, isolate_snapshot_data_size));
  RUST_CONST("OFF_PROJECT_ISOLATE_INSTRUCTIONS",
             offsetof(FlutterProjectArgs, isolate_snapshot_instructions));
  RUST_CONST("OFF_PROJECT_ISOLATE_INSTRUCTIONS_SIZE",
             offsetof(FlutterProjectArgs, isolate_snapshot_instructions_size));
  RUST_CONST("OFF_PROJECT_PERSISTENT_CACHE_PATH",
             offsetof(FlutterProjectArgs, persistent_cache_path));
  RUST_CONST("OFF_PROJECT_SHUTDOWN_VM",
             offsetof(FlutterProjectArgs, shutdown_dart_vm_when_done));
  RUST_CONST("OFF_PROJECT_LOG_CALLBACK",
             offsetof(FlutterProjectArgs, log_message_callback));
  RUST_CONST("OFF_PROJECT_LOG_TAG", offsetof(FlutterProjectArgs, log_tag));
  RUST_CONST("OFF_PROJECT_ENABLE_WIDE_GAMUT",
             offsetof(FlutterProjectArgs, enable_wide_gamut));

  RUST_CONST("FLUTTER_WINDOW_METRICS_SIZE", sizeof(FlutterWindowMetricsEvent));
  RUST_CONST("OFF_METRICS_STRUCT_SIZE",
             offsetof(FlutterWindowMetricsEvent, struct_size));
  RUST_CONST("OFF_METRICS_WIDTH", offsetof(FlutterWindowMetricsEvent, width));
  RUST_CONST("OFF_METRICS_HEIGHT", offsetof(FlutterWindowMetricsEvent, height));
  RUST_CONST("OFF_METRICS_PIXEL_RATIO",
             offsetof(FlutterWindowMetricsEvent, pixel_ratio));
  RUST_CONST("OFF_METRICS_DISPLAY_ID",
             offsetof(FlutterWindowMetricsEvent, display_id));
  RUST_CONST("OFF_METRICS_VIEW_ID", offsetof(FlutterWindowMetricsEvent, view_id));
  RUST_CONST("OFF_METRICS_HAS_CONSTRAINTS",
             offsetof(FlutterWindowMetricsEvent, has_constraints));

  RUST_CONST("FLUTTER_POINTER_EVENT_SIZE", sizeof(FlutterPointerEvent));
  RUST_CONST("OFF_POINTER_STRUCT_SIZE", offsetof(FlutterPointerEvent, struct_size));
  RUST_CONST("OFF_POINTER_PHASE", offsetof(FlutterPointerEvent, phase));
  RUST_CONST("OFF_POINTER_TIMESTAMP", offsetof(FlutterPointerEvent, timestamp));
  RUST_CONST("OFF_POINTER_X", offsetof(FlutterPointerEvent, x));
  RUST_CONST("OFF_POINTER_Y", offsetof(FlutterPointerEvent, y));
  RUST_CONST("OFF_POINTER_DEVICE", offsetof(FlutterPointerEvent, device));
  RUST_CONST("OFF_POINTER_SIGNAL_KIND", offsetof(FlutterPointerEvent, signal_kind));
  RUST_CONST("OFF_POINTER_SCROLL_X", offsetof(FlutterPointerEvent, scroll_delta_x));
  RUST_CONST("OFF_POINTER_SCROLL_Y", offsetof(FlutterPointerEvent, scroll_delta_y));
  RUST_CONST("OFF_POINTER_DEVICE_KIND", offsetof(FlutterPointerEvent, device_kind));
  RUST_CONST("OFF_POINTER_BUTTONS", offsetof(FlutterPointerEvent, buttons));
  RUST_CONST("OFF_POINTER_VIEW_ID", offsetof(FlutterPointerEvent, view_id));
  RUST_CONST("OFF_POINTER_PRESSURE", offsetof(FlutterPointerEvent, pressure));
  RUST_CONST("OFF_POINTER_PRESSURE_MIN", offsetof(FlutterPointerEvent, pressure_min));
  RUST_CONST("OFF_POINTER_PRESSURE_MAX", offsetof(FlutterPointerEvent, pressure_max));

  return 0;
}
