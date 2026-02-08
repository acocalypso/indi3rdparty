#!/bin/bash
# Remove set -e so we continue even if some packages fail
# set -e 

# Configuration
REPO_ROOT=$(pwd)
REPO_DIR="${REPO_ROOT}/dist"
DEBS_DIR="${REPO_ROOT}/all_debs"

mkdir -p "$REPO_DIR" "$DEBS_DIR"

FAILED_PACKAGES=""

# Ensure we are in the root of the repo (where make_deb_pkgs usually is)
if [ ! -f "./make_deb_pkgs" ]; then
    echo "Error: ./make_deb_pkgs not found. Make sure you run this script from the root of the indi-3rdparty repository."
    exit 1
fi

chmod +x ./make_deb_pkgs

# Install basic build requirements if missing (checks for debuild/rules)
if ! command -v dpkg-scanpackages &> /dev/null; then
    echo "Installing missing tools..."
    apt-get update && apt-get install -y dpkg-dev
fi

# Define libs first (dependency order matters)
LIBS="libasi libapogee libartocad libbig5 libcdcl libdcdcam libdfish libdmk libdsi libeg libep libfli libflycapture libfocuslight libftdi libgen_tcp libgphoto libgreychen libguider libioptron libmallincam libplayerone libqhy libqsi librtk libsbig libsexasdome libshelyak libsidereal libsiril libskywatcher libstarvigil libsvb libswab libsynscan libtic libtoupcam libunifiedtelemetry libvaonis libvedet libzwo"

# Find all indi-* drivers, excluding existing build dirs
DRIVERS=$(find . -maxdepth 1 -type d -name "indi-*" -not -path "./deb_*" -not -name "indi-3rdparty" | sed 's|./||' | sort)

echo "========================================"
echo "Starting Build Process"
echo "Target Repo Dir: $REPO_DIR"
echo "========================================"

build_and_collect() {
    local target=$1
    local type=$2
    
    if [ -d "$target" ]; then
        echo ">>> Building $type: $target..."
        
        # Run the build, allow failure
        set +e
        ./make_deb_pkgs "$target"
        local build_status=$?
        set -e
        
        if [ $build_status -ne 0 ]; then
            echo "Error: Build failed for $target (Exit Code: $build_status)"
            FAILED_PACKAGES="$FAILED_PACKAGES $target"
            return
        fi
        
        # Check if build succeeded and copy debs
        if [ -d "deb_$target" ]; then
            count=$(find "deb_$target" -name "*.deb" | wc -l)
            if [ "$count" -gt 0 ]; then
                echo "    Found $count .deb files for $target"
                cp "deb_$target"/*.deb "$DEBS_DIR/"
                
                # Install lib debs immediately so subsequent drivers can link against them
                if [ "$type" == "Lib" ]; then
                     echo "    Installing $target packages to satisfy dependencies..."
                     dpkg -i "deb_$target"/*.deb || echo "Warning: Failed to install $target, subsequent builds might fail."
                fi
            else
                echo "Warning: No .deb files created for $target"
                FAILED_PACKAGES="$FAILED_PACKAGES $target(no-debs)"
            fi
        else
             echo "Error: Build directory deb_$target was not created."
             FAILED_PACKAGES="$FAILED_PACKAGES $target(no-dir)"
        fi
    else
        echo "Warning: Directory $target not found."
    fi
}

echo "Building libraries..."
for lib in $LIBS; do
    build_and_collect "$lib" "Lib"
done

echo "Building drivers..."
for drv in $DRIVERS; do
    build_and_collect "$drv" "Driver"
done

echo "========================================"
echo "Copying all .deb to repository..."
# Check if there are any debs to copy
if ls "$DEBS_DIR"/*.deb 1> /dev/null 2>&1; then
    cp "$DEBS_DIR"/*.deb "$REPO_DIR/"
    echo "Total debs: $(ls -1 "$REPO_DIR"/*.deb | wc -l)"

    echo "Generating repo index..."
    cd "$REPO_DIR"
    dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz
else
    echo "No .deb files found to process."
fi

echo "========================================"
echo "Build Complete with issues."
if [ -n "$FAILED_PACKAGES" ]; then
    echo "Failed Packages:"
    echo "$FAILED_PACKAGES"
else
    echo "All packages built successfully."
fi
echo "Files are in $REPO_DIR"
