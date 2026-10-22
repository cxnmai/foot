config_test = executable(
  'test-config',
  'test-config.c',
  wl_proto_headers,
  link_with: [common, tokenize],
  dependencies: [pixman, xkb, fontconfig, wayland_client, fcft, tllist])

test('config', config_test)

test('zig-tab-policy', zig,
  args: ['test', '-O', 'safe', '-lc', '--dep', 'tab_abi',
         '-Mroot=' + meson.project_source_root() / 'tab-policy.zig',
         '-Mtab_abi=' + tab_abi.full_path()],
  depends: tabs_object,
  timeout: 120)

test('zig-tabs', zig,
  args: ['test', '-O', 'safe', '-lc', '--dep', 'tab_abi',
         '-Mroot=' + meson.project_source_root() / 'tab-bar.zig',
         '-Mtab_abi=' + tab_abi.full_path()],
  depends: tabs_object,
  timeout: 120)

test('zig-graphics-command', zig,
  args: ['test', '-O', 'safe', '-fcompiler-rt', '-lc', '--dep', 'graphics_abi',
         '-Mroot=' + meson.project_source_root() / 'graphics-command.zig',
         '-Mgraphics_abi=' + graphics_abi.full_path()],
  depends: graphics_object,
  timeout: 120)

test('zig-graphics-render', zig,
  args: ['test', '-O', 'safe', '-fcompiler-rt', '-lc', '--dep', 'graphics_abi',
         '-Mroot=' + meson.project_source_root() / 'graphics-render.zig',
         '-Mgraphics_abi=' + graphics_abi.full_path()],
  depends: graphics_object,
  timeout: 120)

# terminal.o pulls the application's dependency graph. Share production code,
# without main.c, rather than replacing terminal/grid behavior with test stubs.
terminal_test_dependencies = [
  math, threads, libepoll, pixman, wayland_client, wayland_cursor,
  xkb, fontconfig, utf8proc, tllist, fcft, png, zlib]
terminal_test_support = static_library(
  'terminal-test-support',
  '../async.c', '../box-drawing.c', '../config.c', '../commands.c',
  '../extract.c', '../fdm.c', '../foot-features.c', '../ime.c', '../input.c',
  '../key-binding.c', '../notify.c', '../quirks.c', '../reaper.c', '../render.c',
  '../tab-bridge.c', '../tab-draw.c', '../graphics-native.c', '../graphics-paint.c',
  '../search.c', '../server.c', '../shm.c', '../slave.c', '../spawn.c',
  '../tokenize.c', '../unicode-mode.c', '../url-mode.c', '../user-notification.c',
  '../wayland.c', tabs_object, graphics_object,
  srgb_funcs, wl_proto_headers, version,
  include_directories: include_directories('..'),
  dependencies: terminal_test_dependencies,
  link_with: pgolib)

ascii_run_test = executable(
  'test-ascii-run', 'test-ascii-run.c', wl_proto_headers,
  include_directories: include_directories('..'),
  dependencies: terminal_test_dependencies,
  link_with: terminal_test_support)
test('ascii-run', ascii_run_test)

graphics_upload_vt_test = executable(
  'test-graphics-upload-vt', 'test-graphics-upload-vt.c', wl_proto_headers,
  include_directories: include_directories('..'),
  dependencies: terminal_test_dependencies,
  link_with: terminal_test_support,
  link_args: ['-Wl,--wrap=kg_new', '-Wl,--wrap=kg_begin', '-Wl,--wrap=kg_put',
              '-Wl,--wrap=kg_put_bytes', '-Wl,--wrap=kg_end', '-Wl,--wrap=kg_abort'])
test('graphics-upload-vt', graphics_upload_vt_test)

test('zig-graphics-upload', zig,
  args: ['test', '-O', 'safe', '-fcompiler-rt', '-lc',
         meson.current_source_dir() / 'graphics-upload-native.c',
         '--dep', 'graphics_abi',
         '-Mroot=' + meson.project_source_root() / 'graphics.zig',
         '-Mgraphics_abi=' + graphics_abi.full_path()],
  depends: graphics_object,
  timeout: 120)

test('zig-graphics-placement', zig,
  args: ['test', '-O', 'safe', '-fcompiler-rt', '-lc', '--dep', 'graphics_abi',
         '-Mroot=' + meson.project_source_root() / 'graphics-placement.zig',
         '-Mgraphics_abi=' + graphics_abi.full_path()],
  depends: graphics_object,
  timeout: 120)
