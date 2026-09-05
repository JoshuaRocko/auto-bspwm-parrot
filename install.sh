#!/bin/bash
#
# auto-bspwm-parrot — adaptado para Parrot Security 7.3 (Debian 13 "trixie")
#
# Cambios respecto al original:
#   - Sin compilación desde fuente (polybar, picom y nvim ya están en apt)
#   - Sin Python 2.7.18 ni pip2
#   - Sin apt-key (retirado en Debian 13)
#   - Sin manipulación de /etc/apt/sources.list
#   - Sin `rm -rf $ruta` al final
#   - wmname -> suckless-tools ; neofetch -> fastfetch
#   - VS Code desde el repo oficial de Microsoft
#   - Picom NO se instala ni se autoarranca (ver NOTA_PICOM abajo)
#   - Reanudable: cada etapa se marca al completarse
#   - Respalda la configuración existente antes de sobrescribir
#
# Uso:
#   ./install.sh              instalación normal
#   ./install.sh --dry-run    solo muestra lo que haría
#   ./install.sh --reset      olvida el progreso y empieza de cero
#
# NOTA_PICOM: esta VM no tiene aceleración 3D (Mesa usa llvmpipe). Picom es un
# compositor con blur y transparencias; cada frame lo dibujaría la CPU. Por eso
# se omite y se comenta su invocación en bspwmrc. Si algún día hay virgl:
#   sudo apt install picom  &&  descomentar la línea en ~/.config/bspwm/bspwmrc
# Ojo: el picom.conf del repo es para el fork de ibhagwan y probablemente no
# parsee con picom 12 de apt.

set -uo pipefail

# ---------------------------------------------------------------- colores ---
G="\e[0;32m\033[1m"; R="\e[0;31m\033[1m"; B="\e[0;34m\033[1m"
Y="\e[0;33m\033[1m"; E="\033[0m\e[0m"

info()  { echo -e "\n${B}[*]${E} $*"; }
ok()    { echo -e "${G}[+]${E} $*"; }
warn()  { echo -e "${Y}[!]${E} $*"; }
err()   { echo -e "${R}[-]${E} $*"; }

trap 'echo -e "\n\n${R}[!] Interrumpido.${E}\n"; exit 130' INT

# ------------------------------------------------------------ validaciones ---
if [ "$(id -u)" -eq 0 ]; then
    err "No ejecutes este script como root. Úsalo con tu usuario normal."
    exit 1
fi

RUTA="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="${HOME}/.cache/auto-bspwm-state"
BACKUP="${HOME}/.config-backup-$(date +%Y%m%d-%H%M%S)"
DRY=0

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY=1 ;;
        --reset)   rm -f "$STATE"; ok "Progreso reiniciado." ;;
        -h|--help) sed -n '3,30p' "$0"; exit 0 ;;
        *) err "Argumento desconocido: $arg"; exit 1 ;;
    esac
done

mkdir -p "$(dirname "$STATE")"; touch "$STATE"

# Verifica que estamos donde creemos
if [ ! -d "${RUTA}/Config" ]; then
    err "No encuentro ${RUTA}/Config — ¿estás ejecutando desde la raíz del repo?"
    exit 1
fi

# Comprobación de base del sistema (aviso, no bloqueo)
if ! grep -qi 'parrot' /etc/os-release 2>/dev/null; then
    warn "Este script está pensado para Parrot OS. Continúo de todos modos."
fi

# --------------------------------------------------------------- utilidades ---
run() {
    if [ "$DRY" -eq 1 ]; then
        echo -e "   ${Y}dry-run:${E} $*"
        return 0
    fi
    "$@"
}

done_step()  { grep -qxF "$1" "$STATE"; }
mark_step()  { [ "$DRY" -eq 0 ] && echo "$1" >> "$STATE"; return 0; }

# Instala solo los paquetes que existen en los repos; reporta los que no.
apt_install() {
    local disponibles=() faltantes=() p
    for p in "$@"; do
        if apt-cache show "$p" >/dev/null 2>&1; then
            disponibles+=("$p")
        else
            faltantes+=("$p")
        fi
    done

    if [ "${#faltantes[@]}" -gt 0 ]; then
        warn "No existen en los repos y se omiten: ${faltantes[*]}"
    fi

    if [ "${#disponibles[@]}" -eq 0 ]; then
        warn "Nada que instalar en este grupo."
        return 0
    fi

    run sudo apt install -y "${disponibles[@]}"
}

backup_if_exists() {
    local target="$1"
    [ -e "$target" ] || return 0
    run mkdir -p "$BACKUP"
    run cp -a "$target" "$BACKUP/" 2>/dev/null
}

# ================================================================== etapas ===

# --- 1. Actualización del sistema -------------------------------------------
if done_step "update"; then
    ok "Sistema ya actualizado en una corrida previa, salto."
else
    info "Actualizando el sistema (esto tarda)..."
    run sudo apt update
    if command -v parrot-upgrade >/dev/null 2>&1; then
        run sudo parrot-upgrade
    else
        warn "parrot-upgrade no existe; uso apt full-upgrade."
        run sudo apt full-upgrade -y
    fi
    mark_step "update"
    ok "Sistema actualizado."
fi

# --- 2. Paquetes del entorno -------------------------------------------------
if done_step "paquetes"; then
    ok "Paquetes ya instalados, salto."
else
    info "Instalando el entorno bspwm y utilidades..."
    apt_install \
        bspwm sxhkd polybar rofi kitty feh \
        zsh zsh-syntax-highlighting zsh-autosuggestions zsh-autocomplete \
        xclip scrot scrub imagemagick ranger fzf bat lsd neovim \
        numlockx suckless-tools fastfetch acpi locate \
        build-essential git vim curl wget \
        i3lock x11-xserver-utils

    # pwntools: Debian 13 protege el Python del sistema (PEP 668).
    info "Instalando pwntools..."
    if command -v pipx >/dev/null 2>&1 || apt-cache show pipx >/dev/null 2>&1; then
        run sudo apt install -y pipx
        run pipx install pwntools
        run pipx ensurepath
    else
        run sudo pip3 install pwntools --break-system-packages
    fi

    mark_step "paquetes"
    ok "Paquetes instalados."
fi

# --- 3. Visual Studio Code (repo oficial) ------------------------------------
if done_step "vscode"; then
    ok "VS Code ya instalado, salto."
else
    info "Instalando Visual Studio Code desde el repo oficial de Microsoft..."
    run sudo install -d -m 0755 /etc/apt/keyrings
    if [ "$DRY" -eq 0 ]; then
        wget -qO- https://packages.microsoft.com/keys/microsoft.asc \
            | gpg --dearmor \
            | sudo tee /etc/apt/keyrings/packages.microsoft.gpg >/dev/null
        echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
            | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
    else
        echo -e "   ${Y}dry-run:${E} añadir keyring y repo de Microsoft"
    fi
    run sudo apt update
    run sudo apt install -y code
    mark_step "vscode"
    ok "VS Code instalado."
fi

# --- 4. Repos externos (nvim config, p10k, i3lock-fancy) ---------------------
if done_step "repos"; then
    ok "Repos externos ya clonados, salto."
else
    info "Clonando configuraciones externas..."
    run mkdir -p "${HOME}/github"

    # NvChad starter
    if [ ! -d "${HOME}/.config/nvim" ]; then
        run git clone https://github.com/NvChad/starter "${HOME}/.config/nvim"
    else
        warn "~/.config/nvim ya existe, no lo toco."
    fi

    # powerlevel10k
    if [ ! -d "${HOME}/.powerlevel10k" ]; then
        run git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
            "${HOME}/.powerlevel10k"
    fi
    if [ "$DRY" -eq 0 ] && ! sudo test -d /root/.powerlevel10k; then
        run sudo git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
            /root/.powerlevel10k
    fi

    # i3lock-fancy: preferir apt, si no está compilar
    if apt-cache show i3lock-fancy >/dev/null 2>&1; then
        run sudo apt install -y i3lock-fancy
    else
        warn "i3lock-fancy no está en apt, lo instalo desde git."
        if [ ! -d "${HOME}/github/i3lock-fancy" ]; then
            run git clone https://github.com/meskarune/i3lock-fancy.git \
                "${HOME}/github/i3lock-fancy"
        fi
        run bash -c "cd '${HOME}/github/i3lock-fancy' && sudo make install"
    fi

    # plugin sudo de oh-my-zsh
    if [ "$DRY" -eq 0 ] && [ ! -f /usr/share/zsh-sudo/sudo.plugin.zsh ]; then
        sudo mkdir -p /usr/share/zsh-sudo
        sudo wget -q -O /usr/share/zsh-sudo/sudo.plugin.zsh \
            https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/plugins/sudo/sudo.plugin.zsh
    fi

    mark_step "repos"
    ok "Repos externos listos."
fi

# --- 5. Fuentes ---------------------------------------------------------------
if done_step "fuentes"; then
    ok "Fuentes ya instaladas, salto."
else
    info "Instalando fuentes..."
    run sudo mkdir -p /usr/local/share/fonts /usr/share/fonts/truetype
    [ -d "${RUTA}/fonts/HNF" ] && \
        run sudo cp -v "${RUTA}"/fonts/HNF/* /usr/local/share/fonts/
    [ -d "${RUTA}/Config/polybar/fonts" ] && \
        run sudo cp -v "${RUTA}"/Config/polybar/fonts/* /usr/share/fonts/truetype/
    run sudo fc-cache -f
    mark_step "fuentes"
    ok "Fuentes instaladas."
fi

# --- 6. Configuración ---------------------------------------------------------
if done_step "config"; then
    ok "Configuración ya copiada, salto."
else
    info "Respaldando configuración existente en ${BACKUP}..."
    backup_if_exists "${HOME}/.zshrc"
    backup_if_exists "${HOME}/.config/bspwm"
    backup_if_exists "${HOME}/.config/sxhkd"
    backup_if_exists "${HOME}/.config/polybar"
    backup_if_exists "${HOME}/.config/kitty"

    info "Copiando configuración..."
    run mkdir -p "${HOME}/.config"
    run cp -rv "${RUTA}"/Config/* "${HOME}/.config/"
    run sudo mkdir -p /root/.config
    run sudo cp -rv "${RUTA}"/Config/* /root/.config/
    [ -d "${RUTA}/kitty" ] && run sudo cp -rv "${RUTA}/kitty" /opt/

    # Tema Nord de rofi
    run mkdir -p "${HOME}/.config/rofi/themes"
    [ -f "${RUTA}/rofi/nord.rasi" ] && \
        run cp -v "${RUTA}/rofi/nord.rasi" "${HOME}/.config/rofi/themes/"

    # zsh + powerlevel10k
    run cp -v "${RUTA}/.zshrc"          "${HOME}/.zshrc"
    run cp -v "${RUTA}/.p10k.zsh"       "${HOME}/.p10k.zsh"
    run sudo cp -v "${RUTA}/.p10k.zsh-root" /root/.p10k.zsh

    # Scripts auxiliares
    run sudo cp -v "${RUTA}/scripts/whichSystem.py" /usr/local/bin/
    run sudo cp -v "${RUTA}/scripts/screenshot"     /usr/local/bin/
    run sudo chmod +x /usr/local/bin/whichSystem.py /usr/local/bin/screenshot

    # Permisos de ejecución
    for f in "${HOME}/.config/bspwm/bspwmrc" \
             "${HOME}/.config/bspwm/scripts/bspwm_resize" \
             "${HOME}/.config/bin/ethernet_status.sh" \
             "${HOME}/.config/bin/htb_status.sh" \
             "${HOME}/.config/bin/htb_target.sh" \
             "${HOME}/.config/polybar/launch.sh"; do
        [ -f "$f" ] && run chmod +x "$f"
    done

    mark_step "config"
    ok "Configuración aplicada. Respaldo en ${BACKUP}"
fi

# --- 7. Desactivar picom (ver NOTA_PICOM arriba) ------------------------------
if done_step "picom"; then
    ok "Picom ya desactivado, salto."
else
    info "Desactivando el autoarranque de picom (sin aceleración 3D)..."
    for rc in "${HOME}/.config/bspwm/bspwmrc"; do
        [ -f "$rc" ] || continue
        # Comenta cualquier línea que invoque picom y no esté ya comentada.
        # /picom/ es sensible a mayúsculas, así que los encabezados tipo
        # "# PICOM" no se ven afectados.
        if grep -qE '^[[:space:]]*[^#[:space:]].*picom|^[[:space:]]*picom' "$rc"; then
            run sed -i -E '/picom/ { /^[[:space:]]*#/! s|^|# [desactivado: VM sin aceleracion 3D] | }' "$rc"
            ok "Comentada la invocación de picom en $rc"
        else
            ok "No hay invocación activa de picom en $rc"
        fi
    done
    mark_step "picom"
fi

# --- 7b. Reemplazar VMware Tools por spice-vdagent ---------------------------
# El bspwmrc original lanza vmware-user-suid-wrapper, que no existe en KVM.
# bspwm no procesa los autostart de XDG, así que spice-vdagent hay que
# arrancarlo desde el bspwmrc o no hay portapapeles ni auto-resize.
if done_step "vdagent"; then
    ok "spice-vdagent ya configurado en bspwmrc, salto."
else
    rc="${HOME}/.config/bspwm/bspwmrc"
    if [ -f "$rc" ]; then
        if grep -q 'vmware-user-suid-wrapper' "$rc"; then
            info "Quitando vmware-user-suid-wrapper del bspwmrc..."
            run sed -i '/vmware-user-suid-wrapper/d' "$rc"
        fi
        if ! grep -q 'spice-vdagent' "$rc"; then
            info "Añadiendo spice-vdagent al bspwmrc..."
            run sed -i '/^wmname/a \\ncommand -v spice-vdagent >/dev/null 2>\&1 \&\& spice-vdagent \&' "$rc"
        fi
        ok "bspwmrc ajustado para KVM/SPICE."
    fi
    mark_step "vdagent"
fi

# --- 8. Shell por defecto -----------------------------------------------------
if done_step "shell"; then
    ok "Shell ya configurado, salto."
else
    info "Cambiando el shell por defecto a zsh..."
    run sudo chsh -s /usr/bin/zsh "$USER"
    run sudo usermod --shell /usr/bin/zsh root
    run sudo ln -sfv "${HOME}/.zshrc" /root/.zshrc
    mark_step "shell"
    ok "Shell cambiado (aplica al próximo login)."
fi

# --- 9. Verificaciones finales ------------------------------------------------
info "Verificando el resultado..."

if [ "$DRY" -eq 0 ]; then
    for cmd in bspwm sxhkd polybar rofi kitty zsh feh; do
        if command -v "$cmd" >/dev/null 2>&1; then
            ok "$cmd  $(command -v "$cmd")"
        else
            err "$cmd  NO ENCONTRADO"
        fi
    done

    if [ -f /usr/share/xsessions/bspwm.desktop ]; then
        ok "Sesión bspwm registrada en el gestor de login"
    else
        warn "No encuentro /usr/share/xsessions/bspwm.desktop"
    fi

    # Relevante en VM: spice-vdagent da portapapeles y auto-resize.
    # Funciona completo en X11 (bspwm), a diferencia de Wayland.
    if systemctl is-active --quiet spice-vdagent 2>/dev/null; then
        ok "spice-vdagent activo"
    else
        warn "spice-vdagent inactivo — sin portapapeles compartido ni auto-resize"
    fi

    run sudo updatedb 2>/dev/null || true
fi

echo
ok "Instalación completada."
echo -e "
  ${B}Siguientes pasos:${E}
    1. Cierra sesión.
    2. En la pantalla de login (SDDM), elige ${G}bspwm${E} en el selector de sesión.
    3. Atajos base: ${G}super+Enter${E} terminal · ${G}super+d${E} rofi · ${G}super+q${E} cerrar ventana

  ${B}Si algo se ve mal:${E}
    Respaldo de tu config previa: ${BACKUP}
    Reanudar esta instalación:    ./install.sh
    Empezar de cero:              ./install.sh --reset
    Revertir la VM completa:      sudo virsh snapshot-revert parrot-sec base-configurada
"
