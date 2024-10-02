from PIL import Image, ImageEnhance

# Load base images
treasure_img = Image.open("treasure.png").convert("RGBA")  # Ensure it's in RGBA mode
sparkles_img = Image.open("sparkles.png").convert("RGBA")  # Ensure it's in RGBA mode

# Ensure both images have the same size for composition
sparkles_img = sparkles_img.resize(treasure_img.size)

# Trial function to adjust sparkle opacity
def apply_sparkles(base_img, overlay_img, sparkle_opacity=1.0):
    # Adjust sparkle opacity (sparkle_opacity should be between 0.0 to 1.0)
    sparkle_layer = overlay_img.copy()  # Copy the overlay image to avoid modifying the original
    # Get the alpha channel of the sparkle image (transparency)
    alpha = sparkle_layer.split()[3]
    alpha = ImageEnhance.Brightness(alpha).enhance(sparkle_opacity)  # Adjust brightness to simulate opacity
    sparkle_layer.putalpha(alpha)

    # Composite the base and sparkle images together
    composite = Image.alpha_composite(base_img, sparkle_layer)

    return composite

# Example usage
# Set sparkle opacity (range: 0.0 to 1.0)
sparkle_opacity_value = 0.9

# Create composite image
final_img = apply_sparkles(treasure_img, sparkles_img, sparkle_opacity=sparkle_opacity_value)

# Save the resulting image to a file
final_img.save("composite_image.png")

print("Composite image saved as composite_image.png")
