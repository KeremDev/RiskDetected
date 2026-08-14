#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <adb-serial> <api-label> <evidence-dir>" >&2
  exit 64
fi

serial="$1"
api_label="$2"
evidence_dir="$3"
script_dir="$(cd "$(dirname "$0")" && pwd)"
android_dir="$(cd "$script_dir/.." && pwd)"
adb_bin="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}/platform-tools/adb"
apk_path="$android_dir/app/build/outputs/apk/qa/app-qa.apk"
package_name="com.riskdetectedan.app.qa"
activity_name="com.riskdetectedan.app.MainActivity"

test -x "$adb_bin"
test -f "$apk_path"
mkdir -p "$evidence_dir"

adb_target=("$adb_bin" -s "$serial")

dump_ui() {
  local name="$1"
  "${adb_target[@]}" shell uiautomator dump /sdcard/window.xml >/dev/null
  "${adb_target[@]}" pull /sdcard/window.xml "$evidence_dir/$name-window.xml" >/dev/null
}

capture_screen() {
  local name="$1"
  "${adb_target[@]}" exec-out screencap -p > "$evidence_dir/$name.png"
}

tap_text_from_tree() {
  local text="$1"
  local tree="$2"
  local center
  center="$(ruby -rrexml/document -e '
    document = REXML::Document.new(File.read(ARGV.fetch(0)))
    wanted = ARGV.fetch(1)
    node = REXML::XPath.first(document, "//node[@text=#{wanted.inspect}]")
    abort("text not found: #{wanted}") unless node
    bounds = node.attributes["bounds"].scan(/\d+/).map(&:to_i)
    puts "#{(bounds[0] + bounds[2]) / 2} #{(bounds[1] + bounds[3]) / 2}"
  ' "$tree" "$text")"
  read -r tap_x tap_y <<< "$center"
  "${adb_target[@]}" shell input tap "$tap_x" "$tap_y"
}

assert_tree_contains() {
  local tree="$1"
  local text="$2"
  rg -Fq "text=\"$text\"" "$tree"
}

assert_tree_excludes() {
  local tree="$1"
  local text="$2"
  if rg -Fq "text=\"$text\"" "$tree"; then
    echo "unexpected UI text: $text" >&2
    exit 1
  fi
}

"${adb_target[@]}" wait-for-device
test "$("${adb_target[@]}" shell getprop sys.boot_completed | tr -d '\r')" = "1"
"${adb_target[@]}" shell settings put global window_animation_scale 0
"${adb_target[@]}" shell settings put global transition_animation_scale 0
"${adb_target[@]}" shell settings put global animator_duration_scale 0
"${adb_target[@]}" shell settings put system font_scale 1.0
"${adb_target[@]}" logcat -c >/dev/null 2>&1 || true
"${adb_target[@]}" install -r -t "$apk_path" >/dev/null
"${adb_target[@]}" shell pm clear "$package_name" >/dev/null
"${adb_target[@]}" shell am start -W -n "$package_name/$activity_name" >/dev/null
sleep 4

dump_ui launch
capture_screen launch
assert_tree_contains "$evidence_dir/launch-window.xml" "Atla"
tap_text_from_tree "Atla" "$evidence_dir/launch-window.xml"
sleep 1

dump_ui skip-confirmation
capture_screen skip-confirmation
assert_tree_contains "$evidence_dir/skip-confirmation-window.xml" "Yine de atla"
tap_text_from_tree "Yine de atla" "$evidence_dir/skip-confirmation-window.xml"
sleep 3

dump_ui auth
capture_screen auth
assert_tree_contains "$evidence_dir/auth-window.xml" "E-posta ile giriş yap"
assert_tree_contains "$evidence_dir/auth-window.xml" "Google ile devam et"
assert_tree_excludes "$evidence_dir/auth-window.xml" "Apple ile devam et"
assert_tree_excludes "$evidence_dir/auth-window.xml" "Son adım."

"${adb_target[@]}" shell am force-stop "$package_name"
"${adb_target[@]}" shell am start -W -n "$package_name/$activity_name" >/dev/null
sleep 3
dump_ui cold-relaunch-auth
capture_screen cold-relaunch-auth
assert_tree_contains "$evidence_dir/cold-relaunch-auth-window.xml" "E-posta ile giriş yap"
assert_tree_excludes "$evidence_dir/cold-relaunch-auth-window.xml" "Son adım."

{
  echo "serial=$serial"
  echo "api_label=$api_label"
  echo "sdk=$("${adb_target[@]}" shell getprop ro.build.version.sdk | tr -d '\r')"
  echo "model=$("${adb_target[@]}" shell getprop ro.product.model | tr -d '\r')"
  echo "size=$("${adb_target[@]}" shell wm size | tr -d '\r')"
  echo "density=$("${adb_target[@]}" shell wm density | tr -d '\r')"
  echo "font_scale=$("${adb_target[@]}" shell settings get system font_scale | tr -d '\r')"
  shasum -a 256 "$apk_path"
} > "$evidence_dir/device-and-artifact.txt"

"${adb_target[@]}" logcat -d -b crash > "$evidence_dir/crash-buffer.txt"
"${adb_target[@]}" logcat -d -s AndroidRuntime:E ActivityTaskManager:I > "$evidence_dir/filtered-logcat.txt"

if rg -i "FATAL EXCEPTION|ANR in $package_name" "$evidence_dir/crash-buffer.txt" "$evidence_dir/filtered-logcat.txt"; then
  echo "crash or ANR detected" >&2
  exit 1
fi

echo "PASS $api_label $serial"
