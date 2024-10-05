# A quick flask application that serves rewardpool.html as index.

from flask import Flask, render_template, send_file
from PIL import Image, ImageEnhance
from io import BytesIO
import argparse

# Load base images
treasure_img = Image.open("assets/treasure.png").convert("RGBA")  # Ensure it's in RGBA mode
sparkles_img = Image.open("assets/sparkles.png").convert("RGBA")  # Ensure it's in RGBA mode

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

app = Flask(__name__)

@app.route('/')
def index():
    return app.send_static_file('rewardpool.html')

@app.route('/mancala')
def mancala():
    return app.send_static_file('mancala.html')

@app.route('/media')
def media():
    sparkle_opacity_value = 0.9
    final_img = apply_sparkles(treasure_img, sparkles_img, sparkle_opacity=sparkle_opacity_value)
    
    # Create an in-memory bytes buffer
    img_io = BytesIO()
    
    # Save the image to the buffer in PNG format
    final_img.save(img_io, 'PNG')
    
    # Seek to the beginning of the buffer to prepare for reading
    img_io.seek(0)

    # Use send_file to send the image from the buffer
    return send_file(img_io, mimetype='image/png')

if __name__ == '__main__':
    # Parse command line arguments, including debug mode, server port, etc.
    parser = argparse.ArgumentParser(description='Arcadium Server')
    parser.add_argument('--debug', action='store_true', help='Enable debug mode')
    parser.add_argument('--port', type=int, default=80, help='Port number')
    args = parser.parse_args()

    # Run the Flask app
    app.run(debug=args.debug, port=args.port)