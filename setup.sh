#!/bin/bash
# Clone the repository
git clone https://github.com/sp3lllz/inkyphotoframe.git /tmp/inkyphotoframe
# Move the required file
mv /tmp/inkyphotoframe/ranphoto.py /home/spell/ranphoto.py
# Set permissions for ranphoto.py
chmod +x /home/spell/ranphoto.py
# Copy image.py
cp /home/spell/Pimoroni/inky/examples/7color/image.py /home/spell/image.py
# Cleanup
rm -rf /tmp/inkyphotoframe
