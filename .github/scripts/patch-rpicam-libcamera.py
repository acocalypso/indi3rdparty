#!/usr/bin/env python3
"""Adapt pinned rpicam-apps to controls provided by the installed libcamera."""
import pathlib
import shlex
import subprocess
import sys

source = pathlib.Path(sys.argv[1])
flags = shlex.split(subprocess.check_output(
    ["pkg-config", "--cflags", "libcamera"], text=True
))


def has_control(name):
    probe = f"#include <libcamera/control_ids.h>\nint main() {{ (void)libcamera::controls::{name}; }}\n"
    return subprocess.run(
        ["c++", "-std=c++17", *flags, "-x", "c++", "-fsyntax-only", "-"],
        input=probe, text=True, capture_output=True,
    ).returncode == 0


def replace_once(path, old, new):
    text = path.read_text()
    if text.count(old) != 1:
        raise RuntimeError(f"Pinned rpicam source changed: {path}: {old}")
    path.write_text(text.replace(old, new))


if not has_control("AeState"):
    if not has_control("draft::AeState"):
        raise RuntimeError("libcamera exposes neither AeState nor draft::AeState")
    header = source / "core/frame_info.hpp"
    replace_once(header, "controls::AeState);", "controls::draft::AeState);")
    replace_once(header, "controls::AeStateConverged;", "controls::draft::AeStateConverged;")
    print("Using libcamera's draft auto-exposure state controls")

for control in ("ExposureTimeMode", "AnalogueGainMode"):
    if not has_control(control):
        # Older libcamera selects manual exposure/gain directly from the
        # ExposureTime/AnalogueGain value; separate mode controls came later.
        replace_once(
            source / "core/rpicam_app.cpp",
            f"\t\tcontrols_.set(controls::{control}, controls::{control}Manual);\n",
            "",
        )
        print(f"Using legacy libcamera manual controls without {control}")

if not has_control("rpi::ScalerCrops"):
    implementation = source / "core/rpicam_app.cpp"
    replace_once(
        implementation,
        "!controls_.get(controls::ScalerCrop) && !controls_.get(controls::rpi::ScalerCrops)",
        "!controls_.get(controls::ScalerCrop)",
    )
    replace_once(
        implementation,
        "\t\tif (options_->GetPlatform() == Platform::VC4)\n"
        "\t\t\tcontrols_.set(controls::ScalerCrop, crops[0]);\n"
        "\t\telse\n"
        "\t\t\tcontrols_.set(controls::rpi::ScalerCrops, libcamera::Span<const Rectangle>(crops.data(), crops.size()));",
        "\t\tcontrols_.set(controls::ScalerCrop, crops[0]);",
    )
    print("Using standard ScalerCrop without Raspberry Pi multi-stream controls")

encoder = source / "core/rpicam_encoder.hpp"
if not has_control("FrameWallClock"):
    replace_once(
        encoder,
        "\t\tauto ts = completed_request->metadata.get(controls::FrameWallClock);\n"
        "\t\tint64_t timestamp_us = ts ? *ts : buffer->metadata().timestamp / 1000;",
        "\t\tint64_t timestamp_us = buffer->metadata().timestamp / 1000;",
    )
    print("Using frame buffer timestamps without FrameWallClock")

# This is an installed inline header. Consumers do not inherit the Meson
# DISABLE_RPI_FEATURES compiler flag used to build the library itself.
if not has_control("rpi::SyncMode") or not has_control("rpi::SyncReady"):
    text = encoder.read_text()
    if text.count("#ifndef DISABLE_RPI_FEATURES") != 2:
        raise RuntimeError("Pinned rpicam encoder synchronisation guards changed")
    encoder.write_text(text.replace(
        "#ifndef DISABLE_RPI_FEATURES",
        "#if 0 // Camera synchronisation controls are unavailable in this libcamera",
    ))
    print("Disabling unsupported camera synchronisation in the public encoder header")
