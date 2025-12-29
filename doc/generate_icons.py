#!/usr/bin/env python3
from PIL import Image, ImageDraw, ImageChops
import os

def create_icon_with_padding(input_path, output_path, size, padding_percent=10, corner_radius_percent=0):
    """
    Create icon with transparent padding and rounded corners
    corner_radius_percent: corner radius as percentage of the icon size
    """
    # Open original image
    img = Image.open(input_path).convert("RGBA")
    
    # Calculate inner size (after removing padding)
    inner_size = int(size * (1 - padding_percent / 100))
    
    # Resize image to inner size
    img_resized = img.resize((inner_size, inner_size), Image.Resampling.LANCZOS)
    
    # Apply rounded corners if specified
    if corner_radius_percent > 0:
        radius = int(inner_size * corner_radius_percent / 100)
        radius = max(1, radius)
        mask = Image.new("L", (inner_size, inner_size), 0)
        draw = ImageDraw.Draw(mask)
        draw.rounded_rectangle(
            [(0, 0), (inner_size - 1, inner_size - 1)],
            radius=radius,
            fill=255
        )
        img_resized.putalpha(ImageChops.multiply(img_resized.getchannel("A"), mask))
    
    # Create new image with transparent background
    new_img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    
    # Calculate position to center the resized image
    pos = (size - inner_size) // 2
    
    # Paste resized image onto the center
    new_img.paste(img_resized, (pos, pos), img_resized)
    
    # Save
    new_img.save(output_path, "PNG")
    print(f"Created: {output_path} ({size}x{size})")

def main():
    # Paths
    input_icon = "doc/icon.png"
    appicon_dir = "MonkeyNote/Assets.xcassets/AppIcon.appiconset"
    
    # Icon sizes for macOS
    icon_sizes = [16, 32, 128, 256, 512]
    padding = 15
    corner_radius_percent = 20  # 6.25% of the icon size
    
    for size in icon_sizes:
        # 1x version
        output_path_1x = os.path.join(appicon_dir, f"icon_{size}x{size}.png")
        create_icon_with_padding(input_icon, output_path_1x, size, padding, corner_radius_percent)
        
        # 2x version
        output_path_2x = os.path.join(appicon_dir, f"icon_{size}x{size}@2x.png")
        create_icon_with_padding(input_icon, output_path_2x, size * 2, padding, corner_radius_percent)
    
    print(f"\nDone! All icons generated with {padding}% transparent padding and {corner_radius_percent}% corner radius.")

if __name__ == "__main__":
    main()