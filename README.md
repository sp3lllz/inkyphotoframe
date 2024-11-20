# inkyphotoframe

This is my latest project to make a digital photo frame that is virtually indistinguishable from a real photo frame.
I have also written a script to pick a random number and use that to determine which photo to display you can have this refresh are whatever interval youd like with chrontab which I will detail how to do in the set up instructions.

## How to

### Heres what you will need for this project.

1. Any rasberry pi from pi 2b or newer including the pi zero or zero 2 will work but I recommend the pi 3b or zero W as a minimum for the built in wifi.
2. A MicroSD card the bigger the SD card the more photos you can have in your random pool.
3. The [Pimoroni 5.7" 7 color e-ink display.](https://shop.pimoroni.com/products/inky-impression-5-7) This should work with the [4"](https://shop.pimoroni.com/products/inky-impression-4) or [7.3"](https://shop.pimoroni.com/products/inky-impression-7-3) version as well but you would need to format your photos and make your frame to different dimentions from the later steps of this tutoral.
4. A frame to put the assembly in once you're finished, I'll get into the details on this later

### Setup of the electronics and code. 

1. Use the [rasberry pi imaging tool](https://www.raspberrypi.com/software/) to image your MicroSD card with Rasberry PiOS Lite and use the advanced options to enable SSH and add your wifi SSID
2. put the MicroSD card into the Pi and then attach it to the inky dispaly using the GPIO headers. If you have a Pi Zero W or Pi Zero W 2 you can attach the Pi directly to the board if youre using a B sized Pi use the standoffs and GPIO extention headers included with the display.
3. Boot the Pi up and connect using your SSH client of choice
4. Now its time to install the inkyphotoframe software, this can be done with a simple one line command `curl https://raw.githubusercontent.com/sp3lllz/inkyphotoframe/refs/heads/main/setup.sh | bash`. First this will runn Pimirionis setup if you have already run that you can skip this by chosing no at the yes no prompt. After that it will create the nessisary folder structure and download the scripts to the pi and finally create a timed crontab job to rotate the image every 30 minutes at the top of the hour and at half past the hour. At the end of the script it should update the photo frame with the following image ![inkytest.jpg](https://raw.githubusercontent.com/sp3lllz/inkyphotoframe/ebaf87d4ec4db4c45492eafdbb4082691fef1315/inkytest.jpg)
5. Now navigate to the following folder `/home/$USER/inkyframe/images/main` this is where you should place your images. For the best results images should be resize to 800*480 resolution but cropping to the same aspect ratio will usually serfice. Images should be renamed to be in the following format, `1.jpg` `2.jpg` `3.jpg` ect. all images should be in `.jpg` format.
6. Once you have renamed all your images to this format ensuring there are no gaps in the numbering run the runupdate.sh script like so `bash ranupdate.sh` and enter the highest number of the photo names. This will set the random number picker to only pick between 1 and the maximum number photo so that it can never select a photo that doesnt exist.
7. Setup is now complete! The photo should uptatically update as per the schedule. 

### The Frame

For the frame I wanted it to look inconspicous if placed next to a real photo frame, but i also wanted to hide the edges of the inky display so that only the the image was showing as if it was a photo print. Note the following mesurements only apply for the 5.7" version of the screen. 
To do this I decided to make a frame from scratch, I made my frame out of oak but no reason you cant make it out of any other kind of wood or even somthing else. I measured that the visable area of the screen is 115mm x 85mm so i made the inside apature of my frame to this dimention. I then cut a thin sheet of balsa wood to act as a mount/backplate at the apature of the mounting frame if you then line up the stand off locations from the inky frame to the backplate and drill some very small holes for the screws to go through. this will then keep the frame suspended in the display in the correct place.

If you're not into wood working I also created a 3D model of the frame and a backplate for holding the inky frame into the correct position. Please note though that i currently do not have a 3D printer to validate it so double checking the dimentions is reccomended before printing. 
