## Serial Console

### Serial Device
Some text says ttyAMA0 would be the serial port on pins 8 and 10 on the pi, however bluetooth on pi3+ used ttyAMA0, and instead serial was moved to ttyS0 unless bluetooth was disabled in boot config `dtoverlay=pi3-disable-bt`.  Ubuntu (20 and 18?) can use serial0 which will pick the right device for you.  

### Kernel Config
Usually with serial console, two entries exist in the kernel command line for "console".  One for serial console with a baud rate, e.g.: `console=serial0,115200`.  Also the console still should go to the normal display device so another entry is for tty1.

### USB 
I paid $11 for 3 pack of EVISWIY PL2303TA USB to TTL Serial Cable, seems to work fine.  the serial port shows up as `/dev/ttyUSB0`.

### Client

(Picocom)[https://github.com/npat-efault/picocom] works well.

To collect the terminal current height and width and then run picocom assuming USB to serial port adapter.

```
tput cols
tput lines
sudo picocom -b 115200 /dev/ttyUSB0
```

Set the terminal height and width with the values collected above
```
stty rows 24 cols 80
```

Exit session with `Ctrl-a Ctrl-x`
