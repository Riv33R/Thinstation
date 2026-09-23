# История изменений и архитектурных решений (Changelog)

В данном документе зафиксированы все ключевые изменения, исправления ошибок загрузки и архитектурные решения, реализованные в процессе адаптации дистрибутива **ThinStation 7.2-ng** для подключения к VDI-серверу **Omnissa / VMware Horizon** (`https://vdi.dnestrschool1.online`) на различном клиентском оборудовании (Intel NUC, ПК, ноутбуки).

---

## 📑 Содержание
1. [Устранение сбоев загрузки ядра и Init](#1-устранение-сбоев-загрузки-ядра-и-init)
   - [Ошибка unknown-block(0,0) (VFS Mount Failure)](#ошибка-unknown-block00-vfs-mount-failure)
   - [Ошибка No working init found](#ошибка-no-working-init-found)
   - [Ошибка Attempted to kill init! exitcode=0x00007f00](#ошибка-attempted-to-kill-init-exitcode0x00007f00)
2. [Поддержка оборудования и полный пакет модулей ядра](#2-поддержка-оборудования-и-полный-пакет-модулей-ядра)
   - [Возврат полного набора модулей (--allmodules)](#возврат-полного-набора-модулей---allmodules)
   - [Аппаратное ускорение графики (DRM / KMS / X.Org)](#аппаратное-ускорение-графики-drm--kms--xorg)
   - [Интеграция микропрограмм (Firmware)](#интеграция-микропрограмм-firmware)
3. [Сетевой стек и Wi-Fi апплет](#3-сетевой-стек-и-wi-fi-апплет)
4. [Интеграция и оптимизация клиента Omnissa Horizon](#4-интеграция-и-оптимизация-клиента-omnissa-horizon)
5. [Тачпады и мультимониторные конфигурации](#5-тачпады-и-мультимониторные-конфигурации)
6. [Таблица коммитов](#6-таблица-коммитов)

---

## 1. Устранение сбоев загрузки ядра и Init

### Ошибка unknown-block(0,0) (VFS Mount Failure)
* **Симптом:** Ядро Linux завершалось аварийно на ранней стадии с сообщением:  
  `Kernel panic - not syncing: VFS: Unable to mount root fs on unknown-block(0,0)`.
* **Причина:** По умолчанию в ThinStation при некоторых режимах сжатия генерируется заглушка initrd (squashfs-стаб), которая требует загрузки дополнительных модулей файловой системы до того, как они становятся доступны.
* **Решение:** В [config/7.2/build.conf](config/7.2/build.conf) задан параметр:
  ```text
  param initrdcmd "xz"
  ```
  Это перевело сборку на создание монолитного `initramfs`, сжатого алгоритмом XZ, который ядро Linux распаковывает в RAM нативно без потребности во внешних драйверах блочных устройств.

---

### Ошибка No working init found
* **Симптом:** `Kernel panic - not syncing: No working init found. Try passing init= option to kernel`.
* **Причина:** В файле `build.conf` отсутствовало явное объявление базового системного пакета `package base`, из-за чего скрипт `/init` не помещался в корень создаваемого образа.
* **Решение:** Добавлен пакет `package base` в [config/7.2/build.conf](config/7.2/build.conf).

---

### Ошибка Attempted to kill init! exitcode=0x00007f00
* **Симптом:** На этапе инициализации пользовательского пространства система падала с паникой:
  ```text
  [ 3.086184] ? __x64_sys_openat+0x61/0xa0
  ...
  ORIG_RAX: 0x000000e7 (sys_exit_group)
  RAX: ffffffffffffffda (-ENOENT: файл не найден)
  RDI: 0x0000007f (127)
  ---[ end Kernel panic - not syncing: Attempted to kill init! exitcode=0x00007f00 ]---
  ```
* **Глубинный анализ:**
  1. Вызов `exit_group(127)` (`0x7f00`) генерируется динамическим компоновщиком GLIBC (`ld-linux.so`) или процессом `systemd`, когда при старте не удается открыть критически важный файл библиотеки через системный вызов `openat` (код возврата `-2` / `-ENOENT`, отображаемый в регистре RAX как `0xffffffffffffffda`).
  2. Виновником разделения файловой системы был параметр `param fastboot lotsofmem`. Утилита `fastboot-mangle` вырезала большинство разделяемых библиотек (`.so`) из `initrd` и переносила их во внешний сжатый образ `lib.squash`.
  3. При загрузке с USB-накопителя образ `lib.squash` не успевал смонтироваться до запуска `systemd`, из-за чего динамический линковщик не находил библиотеки и процесс PID 1 аварийно завершался.
  4. Дополнительно `systemd` требовал валидный 32-значный шестнадцатеричный `machine-id`.
* **Решение:**
  1. **Полное отключение Fastboot:** В [config/7.2/build.conf](config/7.2/build.conf) установлено:
     ```text
     param fastboot false
     ```
     Это исключило выполнение `fastboot-mangle`: все библиотеки, бинарные файлы и модули ядра теперь сохраняются непосредственно внутри единого целостного `initrd`.
  2. **Генерация Machine ID:** В скрипт `/init` добавлен парсинг `machine-id` из `/proc/sys/kernel/random/boot_id` (или аргументов командной строки) с записью в `/etc/machine-id` и `/var/lib/dbus/machine-id`.
  3. **Обновление кэша компоновщика (`ldconfig`):** В `/init` добавлен вызов `ldconfig` перед стартом `systemd` для обновления связей библиотек в оперативной памяти.
  4. **Поиск корня в GRUB:** В шаблон `grub.cfg` внедрена команда `search --no-floppy --file --set=root /boot/vmlinuz`.

---

## 2. Поддержка оборудования и полный пакет модулей ядра

### Возврат полного набора модулей (`--allmodules`)
* Для обеспечения бесшовной загрузки на различном оборудовании заказчика (ПК любых поколений, ноутбуки разных производителей, неттопы Intel NUC) в [scripts/build.sh](scripts/build.sh) включен режим All Modules:
  ```bash
  touch ts/build/ALLMODULES || true
  ./setup-chroot -b -o --allmodules < /dev/null
  ```
* Это включает в ядро все доступные драйверы:
  - Сетевые карты: Realtek (RTL8111/8168/8125/8139), Intel (e1000e, igb, igc, i40e, ixgbe), Broadcom (tg3, bnx2), Atheros (alx), Marvell (sky2), Aquantia (atlantic), USB-Ethernet (ASIX, Realtek, CDC-NCM/MBIM).
  - Контроллеры накопителей: AHCI SATA, NVMe SSD, USB Storage, UAS (USB Attached SCSI).
  - Wi-Fi адаптеры всех основных брендов.

### Аппаратное ускорение графики (DRM / KMS / X.Org)
* **Проблема:** После успешного старта ядра служба `lightdm.service` падала с ошибкой, так как X-сервер не находил видеоустройств (`No screens found`).
* **Решение:** В [config/7.2/build.conf](config/7.2/build.conf) добавлены драйверы ядра KMS/DRM и компоненты X.Org:
  - **Intel:** `module i915`, `module intel_gtt`, `package xorg7-intel` (поддержка Intel HD/UHD/Iris Plus 640 в NUC7i5BNB).
  - **AMD:** `module amdgpu`, `module radeon`, `package xorg7-amdgpu`, `package xorg7-ati`.
  - **NVIDIA:** `module nouveau`, `package xorg7-nouveau`.
  - **Универсальные/Резервные:** `module simpledrm`, `module bochs`, `module vmwgfx`, `module qxl`, `module drm`, `module drm_kms_helper`, `package xorg7-vesa`, `package xorg7-fbdev`.
* **Права и каталоги LightDM:** В [scripts/build.sh](scripts/build.sh) и `/init` обеспечено создание рабочих каталогов `/var/lib/lightdm`, `/var/log/lightdm`, `/var/cache/lightdm`, `/run/lightdm`, `/tmp/.X11-unix` с правами `1777`.

### Интеграция микропрограмм (Firmware)
* В сборочный образ принудительно копируются прошивки из сборочного контейнера Fedora 42:
  - Видеокарты: `i915` (DMC, GuC, HuC прошивки для Intel Skylake/Kaby Lake и новее), `amdgpu`, `radeon`, `nouveau`.
  - Беспроводные сети: `iwlwifi`, `intel`, `rtw88`, `rtw89`, `rtlwifi`, `rtl_bt`, `mediatek`, `ath10k`, `ath11k`, `brcm`, `regulatory.db`.

---

## 3. Сетевой стек и Wi-Fi апплет

* **Отключение NetworkManager-wait-online:** В скрипте сборки пропатчен финализатор пакета networkmanager, убирающий ожидание сети при старте (устраняет 90-секундную задержку загрузки при отключенном кабеле Ethernet).
* **Принудительное управление интерфейсами:** Создан конфиг `10-manage-all.conf` (`managed=true`, `unmanaged-devices=none`), переключающий NetworkManager на внутренний DHCP-клиент (`dhcp=internal`).
* **Графический апплет выбора сетей:** Настроен автозапуск `nm-applet` в трее через `xdg/autostart` для обеих сессий (`SESSION_0` и `SESSION_1`).
* **Авторазблокировка радиомодулей:** Добавлен сервис автозапуска `rfkill unblock all; nmcli radio wifi on`.
* **Профиль проводной сети:** Создан дефолтный профиль `Wired.nmconnection` с наивысшим приоритетом автоподключения.

---

## 4. Интеграция и оптимизация клиента Omnissa Horizon

* **Целевой сервер VDI:** `https://vdi.dnestrschool1.online`.
* **Автоподключение:**
  - Созданы файлы `horizon-default-config`, `view-default-config`, а также обязательные конфигурации `horizon-mandatory-config` и `view-mandatory-config`.
  - Установлены параметры:
    ```ini
    view.defaultBroker = "https://vdi.dnestrschool1.online"
    view.sslVerificationMode = "3"
    view.autoConnectBroker = "TRUE"
    view.defaultDesktopSize = "1"
    ```
* **Скрипт-обертка `horizon-client`:** Создан безопасный wrapper `/usr/local/bin/horizon-client`, который фильтрует неподдерживаемые CLI-аргументы (`--keep_wm_bindings`, `--noninteractive=false`, некорректные булевы флаги `--allmonitors=true`), предотвращая аварийное завершение клиента при старте из сессии ThinStation.

---

## 5. Тачпады и мультимониторные конфигурации

* **Тачпады на ноутбуках:**
  - Включены драйверы `xorg7-xinput`, `libinput`, `psmouse`, `hid-multitouch`, `i2c-hid`, `i2c-hid-acpi`, `intel-lpss-pci`, `elan_i2c`, `rmi_core`.
  - Создана конфигурация `/etc/X11/xorg.conf.d/30-touchpad.conf` с включением клика касанием (`Option "Tapping" "on"`) и метода клика двумя пальцами (`clickfinger`).
* **Мультимонитор (Extended Desktop):**
  - Разработан скрипт `/bin/auto-multimonitor`, выполняющий динамическое сканирование подключенных экранов через `xrandr` и объединяющий их в широкий рабочий стол слева направо (`--right-of`) с назначением первого монитора основным (`--primary`).
  - Скрипт добавлен в `/etc/xdg/autostart/` и `/etc/X11/xinit/xinitrc.d/`.

---

## 6. Таблица коммитов

| Хеш коммита | Описание изменений |
| :--- | :--- |
| `ea0b7ff` | **Отключение fastboot (`param fastboot false`)**, устранение паники ядра `Attempted to kill init! exitcode=0x00007f00`, добавление вызова `ldconfig` в раннем `/init`. |
| `23a8e17` | **Возврат полного пакета модулей (`--allmodules`)**, добавление драйверов DRM/GPU (`i915`, `drm`, `vesa`, `fbdev`), прошивок GPU и создание каталогов LightDM. |
| `7eeb466` | Исправление паники init на Intel NUC: гарантированная генерация `machine-id`, защита библиотек systemd, добавление `search --file /boot/vmlinuz` в GRUB и `earlymicrocode`. |
| `4ed517f` | Включение сборки со всеми модулями, полная матрица сетевых драйверов Ethernet, принудительное управление всеми интерфейсами в NetworkManager. |
| `c1a552f` | Очистка устаревших зависимостей в сборочном контейнере Fedora 42 (`--skip-broken`). |
| `8ebed5f` | Скрипт-обертка для `horizon-client`, интеграция прошивок Wi-Fi и авторазблокировка rfkill. |
| `63cf301` | Документирование расширенного рабочего стола (multi-monitor), жестов тачпада и настроек Wi-Fi. |
| `3c499ea` | Добавление пакета `package base` для устранения ошибки `No working init found`. |
| `e836d62` | Переход на `param initrdcmd "xz"` для устранения ошибки `unknown-block(0,0)`. |
