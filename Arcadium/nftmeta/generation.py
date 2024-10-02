from PIL import Image, ImageEnhance

# Load base images
treasure_img = Image.open("treasure.png")
sparkles_img = Image.open("sparkles.png")

# Ensure both images have the same size for composition
sparkles_img = sparkles_img.resize(treasure_img.size)

# Trial function to adjust sparkle opacity
def apply_sparkles(base_img, overlay_img, sparkle_opacity=1.0):
    # Adjust sparkle opacity (sparkle_opacity should be between 0.0 to 1.0)
    sparkle_layer = overlay_img.convert("RGBA")
    sparkle_layer.putalpha(int(sparkle_opacity * 255))  # Adjust alpha (transparency)
    
    # Composite the base and sparkle images together
    composite = Image.alpha_composite(base_img.convert("RGBA"), sparkle_layer)
    
    return composite

# Example usage
# Set sparkle opacity (range: 0.0 to 1.0)
sparkle_opacity_value = 0.5

# Create composite image
final_img = apply_sparkles(treasure_img, sparkles_img, sparkle_opacity=sparkle_opacity_value)

# Save the resulting image to a file
final_img.save("composite_image.png")

print("Composite image saved as composite_image.png")