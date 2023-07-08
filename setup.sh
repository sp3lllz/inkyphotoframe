#!/bin/bash
curl https://get.pimoroni.com/inky | bash
curl -o /home/spell/ranphoto.py https://raw.githubusercontent.com/sp3lllz/inkyphotoframe/main/ranphoto.py 
cp /home/spell/Pimoroni/inky/examples/7color/image.py /home/spell/image.py
chmod +x ranphoto.py