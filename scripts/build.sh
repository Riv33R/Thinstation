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

echo "--> Запуск сборки образа ThinStation..."
./setup-chroot -b < /dev/null

echo "--> Поиск и экспорт созданных загрузочных образов..."
mkdir -p "${OUTPUT_DIR}"

# 1. Поиск в каталогах boot-images (ThinStation 7.2 использует ts/build/boot-images)
for bdir in "${BUILD_DIR}/ts/build/boot-images" "${BUILD_DIR}/boot-images" "/build/boot-images"; do
    if [ -d "$bdir" ]; then
        echo "  [OK] Найдена папка образов: $bdir"
        find "$bdir" -type f \( -name "*.iso" -o -name "*.img" -o -name "vmlinuz*" -o -name "initrd*" \) -exec cp -vf {} "${OUTPUT_DIR}/" \;
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

