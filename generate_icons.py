#!/usr/bin/env python3
from PIL import Image
import os

# Define the path to the source icon and output directory
import sys
base_dir = os.path.dirname(os.path.abspath(__file__))
source_icon = os.path.join(base_dir, "MeetingCopilot/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png")
output_dir = os.path.join(base_dir, "MeetingCopilot/Assets.xcassets/AppIcon.appiconset")

# Icon sizes needed (filename: pixel_size)
icons = {
    # iPhone
    "icon_20x20@2x.png": 40,
    "icon_20x20@3x.png": 60,
    "icon_29x29@2x.png": 58,
    "icon_29x29@3x.png": 87,
    "icon_40x40@2x.png": 80,
    "icon_40x40@3x.png": 120,
    "icon_60x60@2x.png": 120,
    "icon_60x60@3x.png": 180,
    # iPad
    "icon_20x20.png": 20,
    "icon_20x20@2x-ipad.png": 40,
    "icon_29x29.png": 29,
    "icon_29x29@2x-ipad.png": 58,
    "icon_40x40.png": 40,
    "icon_40x40@2x-ipad.png": 80,
    "icon_76x76.png": 76,
    "icon_76x76@2x.png": 152,
    "icon_83.5x83.5@2x.png": 167,
}

# Load the source image
print(f"Loading source icon: {source_icon}")
img = Image.open(source_icon)

# Generate all the icon sizes
for filename, size in icons.items():
    output_path = os.path.join(output_dir, filename)
    resized = img.resize((size, size), Image.Resampling.LANCZOS)
    resized.save(output_path, "PNG")
    print(f"Created {filename} ({size}x{size})")

print("\nAll icons generated successfully!")
