#!/usr/bin/env bash
set -eo pipefail

VERSION="${1:-7.2-Stable}"
WORKSPACE_DIR="${2:-/workspace}"
CONFIG_DIR="${WORKSPACE_DIR}/config"
OUTPUT_DIR="${WORKSPACE_DIR}/output"

mkdir -p "${OUTPUT_DIR}"

echo "============================================================"
echo "      ThinStation Automated Build Script"
echo " Версия:           ${VERSION}"
echo " Сервер VDI:        vdi.dnestrschool1.online"
echo " Каталог вывода:    ${OUTPUT_DIR}"
echo "============================================================"

BUILD_DIR="/tmp/thinstation-build"
rm -rf "${BUILD_DIR}"

if [ "${VERSION}" = "7.2-Stable" ]; then
    REPO_URL="https://github.com/Thinstation/thinstation-ng.git"
    BRANCH="7.2-Stable"
    CONF_DIR="${CONFIG_DIR}/7.2"
else
    REPO_URL="https://github.com/Thinstation/thinstation.git"
    BRANCH="6.2-Stable"
    CONF_DIR="${CONFIG_DIR}/6.2"
fi

echo "--> Клонирование репозитория ThinStation: ${REPO_URL} (${BRANCH})..."
git clone --depth 1 -b "${BRANCH}" "${REPO_URL}" "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Предотвращение интерактивных запросов в CI
export AUTODL=true
export CI=true

# Подавление интерактивного ридера README
mkdir -p ts/etc etc
touch ts/etc/READ etc/READ 2>/dev/null || true

echo "--> Инициализация chroot-окружения (install-only)..."
./setup-chroot -a -i < /dev/null

HORIZON_RPM="Omnissa-Horizon-Client-2506-8.16.0-16536624989.x64.rpm"
GDRIVE_URL="https://drive.usercontent.google.com/download?id=1TsopTTdWTlszhXrYD3uQiLhYD9qqvp83&export=download&confirm=t"

mkdir -p "${WORKSPACE_DIR}/downloads"
if [ ! -f "${WORKSPACE_DIR}/downloads/${HORIZON_RPM}" ] || [ "$(stat -c%s "${WORKSPACE_DIR}/downloads/${HORIZON_RPM}" 2>/dev/null || echo 0)" -lt 100000000 ]; then
    echo "--> Скачивание ${HORIZON_RPM} из Google Drive..."
    curl -fSL --retry 5 --retry-delay 3 -o "${WORKSPACE_DIR}/downloads/${HORIZON_RPM}" "${GDRIVE_URL}"
fi

# Подготовка каталогов downloads для проприетарных пакетов (Horizon / VMware)
mkdir -p downloads /downloads ts/build/downloads
if [ -d "${WORKSPACE_DIR}/downloads" ] && [ -n "$(ls -A "${WORKSPACE_DIR}/downloads" 2>/dev/null)" ]; then
    echo "  [OK] Копирование файлов из каталога downloads репозитория..."
    cp -vf "${WORKSPACE_DIR}/downloads/"* downloads/ 2>/dev/null || true
    cp -vf "${WORKSPACE_DIR}/downloads/"* /downloads/ 2>/dev/null || true
    cp -vf "${WORKSPACE_DIR}/downloads/"* ts/build/downloads/ 2>/dev/null || true
fi

echo "  [OK] Проверка наличия пакета Horizon Client:"
ls -lh downloads/${HORIZON_RPM} || true
ls -lh /downloads/${HORIZON_RPM} || true

echo "--> Применение конфигурационных файлов для vdi.dnestrschool1.online..."
if [ -f "${CONF_DIR}/build.conf" ]; then
    echo "  [OK] Копирование build.conf"
    cp -vf "${CONF_DIR}/build.conf" ts/build/build.conf
else
    echo "  [!] Внимание: ${CONF_DIR}/build.conf не найден, используется конфигурация по умолчанию"
fi

if [ -f "${CONF_DIR}/thinstation.conf.buildtime" ]; then
    echo "  [OK] Копирование thinstation.conf.buildtime"
    cp -vf "${CONF_DIR}/thinstation.conf.buildtime" ts/build/thinstation.conf.buildtime
else
    echo "  [!] Внимание: ${CONF_DIR}/thinstation.conf.buildtime не найден"
fi

echo "--> Применение оптимизаций сети и рабочего стола..."
# 1. Отключение NetworkManager-wait-online (устраняет 90-секундное зависание при старте)
if [ -f "ts/build/packages/networkmanager/build/finalize" ]; then
    echo "  [OK] Патч networkmanager: отключение блокирующего NetworkManager-wait-online"
    sed -i '/NetworkManager-wait-online/d' ts/build/packages/networkmanager/build/finalize || true
fi

# 2. Настройка NetworkManager: принудительное управление ВСЕМИ интерфейсами (Ethernet + Wi-Fi) и внутренний DHCP
for nmdir in ts/build/packages/networkmanager/build/extra/etc/NetworkManager ts/build/packages/base/build/extra/etc/NetworkManager; do
    mkdir -p "$nmdir/conf.d"
    cat << 'EOF' > "$nmdir/conf.d/10-manage-all.conf"
[main]
dhcp=internal
plugins=keyfile

[keyfile]
unmanaged-devices=none

[device]
match-device=*
managed=true
EOF
    cp -vf "$nmdir/conf.d/10-manage-all.conf" "$nmdir/NetworkManager.conf" 2>/dev/null || true
done

# Удаление любых конфигураций, блокирующих управление устройствами
find ts/build -name "*unmanaged*" -delete 2>/dev/null || true
find ts/build -name "10-globally-managed-devices.conf" -delete 2>/dev/null || true

# 3. Гарантированный автозапуск nm-applet в системном трее
for xdgdir in ts/build/packages/networkmanager/build/extra/etc/xdg/autostart ts/build/packages/base/build/extra/etc/xdg/autostart; do
    mkdir -p "$xdgdir"
    cat << 'EOF' > "$xdgdir/nm-applet.desktop"
[Desktop Entry]
Name=Network
Comment=Manage your network connections
Icon=nm-device-wireless
Exec=nm-applet
Terminal=false
Type=Application
NotShowIn=KDE;
EOF
done

# 4. Предварительно созданный профиль проводной сети (Ethernet auto-dhcp)
for scdir in ts/build/packages/networkmanager/build/extra/etc/NetworkManager/system-connections ts/build/packages/base/build/extra/etc/NetworkManager/system-connections; do
    mkdir -p "$scdir"
    cat << 'EOF' > "$scdir/Wired.nmconnection"
[connection]
id=Wired
uuid=d6b7b252-0c98-4c22-901c-6d9e79435bcf
type=ethernet
autoconnect=true
autoconnect-priority=1

[ethernet]

[ipv4]
method=auto

[ipv6]
method=auto
EOF
    chmod 600 "$scdir/Wired.nmconnection" || true
done

# 5. Привязка machine-id для D-Bus (устранение ошибки Horizon CdkClientInfo_SaveDeviceID)
mkdir -p ts/build/packages/base/build/extra/var/lib/dbus
ln -sf /etc/machine-id ts/build/packages/base/build/extra/var/lib/dbus/machine-id 2>/dev/null || true

# 6. Конфигурация тачпада для X.Org (включение tap-to-click / клик касанием)
mkdir -p ts/build/packages/base/build/extra/etc/X11/xorg.conf.d
cat << 'EOF' > ts/build/packages/base/build/extra/etc/X11/xorg.conf.d/30-touchpad.conf
Section "InputClass"
    Identifier "touchpad"
    MatchIsTouchpad "on"
    Driver "libinput"
    Option "Tapping" "on"
    Option "NaturalScrolling" "false"
    Option "ClickMethod" "clickfinger"
EndSection
EOF

# 7. Предварительная настройка клиента Omnissa / VMware Horizon (сервер, SSL, автоподключение, мультимонитор)
mkdir -p ts/build/packages/base/build/extra/etc/omnissa
cat << 'EOF' > ts/build/packages/base/build/extra/etc/omnissa/horizon-default-config
view.defaultBroker = "https://vdi.dnestrschool1.online"
view.sslVerificationMode = "3"
view.autoConnectBroker = "TRUE"
view.defaultDesktopSize = "1"
EOF

mkdir -p ts/build/packages/base/build/extra/etc/vmware
cat << 'EOF' > ts/build/packages/base/build/extra/etc/vmware/view-default-config
view.defaultBroker = "https://vdi.dnestrschool1.online"
view.sslVerificationMode = "3"
view.autoConnectBroker = "TRUE"
view.defaultDesktopSize = "1"
EOF

mkdir -p ts/build/packages/base/build/extra/etc/skel/.omnissa
cat << 'EOF' > ts/build/packages/base/build/extra/etc/skel/.omnissa/horizon-preferences
view.defaultBroker = "https://vdi.dnestrschool1.online"
view.sslVerificationMode = "3"
view.autoConnectBroker = "TRUE"
view.defaultDesktopSize = "1"
EOF

mkdir -p ts/build/packages/base/build/extra/etc/skel/.vmware
cat << 'EOF' > ts/build/packages/base/build/extra/etc/skel/.vmware/view-preferences
view.defaultBroker = "https://vdi.dnestrschool1.online"
view.sslVerificationMode = "3"
view.autoConnectBroker = "TRUE"
view.defaultDesktopSize = "1"
EOF

mkdir -p ts/build/packages/base/build/extra/root/.omnissa
cp -vf ts/build/packages/base/build/extra/etc/skel/.omnissa/horizon-preferences ts/build/packages/base/build/extra/root/.omnissa/ 2>/dev/null || true
mkdir -p ts/build/packages/base/build/extra/root/.vmware
cp -vf ts/build/packages/base/build/extra/etc/skel/.vmware/view-preferences ts/build/packages/base/build/extra/root/.vmware/ 2>/dev/null || true

# Обязательная конфигурация (mandatory config) для безусловного применения адреса сервера и автоконнекта
cp -vf ts/build/packages/base/build/extra/etc/omnissa/horizon-default-config ts/build/packages/base/build/extra/etc/omnissa/horizon-mandatory-config 2>/dev/null || true
cp -vf ts/build/packages/base/build/extra/etc/vmware/view-default-config ts/build/packages/base/build/extra/etc/vmware/view-mandatory-config 2>/dev/null || true

# Скрипт-обертка для horizon-client: перехватывает и очищает некорректные флаги CLI
mkdir -p ts/build/packages/base/build/extra/usr/local/bin
cat << 'EOF' > ts/build/packages/base/build/extra/usr/local/bin/horizon-client
#!/bin/sh
# Обертка для безопасного запуска horizon-client без сбойных параметров CLI
CLEAN_ARGS=""
for arg in "$@"; do
    case "$arg" in
        --keep_wm_bindings*)
            # Игнорировать неизвестный параметр
            ;;
        --noninteractive=false|--nonInteractive=false)
            # Игнорировать некорректное значение
            ;;
        --allmonitors=true)
            CLEAN_ARGS="$CLEAN_ARGS --allmonitors"
            ;;
        --fullscreen=true)
            CLEAN_ARGS="$CLEAN_ARGS --fullscreen"
            ;;
        *)
            CLEAN_ARGS="$CLEAN_ARGS $arg"
            ;;
    esac
done
exec /usr/bin/horizon-client $CLEAN_ARGS
EOF
chmod +x ts/build/packages/base/build/extra/usr/local/bin/horizon-client || true

# 8. Автоматическое расширение рабочего стола на все подключенные мониторы (Multi-Monitor Extended Desktop)
mkdir -p ts/build/packages/base/build/extra/bin
cat << 'EOF' > ts/build/packages/base/build/extra/bin/auto-multimonitor
#!/bin/sh
CONNECTED=$(xrandr -q 2>/dev/null | awk '/ connected/ {print $1}')
COUNT=$(echo "$CONNECTED" | wc -w)
if [ "$COUNT" -gt 1 ]; then
    CMD="xrandr"
    PREV=""
    for MON in $CONNECTED; do
        if [ -z "$PREV" ]; then
            CMD="$CMD --output $MON --auto --primary"
        else
            CMD="$CMD --output $MON --auto --right-of $PREV"
        fi
        PREV="$MON"
    done
    $CMD 2>/dev/null || true
fi
EOF
chmod +x ts/build/packages/base/build/extra/bin/auto-multimonitor || true

mkdir -p ts/build/packages/base/build/extra/etc/xdg/autostart
cat << 'EOF' > ts/build/packages/base/build/extra/etc/xdg/autostart/auto-multimonitor.desktop
[Desktop Entry]
Type=Application
Name=Auto Multi-Monitor
Exec=/bin/auto-multimonitor
Terminal=false
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

mkdir -p ts/build/packages/base/build/extra/etc/X11/xinit/xinitrc.d
cp -vf ts/build/packages/base/build/extra/bin/auto-multimonitor ts/build/packages/base/build/extra/etc/X11/xinit/xinitrc.d/00-multimonitor.sh || true
chmod +x ts/build/packages/base/build/extra/etc/X11/xinit/xinitrc.d/00-multimonitor.sh || true

# 9. Интеграция прошивок беспроводных сетей (Wi-Fi Firmware) и авторазблокировка радиомодулей
echo "--> Копирование прошивок беспроводных адаптеров (Wi-Fi firmware)..."
mkdir -p ts/build/packages/base/build/extra/lib/firmware
cp -vf /lib/firmware/regulatory.db* ts/build/packages/base/build/extra/lib/firmware/ 2>/dev/null || true
for fw in iwlwifi* intel rtw88 rtw89 rtlwifi mediatek ath10k ath11k brcm; do
    for src in /lib/firmware/$fw; do
        if [ -e "$src" ]; then
            cp -rf "$src" ts/build/packages/base/build/extra/lib/firmware/ 2>/dev/null || true
        fi
    done
done

# Копирование nm-applet если установлен в сборочном контейнере
mkdir -p ts/build/packages/base/build/extra/usr/bin
if [ -f "/usr/bin/nm-applet" ]; then
    echo "  [OK] Копирование nm-applet в образ..."
    cp -vf /usr/bin/nm-applet ts/build/packages/base/build/extra/usr/bin/ 2>/dev/null || true
    [ -f "/usr/bin/nm-connection-editor" ] && cp -vf /usr/bin/nm-connection-editor ts/build/packages/base/build/extra/usr/bin/ 2>/dev/null || true
fi

# Разблокировка радиомодулей Wi-Fi и включение радио в NetworkManager
cat << 'EOF' > ts/build/packages/base/build/extra/etc/xdg/autostart/01-wifi-unblock.desktop
[Desktop Entry]
Type=Application
Name=WiFi Unblock
Exec=/bin/sh -c "rfkill unblock all 2>/dev/null; nmcli radio wifi on 2>/dev/null"
Terminal=false
Hidden=false
X-GNOME-Autostart-enabled=true
EOF

# Гарантия наличия nm-applet в автозапуске base пакета
mkdir -p ts/build/packages/base/build/extra/etc/xdg/autostart
cp -vf ts/build/packages/networkmanager/build/extra/etc/xdg/autostart/nm-applet.desktop ts/build/packages/base/build/extra/etc/xdg/autostart/ 2>/dev/null || true

echo "--> Запуск сборки образа ThinStation со всеми модулями ядра (All Modules)..."
touch ts/build/ALLMODULES || true
./setup-chroot -b -o --allmodules < /dev/null

echo "--> Поиск и экспорт созданных загрузочных образов..."
mkdir -p "${OUTPUT_DIR}"

# 1. Поиск в каталогах boot-images (ThinStation 7.2 использует ts/build/boot-images)
for bdir in "${BUILD_DIR}/ts/build/boot-images" "${BUILD_DIR}/boot-images" "/build/boot-images"; do
    if [ -d "$bdir" ]; then
        echo "  [OK] Найдена папка образов: $bdir"
        find "$bdir" -type f \( -name "*.iso" -o -name "*.img" -o -name "vmlinuz*" -o -name "initrd*" -o -name "*.squash*" \) -exec cp -vf {} "${OUTPUT_DIR}/" \;
    fi
done

# 2. Общий рекурсивный поиск ISO-образов во всей директории сборки
find "${BUILD_DIR}" /build -type f -name "*.iso" -exec cp -vf {} "${OUTPUT_DIR}/" \; 2>/dev/null || true


# Генерация контрольных сумм SHA-256 для проверки целостности
(cd "${OUTPUT_DIR}" && sha256sum * > SHA256SUMS.txt 2>/dev/null) || true

# Обеспечиваем полные права на чтение файлов раннером GitHub Actions
chmod -R 777 "${OUTPUT_DIR}" 2>/dev/null || true

echo "============================================================"
echo " Список сформированных файлов в ${OUTPUT_DIR}:"
ls -lh "${OUTPUT_DIR}"
echo "============================================================"

# Проверяем, что выходная папка не пуста
if [ -z "$(ls -A "${OUTPUT_DIR}" 2>/dev/null)" ]; then
    echo "ОШИБКА: Загрузочные образы не найдены! Выводим дерево ts/build для диагностики:"
    find "${BUILD_DIR}/ts/build" -maxdepth 4 -ls || true
    exit 1
fi

