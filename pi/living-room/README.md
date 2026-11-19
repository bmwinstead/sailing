# Living room display image

This directory defines a Raspberry Pi OS image for the living room display.

- Device: Raspberry Pi 4B.
- Screen: Dell P2424HT, 1920x1080, touch over USB.
- Software: the labwc desktop and the [touchkio](https://github.com/leukipp/touchkio) kiosk app.
- Page: `https://home-assistant.winstead.io/living-room`.

[rpi-image-gen](https://github.com/raspberrypi/rpi-image-gen) builds the image.
The GitHub Actions workflow `.github/workflows/living-room-image.yaml` runs the build.

## What is in the image

| Item | Value |
|------|-------|
| OS | Raspberry Pi OS Trixie, arm64 |
| Desktop | labwc, with automatic login for `bmw` |
| Host name | `living-room` |
| User | `bmw`, no password, SSH keys only, `sudo` without password |
| Network | Ethernet with DHCP. NetworkManager runs it. |
| Packages | `touchkio`, `swayidle`, `wlopm`, `ddcutil`, `openssh-server` |
| touchkio service | systemd user service, enabled |
| Screen blanking | None. Home Assistant sleeps and wakes the screen over MQTT. |
| Screen mode | 1920x1080, landscape, set at login |

The image has no secret.
The MQTT broker at `10.20.0.7` accepts anonymous clients, so touchkio has no user name and no password.
touchkio connects to the broker without credentials when `mqtt_user` and `mqtt_password` are empty.
The check is in `js/integration.js` of touchkio 1.6.0.

## Files

| File | Use |
|------|-----|
| `config/living-room.yaml` | Image settings. The touchkio version and checksum, the page URL and the broker URL are here. |
| `layer/living-room-kiosk.yaml` | Packages for the kiosk. |
| `layer/living-room-kiosk.d/hooks/` | Build steps. They install touchkio and write the files for user `bmw`. |
| `layer/living-room-kiosk.d/home/` | Files for the home of `bmw`. The labwc autostart is here. |
| `layer/living-room-kiosk.d/customize.overlay/` | Files for the root file system. The touchkio unit and the Wi-Fi import service are here. |

## Build the image

### Before the first build

1. Open the repository settings on GitHub.
2. Go to **Secrets and variables**, then **Actions**, then **Variables**.
3. Add the variable `LIVING_ROOM_SSH_PUBKEY`.
4. Set the value to your SSH public key, for example the content of `~/.ssh/id_ed25519.pub`.

A public key is not secret, so this is a variable and not a secret.
The build stops if the variable is empty. The image has no password, so it must have a key.

### Build with GitHub Actions

1. Open the **Actions** tab.
2. Select **Build living room image**.
3. Select **Run workflow**.

The workflow also runs on each push to `main` that changes `pi/living-room/**`.
The build runs on an `ubuntu-24.04-arm` runner and takes a long time.

The workflow does these steps:

1. It builds the image with rpi-image-gen.
2. It compresses the image to `living-room.img.xz`.
3. It uploads the image and `living-room.img.xz.sha256` as a workflow artifact.
4. It attaches the same files to a GitHub release with the tag `living-room-image-<run number>`.

A GitHub release file can be 2 GiB at most.
If the compressed image is larger, the release step fails. The artifact is still there.

### Build on your own computer

Use an arm64 machine with Debian or Ubuntu.

```bash
git clone https://github.com/raspberrypi/rpi-image-gen.git
cd rpi-image-gen
git checkout v2.9.0
sudo ./install_deps.sh
./rpi-image-gen build \
  -S /path/to/sailing/pi/living-room \
  -c living-room.yaml \
  -- IGconf_ssh_pubkey_user1=/path/to/authorized_keys
```

The image is in `work/` in the current directory.

## Flash the image

1. Download `living-room.img.xz` from the release or the workflow artifact.
2. Check the file: `sha256sum -c living-room.img.xz.sha256`.
3. Open Raspberry Pi Imager.
4. For **Choose device**, select **Raspberry Pi 4**.
5. For **Choose OS**, select **Use custom**, then select `living-room.img.xz`.
6. Select the SD card.
7. If Imager offers OS customisation, do not use it. This image does not read the Imager settings. Use the Wi-Fi steps below.
8. Write the card.

## Wi-Fi

The image has no Wi-Fi credentials. Ethernet with DHCP works with no setup.

To use Wi-Fi, put a NetworkManager file on the boot partition:

1. After you write the card, remove it and put it in your computer again.
2. Open the partition named `BOOT`.
3. Create the file `wifi.nmconnection` with this content:

```ini
[connection]
id=home
type=wifi
autoconnect=true

[wifi]
ssid=YOUR_NETWORK_NAME
mode=infrastructure

[wifi-security]
key-mgmt=wpa-psk
psk=YOUR_PASSWORD

[ipv4]
method=auto

[ipv6]
method=auto
```

At boot, the service `living-room-wifi` moves the file to `/etc/NetworkManager/system-connections/`.
It sets the owner to `root` and the mode to `0600`. Then it deletes the copy on the boot partition.

If the router needs a Wi-Fi country, set `ieee80211.regdom` in `config/living-room.yaml` and build again.

## First boot checklist

Do these steps in order.

1. Connect the Ethernet cable, the HDMI cable and the USB-B cable for touch. Then power on the Pi.
2. Wait for the desktop. The Home Assistant page must appear in full screen.
3. If the page shows the Home Assistant login, log in with the touch screen. touchkio keeps the login in `~/.config/touchkio/`.
4. Find the IP address of the Pi in the router. The host name is `living-room`.
5. Log in: `ssh bmw@<ip address>`.
6. Check the service: `systemctl --user status touchkio.service`.
7. In Home Assistant, open **Settings**, **Devices & services**, **MQTT**. A new device must appear.
   - The device name starts with `TouchKio` and has the host name `Living-room`.
   - The id is `rpi_` and the last six characters of the Pi serial number.
   - The device has a display switch, a kiosk status, a keyboard switch, a page selector, a zoom control and sensors for CPU, memory and temperature.
   - It also has buttons for refresh, reboot and shutdown.
8. Turn the display switch off and on. The screen must go dark and wake again.
9. Touch the screen. The touch must hit the point you press.

## DNS

The Pi must resolve `home-assistant.winstead.io` through the home DNS forwarder.
The forwarder must send the domain `winstead.io` to `10.20.0.4`, the k8s-gateway.
Give the Pi the home DNS server in DHCP. Do not use a public DNS server on the Pi.

Check from the Pi: `getent hosts home-assistant.winstead.io`. The result must be `10.20.0.3`, the internal gateway.

## Update touchkio

Renovate reads the comment above `touchkio_version` in `config/living-room.yaml` and opens a pull request for new releases.
Renovate does not change the checksum.
Take the checksum of the new `.deb` file from the touchkio release page and put it in `touchkio_sha256`.
The build stops if the checksum is wrong.

## Known limits

- The image is not bit-for-bit reproducible. The Debian and Raspberry Pi packages are the latest at build time.
- The root partition is 5 GiB and does not grow at first boot.
- `ddcutil` is installed. The user can use `sudo` without a password, so touchkio can use `ddcutil` for display power and brightness when the monitor supports it. If sleep or wake misbehaves, run `sudo ddcutil capabilities` and check the monitor.
- The cursor is hidden with a transparent cursor theme. A touch screen does not show a cursor, so this only matters if a mouse is connected.
