# Raspberry Pi WiFi Checker

The Raspberry Pi is a great little single-board computer.  Sometimes however when we use it as a server for web pages or home control applications, it loses WiFi connectivity.  This command will install a script that will help to keep your WiFi running:

    curl -L wifi.brewpiremix.com | sudo bash

You'll see something like:

    pi@raspberrypi:~ $ curl -L wifi.brewpiremix.com | sudo bash
      % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                     Dload  Upload   Total   Spent    Left  Speed
    100   354  100   354    0     0   3510      0 --:--:-- --:--:-- --:--:--  3540
    100  6514  100  6514    0     0  25714      0 --:--:-- --:--:-- --:--:-- 25714
    
    ***Script doDaemon.sh starting.***
    
    Installing checkWiFi.sh script to /usr/local/bin.
      % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                     Dload  Upload   Total   Spent    Left  Speed
    100  8545  100  8545    0     0  39645      0 --:--:-- --:--:-- --:--:-- 39744
    
    Creating unit file for wificheck.
    Reloading systemd config.
    Enabling wificheck daemon.
    Created symlink /etc/systemd/system/multi-user.target.wants/wificheck.service → /etc/systemd/system/wificheck.service.
    Created symlink /etc/systemd/system/network.target.wants/wificheck.service → /etc/systemd/system/wificheck.service.
    Starting wificheck daemon.
    
    ***Script doDaemon.sh complete.***
    pi@raspberrypi:~ $

I've tested this on Stretch as well as Buster, but it should work on Wheezy as well (but you should really upgrade if you are on a system that's that old.)

After the new service is running, issue the command `sudo systemctl status wificheck` and you should see something like:

    ● wificheck.service - Service for: wificheck
       Loaded: loaded (/etc/systemd/system/wificheck.service; enabled; vendor preset
       Active: active (running) since Sat 2019-03-23 16:55:31 CDT; 6min ago
         Docs: https://github.com/lbussy/rpi-wifi-checker
     Main PID: 18482 (bash)
       CGroup: /system.slice/wificheck.service
               ├─18482 /bin/bash /usr/local/bin/checkWiFi.sh -d
               └─18508 sleep 600
    
    Mar 23 16:55:31 raspberrypi systemd[1]: Started Service for: wificheck.

As long as you see `Active: active (running)`, you're fine.

Those of you who have a Legacy BrewPi host that want to use this should ditch the wificheck in cron.d.  If you are running BrewPi Remix you already have something similar to this so no changes are needed.

This script will log to: `/var/log/wificheck.log`, and log any issues to `/var/log/wificheck.err`.  If your RPi is REALLY flaky and a reboot is the only way to fix network issues, edit `/usr/local/bin/checkWiFi.sh` and change line line 34 to read `REBOOT=true` and it will reboot your Pi if it can't resolve the issue by "normal" means.  If you make that edit you will need to restart the daemon by issuing the command `sudo systemctl restart wificheck`.
