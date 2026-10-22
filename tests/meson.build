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
