#!/system/bin/sh
# Debug-only, app-local bootstrap. Nothing is injected into SystemUI/Zygote.
runner="$1"
shift
/system/bin/log -t RodinTileLab "WRAPPER runner=$runner remaining=$#"
case "$runner" in
    */app_process*) ;;
    *) exec "$runner" "$@" ;;
esac
lab_dir="${0%/*}"
# Install paths contain '='; ART treats that character as agent options.
# A relative path avoids truncating the library name at the install token.
cd "$lab_dir" || exit 1
exec "$runner" -Xplugin:libopenjdkjvmti.so \
    -Xcompiler-option --debuggable -agentpath:./librodin_tile_lab.so "$@"
