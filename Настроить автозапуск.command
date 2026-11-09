#!/bin/zsh
cd -- "$(dirname "$0")" || exit 1
exec /bin/zsh './Установить.command' --configure-only
