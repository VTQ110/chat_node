#!/bin/bash
# Launches the app in a booted Simulator in screenshot (demo) mode and captures each scene.
# Usage: scripts/take-screenshots.sh <simulator-udid> [output-dir]
set -euo pipefail

UDID=$1
OUT=${2:-Screenshots}
BUNDLE=com.example.CompositionCamera
mkdir -p "$OUT"

shot() {
    local name=$1
    shift
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
    xcrun simctl launch "$UDID" "$BUNDLE" "$@" > /dev/null
    sleep 4
    xcrun simctl io "$UDID" screenshot "$OUT/$name.png"
    echo "captured $name"
}

# Real first launch: the camera permission prompt.
xcrun simctl privacy "$UDID" reset camera "$BUNDLE" 2>/dev/null || true
shot 01-quyen-camera

D="-demo YES"
shot 02-man-hinh-chinh    $D -demoImage landscape -demoGuide ruleOfThirds -demoSmart NO
shot 03-meo-bo-cuc        $D -demoImage landscape -demoGuide ruleOfThirds -demoSmart NO -demoTip YES
shot 04-ti-le-vang        $D -demoImage landscape -demoGuide goldenRatio -demoSmart NO
shot 05-xoan-oc           $D -demoImage landscape -demoGuide goldenSpiral -demoSmart NO
shot 06-xoan-oc-xoay      $D -demoImage landscape -demoGuide goldenSpiral -demoVariant 1 -demoSmart NO
shot 07-tam-giac          $D -demoImage landscape -demoGuide goldenTriangle -demoSmart NO
shot 08-duong-cheo        $D -demoImage landscape -demoGuide diagonals -demoSmart NO
shot 09-doi-xung          $D -demoImage landscape -demoGuide symmetry -demoSmart NO
shot 10-goi-y-chua-dat    $D -demoImage kayak -demoGuide ruleOfThirds -demoZoom 1.6
shot 11-goi-y-dat         $D -demoImage kayak -demoGuide ruleOfThirds -demoZoom 1.6 -demoAlign YES
shot 12-khuon-mat         $D -demoImage portrait -demoGuide ruleOfThirds -demoZoom 1.4
shot 13-khuon-mat-dat     $D -demoImage portrait -demoGuide ruleOfThirds -demoZoom 1.4 -demoAlign YES
shot 14-lui-ra-xa         $D -demoImage portrait -demoGuide ruleOfThirds -demoZoom 2.6
shot 15-can-bang-nghieng  $D -demoImage landscape -demoGuide ruleOfThirds -demoSmart NO -demoRoll 7
shot 16-can-bang-dat      $D -demoImage landscape -demoGuide ruleOfThirds -demoSmart NO -demoRoll 0.3
shot 17-da-chup           $D -demoImage kayak -demoGuide ruleOfThirds -demoZoom 1.6 -demoAlign YES -demoThumbnail YES -demoToast "Đã lưu vào thư viện Ảnh"
shot 18-tu-choi-quyen     $D -demoStatus unauthorized
