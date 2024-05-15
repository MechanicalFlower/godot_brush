#!/usr/bin/env -S just --justfile

set dotenv-load := true

export PIP_REQUIRE_VIRTUALENV := "true"

# === Aliases ===

[private]
alias g := godot

[private]
alias e := editor

# === Variables ===

# Global directories
# To make the Godot binaries available for other projects
home_dir := env_var('HOME')
main_dir := home_dir / ".mkflower"
cache_dir := main_dir / "cache"
bin_dir := main_dir / "bin"

# Godot variables
godot_version := env_var('GODOT_VERSION')
godot_platform := if arch() == "x86" {
 "linux.x86_32"
} else if arch() == "x86_64" {
    "linux.x86_64"
} else if arch() == "arm" {
    "linux.arm32"
} else if arch() == "aarch64" {
    "linux.arm64"
} else {
    ""
}
godot_filename := "Godot_v" + godot_version + "-stable_" + godot_platform
godot_bin := bin_dir / godot_filename

# Addon variables
addon_name := env_var('ADDON_NAME')
addon_version := env_var('ADDON_VERSION')

# Python virtualenv
venv_dir := justfile_directory() / "venv"

# === Commands ===

# Display all commands
@default:
    echo "OS: {{ os() }} - ARCH: {{ arch() }}\n"
    just --list

# Create directories
[private]
@makedirs:
    mkdir -p {{ cache_dir }} {{ bin_dir }}

# === Installer ===
#
# Recipes for checking and/or installing binaries like Godot and Butler.
# Ensures consistent environments across CI and local development.

# Download Godot
[private]
install-godot: makedirs
    curl -L --progress-bar -X GET "https://github.com/godotengine/godot-builds/releases/download/{{ godot_version }}/{{ godot_filename }}.zip" --output {{ cache_dir }}/{{ godot_filename }}.zip
    unzip -o {{ cache_dir }}/{{ godot_filename }}.zip -d {{ cache_dir }}
    cp {{ cache_dir }}/{{ godot_filename }} {{ godot_bin }}

# Check and download Godot if not already installed
[private]
@check-godot:
    [ ! -e {{ godot_bin }} ] && just install-godot || true

# Download Godot export templates
[private]
install-templates: makedirs
    curl -L --progress-bar -X GET "https://github.com/godotengine/godot-builds/releases/download/{{ godot_version }}/{{ godot_template }}" --output {{ cache_dir }}/{{ godot_template }}
    unzip -o {{ cache_dir }}/{{ godot_template }} -d {{ cache_dir }}
    mkdir -p {{ godot_templates_dir }}
    cp {{ cache_dir }}/templates/* {{ godot_templates_dir }}

# Check and download Godot export templates if not already installed
[private]
@check-templates:
    [ ! -d {{ godot_templates_dir }} ] && just install-templates || true

# === Python ===
#
# Recipes for working with Python and Python packages.
# These recipes ensure that Python packages are installed within a virtual environment,
# providing a clean and isolated environment.

export PIP_REQUIRE_VIRTUALENV := "true"

# Python virtualenv wrapper
[private]
@venv *ARGS:
    [ ! -d {{ venv_dir }} ] && python3 -m venv {{ venv_dir }} && touch {{ venv_dir }}/.gdignore || true
    . {{ venv_dir }}/bin/activate && {{ ARGS }}

# Run files formatters
fmt:
    just venv pip install pre-commit==3.*
    just venv pre-commit run -a

# === Godot ===
#
# Recipes for managing the Godot binary.
# These recipes simplify common tasks such as installing addons, importing game resources,
# and opening the Godot editor.

# Godot binary wrapper
godot *ARGS: check-godot check-templates
    {{ godot_bin }} {{ ARGS }}

# Import game resources
@import-resources:
    just godot --headless --import

# Open the Godot editor
@editor:
    just godot --editor

# === Export ===
#
# Recipes for exporting the game to different platforms.
# Handles tasks such as updating version information, preparing directories,
# and exporting the game for Windows, MacOS, Linux, and the web.

# Updates the addon version
@bump-version:
    echo "Update version in the plugin.cfg"
    sed -i "s,version=.*$,version=\"{{ addon_version }}\",g" ./addons/{{ addon_name }}/plugin.cfg

# === Clean ===
#
# Recipes for cleaning up the project, removing files and folders created by this Justfile.

# Remove game plugins
clean-addons:
    rm -rf .plugged
    [ -f plug.gd ] && (cd addons/ && git clean -f -X -d) || true

# Remove files created by Godot
clean-resources:
    rm -rf .godot

# Remove any unnecessary files
clean: clean-addons clean-resources

# === CI ===
#
# Recipes triggered by CI steps.
# Can be run locally but requires setup of environment variables.

# Add some variables to Github env
ci-load-dotenv:
    echo "godot_version={{ godot_version }}" >> $GITHUB_ENV
    echo "addon_name={{ addon_name }}" >> $GITHUB_ENV
    echo "addon_version={{ addon_version }}" >> $GITHUB_ENV

# Upload the addon on Github
publish:
    gh release create "{{ addon_version }}" --title="v{{ addon_version }}" --generate-notes
    # TODO: Add a asset-lib publish step
