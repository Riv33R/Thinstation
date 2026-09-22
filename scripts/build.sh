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

# Подготовка каталога downloads для проприетарных пакетов (Horizon / VMware)
mkdir -p downloads /downloads ts/build/downloads
if [ -d "${WORKSPACE_DIR}/downloads" ] && [ -n "$(ls -A "${WORKSPACE_DIR}/downloads" 2>/dev/null)" ]; then
    echo "  [OK] Копирование файлов из каталога downloads репозитория..."
    cp -vf "${WORKSPACE_DIR}/downloads/"* downloads/ 2>/dev/null || true
    cp -vf "${WORKSPACE_DIR}/downloads/"* /downloads/ 2>/dev/null || true
    cp -vf "${WORKSPACE_DIR}/downloads/"* ts/build/downloads/ 2>/dev/null || true
fi

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

echo "--> Запуск сборки образа ThinStation..."
./setup-chroot -b < /dev/null

echo "--> Поиск и экспорт созданных загрузочных образов..."
# ThinStation помещает образы в boot-images/ (grub/thinstation-efi.iso или iso/thinstation.iso)
found_any=false
while IFS= read -r file; do
    echo "  [Сохранение] $file"
    cp -vf "$file" "${OUTPUT_DIR}/"
    found_any=true
done < <(find boot-images/ -type f \( -name "*.iso" -o -name "*.img" -o -name "vmlinuz*" -o -name "initrd*" \))

if [ "$found_any" = false ]; then
    echo "  [!] Образы в boot-images не найдены по маске, копируем всё содержимое boot-images..."
    cp -rvf boot-images/* "${OUTPUT_DIR}/" 2>/dev/null || true
fi

echo "============================================================"
echo " Сборка завершена успешно!"
echo " Список сформированных файлов в ${OUTPUT_DIR}:"
ls -lh "${OUTPUT_DIR}"
echo "============================================================"
