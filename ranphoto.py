#!/usr/bin/env python3
import random
import os
import signal
import datetime
import requests
import subprocess
import RPi.GPIO as GPIO
import sys
from PIL import Image
from inky.auto import auto
# Generate the random numer
randnum = str(random.randint(1,77))
# print the number generated
print("The Number is: {}".format(randnum))
# set the variable for the photo path
image_file = "images/main/{}.jpg".format(randnum)
# run the image.py script to display the chosen image on the screen
os.system("python image.py --file " + image_file)
