#!/usr/bin/env python3
from PIL import Image, ImageDraw, ImageFont
import os

# Output directory
output_dir = "MeetingCopilot/Assets.xcassets/AppIcon.appiconset"

# Create a 1024x1024 placeholder icon
size = 1024
img = Image.new('RGB', (size, size), color='#007AFF')  # iOS blue
draw = ImageDraw.Draw(img)

# Add "MC" text in the center
try:
    font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 400)
except:
    font = ImageFont.load_default()

text = "MC"
# Get text bounding box
bbox = draw.textbbox((0, 0), text, font=font)
text_width = bbox[2] - bbox[0]
text_height = bbox[3] - bbox[1]

# Center the text
x = (size - text_width) // 2 - bbox[0]
y = (size - text_height) // 2 - bbox[1]

draw.text((x, y), text, fill='white', font=font)

# Save the 1024x1024 source
source_path = os.path.join(output_dir, "icon_1024x1024.png")
img.save(source_path, "PNG")
print(f"Created source icon: {source_path}")

# Icon sizes needed (filename: pixel_size)
icons = {
    "icon_20x20@2x.png": 40,
    "icon_20x20@3x.png": 60,
    "icon_29x29@2x.png": 58,
    "icon_29x29@3x.png": 87,
    "icon_40x40@2x.png": 80,
    "icon_40x40@3x.png": 120,
    "icon_60x60@2x.png": 120,
    "icon_60x60@3x.png": 180,
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

# Generate all the icon sizes
for filename, icon_size in icons.items():
    output_path = os.path.join(output_dir, filename)
    resized = img.resize((icon_size, icon_size), Image.Resampling.LANCZOS)
    resized.save(output_path, "PNG")
    print(f"Created {filename} ({icon_size}x{icon_size})")

print("\nAll icons generated successfully!")
