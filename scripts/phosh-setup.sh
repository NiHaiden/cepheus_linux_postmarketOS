#!/bin/sh
# cli-setup.sh + Phosh as the boot UI (greetd + phrog greeter; Plasma stays selectable if installed).
exec "$(dirname "$0")/cli-setup.sh" phosh
