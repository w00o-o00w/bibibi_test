#!/usr/bin/env bash
# =====================================================================
#  bibibi_test — повне тестування ноутбука (Linux / macOS)
#  https://github.com/w00o-o00w/bibibi_test
#
#  Запуск з GitHub:
#    sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/w00o-o00w/bibibi_test/main/bibibi_test.sh)"
#  Або локально:
#    sudo bash bibibi_test.sh
#
#  Що робить: тільки ЧИТАЄ інформацію про залізо і систему, навантажує процесор,
#  пише і видаляє тимчасовий файл для тесту диска, зберігає звіт на робочий стіл.
#  Linux: якщо бракує діагностичних утиліт (smartmontools, dmidecode, pciutils,
#  usbutils) — ставить їх з офіційного репозиторію і В КІНЦІ ВИДАЛЯЄ рівно те,
#  що поставив. macOS: нічого не встановлює.
#  Нічого не відправляє в інтернет.
#
#  Параметри: --no-browser   --cpu-seconds N   --disk-mb N
#  Сумісно з bash 3.2 (стандартний bash на macOS).
# =====================================================================

BIBIBI_VERSION="1.0.0"
CPU_SECONDS=300
DISK_MB=2048
NO_BROWSER=0

OS_KIND=""; WORK=""; CUR_PID=""; SKIP_FLAG=0; ABORT=0; LAST_INT=0
PM=""; INSTALLED=""; DISKTEST_FILE=""; CLEANED=0
CU=""; CU_UID=""; CU_HOME=""; CU_DISPLAY=""; U_DESKTOP=""; U_DOWNLOADS=""
M_HOST=""; M_MODEL=""; M_SERIAL=""; M_OS=""
RS=(); RC=(); RT=(); RV=(); SK=(); SV=()

if [ -t 1 ]; then
  C_R=$'\033[31m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_C=$'\033[36m'; C_M=$'\033[35m'; C_D=$'\033[90m'; C_B=$'\033[1m'; C_0=$'\033[0m'
else
  C_R=""; C_G=""; C_Y=""; C_C=""; C_M=""; C_D=""; C_B=""; C_0=""
fi

# ===================================================================== утиліти
has()   { command -v "$1" >/dev/null 2>&1; }
trim()  { local s="$*"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }
clean() {
  local s="$*"
  s=$(printf '%s' "$s" | tr '\t\r\n' '   ' | tr -d '\000-\010\013\014\016-\037\177')
  s=$(trim "$s"); [ -n "$s" ] || s="—"
  printf '%s' "$s"
}
# вивід тестів: R = результат, S = характеристика, M = метадані
res()  { printf 'R\t%s\t%s\t%s\t%s\n' "$1" "$(clean "$2")" "$(clean "$3")" "$(clean "$4")"; }
spec() { printf 'S\t%s\t%s\n' "$(clean "$1")" "$(clean "$2")"; }
meta() { printf 'M\t%s\t%s\n' "$1" "$(clean "$2")"; }
progress() { printf '%s' "$*" > "$WORK/progress" 2>/dev/null; }
rd()   { [ -r "$1" ] && trim "$(tr -d '\000' < "$1" 2>/dev/null | head -c 300)"; }
calc() { awk "BEGIN{printf \"%.${2:-0}f\", ($1)}" 2>/dev/null; }
num()  { printf '%s' "$1" | tr -cd '0-9'; }
bad_serial() { printf '%s' "$1" | grep -Eiq '^(|0+|none|n/?a|default.*|to be filled.*|system serial.*|chassis serial.*|123456789|x{5,})$'; }
now()  {
  local t; t=$(date +%s.%N 2>/dev/null)
  case $t in *N*|"") t=$(perl -MTime::HiRes=time -e 'printf "%.3f", time' 2>/dev/null || date +%s) ;; esac
  printf '%s' "$t"
}
cpu_count() {
  if [ "$OS_KIND" = macos ]; then sysctl -n hw.logicalcpu 2>/dev/null || echo 1
  else nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1; fi
}
jesc() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/</\\u003c/g' -e 's/>/\\u003e/g'; }
safe_name() { printf '%s' "$1" | sed -e 's#[/\\:*?"<>|]#_#g' -e 's/\[/_/g' -e 's/\]/_/g' -e 's/  */ /g' -e 's/^[ .]*//' -e 's/[ .]*$//'; }

# дерево процесів (щоб зупиняти тест разом з усім, що він запустив)
tree_pids() {
  local p=$1 c
  for c in $(ps -A -o pid= -o ppid= 2>/dev/null | awk -v p="$p" '$2==p {print $1}'); do tree_pids "$c"; done
  echo "$p"
}
kill_tree() {
  local pids; pids=$(tree_pids "$1")
  kill -TERM $pids 2>/dev/null; sleep 1; kill -KILL $pids 2>/dev/null
}

# ===================================================================== консоль
add_result() {
  RS[${#RS[@]}]=$1; RC[${#RC[@]}]=$2; RT[${#RT[@]}]=$3; RV[${#RV[@]}]=$4
  case $1 in
    ok)   printf '   %s[ОК]     %s: %s%s\n' "$C_G" "$3" "$4" "$C_0" ;;
    warn) printf '   %s[УВАГА]  %s: %s%s\n' "$C_Y" "$3" "$4" "$C_0" ;;
    fail) printf '   %s[КРИТ]   %s: %s%s\n' "$C_R" "$3" "$4" "$C_0" ;;
    info) printf '   %s[ІНФО]   %s: %s%s\n' "$C_C" "$3" "$4" "$C_0" ;;
    *)    printf '   %s[НЕ ПЕР] %s: %s%s\n' "$C_D" "$3" "$4" "$C_0" ;;
  esac
}
parse_out() {
  local kind a b c d
  while IFS=$'\t' read -r kind a b c d; do
    case $kind in
      R) add_result "$a" "$b" "$c" "$d" ;;
      S) SK[${#SK[@]}]=$a; SV[${#SV[@]}]=$b ;;
      M) [ "$b" = "—" ] && b=""
         case $a in hostname) M_HOST=$b ;; model) M_MODEL=$b ;; serial) M_SERIAL=$b ;; os) M_OS=$b ;; esac ;;
    esac
  done < "$1"
}
on_int() {
  local t; t=$(date +%s)
  if [ $((t - LAST_INT)) -le 2 ]; then
    ABORT=1; printf '\n%s   Тестування перервано — формую звіт з того, що встигли.%s\n' "$C_Y" "$C_0"
  else
    printf '\n%s   Пропускаю… (ще раз Ctrl+C протягом 2 с — перервати все)%s\n' "$C_Y" "$C_0"
  fi
  LAST_INT=$t; SKIP_FLAG=1
}

# Кожен тест — окремий фоновий процес зі своїм лімітом часу.
# Помилка чи зависання одного тесту не зупиняє інші.
run_test() {
  local title=$1 limit=$2 fn=$3
  printf '\n%s%s>> %s%s\n' "$C_C" "$C_B" "$title" "$C_0"
  if [ "$ABORT" = 1 ]; then add_result skip "$title" "Тест не запускався" "тестування перервано"; return; fi
  local out="$WORK/out_$fn" err="$WORK/err_$fn" state="done" start el shown=0 rc before
  : > "$out"; : > "$WORK/progress"; SKIP_FLAG=0
  "$fn" > "$out" 2> "$err" &
  CUR_PID=$!
  start=$(date +%s)
  while kill -0 "$CUR_PID" 2>/dev/null; do
    if [ "$SKIP_FLAG" = 1 ]; then state=skipped; break; fi
    el=$(( $(date +%s) - start ))
    if [ "$el" -ge "$limit" ]; then state=timeout; break; fi
    if [ "$el" -ge 3 ] && [ -t 1 ]; then
      printf '\r   %s%s · %d с · Ctrl+C — пропустити%s\033[K' "$C_D" "$(cat "$WORK/progress" 2>/dev/null)" "$el" "$C_0"
      shown=1
    fi
    sleep 1
  done
  [ "$shown" = 1 ] && printf '\r\033[K'
  [ "$state" != "done" ] && kill_tree "$CUR_PID"
  wait "$CUR_PID" 2>/dev/null; rc=$?
  CUR_PID=""
  before=${#RS[@]}
  parse_out "$out"
  case $state in
    timeout) add_result skip "$title" "Тест не завершився" "перевищено ліміт часу ($limit с)" ;;
    skipped) add_result skip "$title" "Тест пропущено" "пропущено вручну (Ctrl+C)" ;;
  esac
  if [ "$state" = "done" ] && [ "${#RS[@]}" -eq "$before" ]; then
    local e; e=$(head -n 1 "$err" 2>/dev/null)
    add_result skip "$title" "Помилка тесту" "${e:-тест не повернув результатів (код $rc)}"
  fi
}

# ===================================================================== користувач за екраном
xdg_dir() {
  local key=$1 def=$2 f="$CU_HOME/.config/user-dirs.dirs" v=""
  if [ -r "$f" ]; then
    v=$(grep "^XDG_${key}_DIR=" "$f" | head -n 1 | cut -d= -f2- | tr -d '"')
    v=${v/\$HOME/$CU_HOME}
  fi
  if [ -n "$v" ] && [ -d "$v" ]; then printf '%s' "$v"; else printf '%s' "$CU_HOME/$def"; fi
}
detect_user() {
  local s k v name active type remote disp
  if [ "$OS_KIND" = macos ]; then
    CU=$(stat -f%Su /dev/console 2>/dev/null)
    [ "$CU" = root ] && CU=""
  elif has loginctl; then
    for s in $(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}'); do
      name=""; active=""; type=""; remote=""; disp=""
      while IFS='=' read -r k v; do
        case $k in Name) name=$v ;; Active) active=$v ;; Type) type=$v ;; Remote) remote=$v ;; Display) disp=$v ;; esac
      done <<EOF
$(loginctl show-session "$s" -p Name -p Active -p Type -p Remote -p Display 2>/dev/null)
EOF
      if [ "$active" = yes ] && [ "$remote" != yes ] && [ "$name" != root ] && { [ "$type" = x11 ] || [ "$type" = wayland ]; }; then
        CU=$name; CU_DISPLAY=$disp; break
      fi
    done
  fi
  if [ -z "$CU" ] && [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != root ]; then CU=$SUDO_USER; fi
  [ -z "$CU" ] && CU=$(logname 2>/dev/null)
  [ -z "$CU" ] && CU=root
  CU_UID=$(id -u "$CU" 2>/dev/null)
  if [ "$OS_KIND" = macos ]; then
    CU_HOME=$(dscl . -read "/Users/$CU" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
    [ -z "$CU_HOME" ] && CU_HOME="/Users/$CU"
    U_DESKTOP="$CU_HOME/Desktop"; U_DOWNLOADS="$CU_HOME/Downloads"
  else
    CU_HOME=$(getent passwd "$CU" 2>/dev/null | cut -d: -f6)
    [ -z "$CU_HOME" ] && CU_HOME=$(eval "printf '%s' ~$CU" 2>/dev/null)
    U_DESKTOP=$(xdg_dir DESKTOP Desktop); U_DOWNLOADS=$(xdg_dir DOWNLOAD Downloads)
  fi
  [ -d "$U_DESKTOP" ] || U_DESKTOP=$CU_HOME
}
own() { [ "$CU" != root ] && chown "$CU" "$1" 2>/dev/null; }
open_in_browser() {
  local f=$1 rt wl="" s
  if [ "$OS_KIND" = macos ]; then
    if [ "$CU" != root ] && [ -n "$CU_UID" ]; then
      launchctl asuser "$CU_UID" sudo -u "$CU" open "$f" >/dev/null 2>&1 || open "$f" >/dev/null 2>&1
    else open "$f" >/dev/null 2>&1; fi
    return
  fi
  has xdg-open || return 1
  if [ "$CU" = root ] || [ -z "$CU_UID" ]; then xdg-open "$f" >/dev/null 2>&1 & return; fi
  rt="/run/user/$CU_UID"
  for s in "$rt"/wayland-[0-9]; do [ -S "$s" ] && { wl=${s##*/}; break; }; done
  sudo -u "$CU" env DISPLAY="${CU_DISPLAY:-:0}" ${wl:+WAYLAND_DISPLAY=$wl} XDG_RUNTIME_DIR="$rt" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$rt/bus" HOME="$CU_HOME" xdg-open "$f" >/dev/null 2>&1 &
}

# ===================================================================== Linux: тимчасові утиліти
pkg_snapshot() {
  case $PM in
    apt-get) dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 2>/dev/null | awk '$1 ~ /^ii/ {print $2}' ;;
    dnf|yum|zypper) rpm -qa --qf '%{NAME}\n' 2>/dev/null ;;
    pacman) pacman -Qq 2>/dev/null ;;
  esac | LC_ALL=C sort -u
}
# Захист від зависань при встановленні: жодних питань у терміналі,
# очікування, якщо менеджер пакетів зайнятий фоновим оновленням.
pm_env() {
  export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1 APT_LISTCHANGES_FRONTEND=none
}
pm_run() {  # $1 = ліміт секунд, далі команда; stdin закрито, щоб нічого не чекало відповіді
  local limit=$1; shift
  if has timeout && timeout --foreground 1 true 2>/dev/null; then
    timeout --foreground "$limit" "$@" </dev/null
  elif has timeout; then
    timeout "$limit" "$@" </dev/null
  else
    "$@" </dev/null
  fi
}
apt_busy() { pgrep -x 'apt|apt-get|dpkg|unattended-upgr|packagekitd' >/dev/null 2>&1; }
APT_OPTS="-o DPkg::Lock::Timeout=300 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

linux_prepare_tools() {
  local need="" pair p ok="" bad="" waited=0
  for p in apt-get dnf yum zypper pacman; do has "$p" && { PM=$p; break; }; done
  for pair in smartctl:smartmontools dmidecode:dmidecode lspci:pciutils lsusb:usbutils; do
    has "${pair%%:*}" || need="$need ${pair#*:}"
  done
  need=$(trim "$need")
  if [ -z "$need" ]; then echo "   Усі потрібні утиліти вже встановлені — нічого ставити не треба."; return 0; fi
  if [ -z "$PM" ]; then echo "   ${C_Y}Не знайдено менеджер пакетів — частина перевірок буде пропущена.${C_0}"; return 0; fi
  echo "   Потрібно тимчасово встановити: $need"
  echo "   ${C_D}(після тестів вони будуть видалені автоматично)${C_0}"
  pm_env
  pkg_snapshot > "$WORK/pk_before"
  : > "$WORK/pm.log"

  if [ "$PM" = apt-get ]; then
    while apt_busy && [ "$waited" -lt 300 ]; do
      [ "$waited" = 0 ] && echo "   ${C_Y}Менеджер пакетів зайнятий (фонове оновлення системи) — чекаю до 5 хв…${C_0}"
      sleep 5; waited=$((waited + 5))
    done
    printf '   Оновлюю список пакетів… '
    if pm_run 300 apt-get $APT_OPTS update -qq >>"$WORK/pm.log" 2>&1; then echo "${C_G}ок${C_0}"; else echo "${C_Y}з помилками (пробую далі)${C_0}"; fi
  fi

  # По одному пакету: якщо якогось немає, решта все одно поставиться.
  for p in $need; do
    printf '   Встановлюю %s… ' "$p"
    case $PM in
      apt-get) pm_run 600 apt-get $APT_OPTS install -y -q --no-install-recommends "$p" >>"$WORK/pm.log" 2>&1 ;;
      dnf)     pm_run 600 dnf install -y -q --setopt=install_weak_deps=False "$p" >>"$WORK/pm.log" 2>&1 ;;
      yum)     pm_run 600 yum install -y -q "$p" >>"$WORK/pm.log" 2>&1 ;;
      zypper)  pm_run 600 zypper --non-interactive --quiet install --no-recommends "$p" >>"$WORK/pm.log" 2>&1 ;;
      pacman)  pm_run 600 pacman -S --noconfirm --needed "$p" >>"$WORK/pm.log" 2>&1 ;;
    esac
    if [ $? -eq 0 ]; then echo "${C_G}ок${C_0}"; ok="$ok $p"; else echo "${C_Y}не вдалося${C_0}"; bad="$bad $p"; fi
  done

  pkg_snapshot > "$WORK/pk_after"
  INSTALLED=$(LC_ALL=C comm -13 "$WORK/pk_before" "$WORK/pk_after" | tr '\n' ' ')
  INSTALLED=$(trim "$INSTALLED")
  [ -n "$INSTALLED" ] && echo "   ${C_G}Встановлено тимчасово (з залежностями): $INSTALLED${C_0}"
  if [ -n "$(trim "$bad")" ]; then
    echo "   ${C_Y}Не вдалося встановити:$bad — ці перевірки будуть позначені «не вдалося перевірити».${C_0}"
    echo "   ${C_D}Причина (останні рядки журналу менеджера пакетів):${C_0}"
    grep -Ei 'error|помилк|unable|could not|failed|E:' "$WORK/pm.log" | tail -n 4 | sed 's/^/     /'
    if grep -q 'dpkg --configure -a' "$WORK/pm.log"; then
      echo "   ${C_Y}Підказка: система має незавершене оновлення. Виконайте «sudo dpkg --configure -a» і запустіть тест ще раз.${C_0}"
    fi
  fi
  return 0
}
linux_remove_tools() {
  [ -n "$INSTALLED" ] || return 0
  local list=$INSTALLED left
  INSTALLED=""
  echo "   Видаляю тимчасово встановлені утиліти: $list"
  pm_env
  case $PM in
    apt-get) pm_run 600 apt-get $APT_OPTS purge -y -q $list >"$WORK/pm_rm.log" 2>&1 ;;
    dnf)     pm_run 600 dnf remove -y -q --noautoremove $list >"$WORK/pm_rm.log" 2>&1 || pm_run 600 dnf remove -y -q $list >>"$WORK/pm_rm.log" 2>&1 ;;
    yum)     pm_run 600 yum remove -y -q $list >"$WORK/pm_rm.log" 2>&1 ;;
    zypper)  pm_run 600 zypper --non-interactive --quiet remove $list >"$WORK/pm_rm.log" 2>&1 ;;
    pacman)  pm_run 600 pacman -Rn --noconfirm $list >"$WORK/pm_rm.log" 2>&1 ;;
  esac
  printf '%s\n' $list | LC_ALL=C sort -u > "$WORK/pk_ours"
  left=$(pkg_snapshot | LC_ALL=C comm -12 "$WORK/pk_ours" - | tr '\n' ' ')
  left=$(trim "$left")
  if [ -z "$left" ]; then echo "   ${C_G}Видалено. Система в тому стані, що й до тесту.${C_0}"
  else echo "   ${C_Y}Не вдалося видалити: $left — видаліть їх вручну через менеджер пакетів.${C_0}"; fi
}

# ===================================================================== тести Linux
t_system_linux() {
  local d=/sys/class/dmi/id vendor product version serial model host os bios bdate v
  vendor=$(rd $d/sys_vendor); product=$(rd $d/product_name); version=$(rd $d/product_version)
  serial=$(rd $d/product_serial)
  if bad_serial "$serial" && has dmidecode; then serial=$(trim "$(dmidecode -s system-serial-number 2>/dev/null | head -n 1)"); fi
  bad_serial "$serial" && serial=$(rd $d/board_serial)
  bad_serial "$serial" && serial=""
  model=$(trim "$vendor $product")
  if [ -n "$version" ] && ! printf '%s' "$version" | grep -Eiq 'none|default|to be filled|system version|^0$'; then
    case $model in *"$version"*) ;; *) model="$model ($version)" ;; esac
  fi
  host=$(hostname 2>/dev/null || uname -n)
  os=$( . /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-Linux}")
  meta hostname "$host"; meta model "$model"; meta serial "$serial"; meta os "$os"
  spec "Назва ПК" "$host"; spec "Модель" "$model"
  spec "Серійний номер" "${serial:-не вказано виробником}"
  bios=$(rd $d/bios_version); bdate=$(rd $d/bios_date)
  spec "BIOS / UEFI" "$(rd $d/bios_vendor) $bios ${bdate:+від $bdate}"
  spec "Операційна система" "$os, ядро $(uname -r), $(uname -m)"
  if [ -n "$serial" ]; then res ok "Система" "Серійний номер" "$serial"
  else res warn "Система" "Серійний номер" "виробник не прописав серійний номер у BIOS"; fi
  if [ -d /sys/firmware/efi ]; then
    local sb f
    f=$(ls /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | head -n 1)
    sb=""; [ -n "$f" ] && sb=$(od -An -t u1 -j4 -N1 "$f" 2>/dev/null | tr -d ' ')
    case $sb in 1) spec "Режим завантаження" "UEFI, Secure Boot увімкнено" ;; 0) spec "Режим завантаження" "UEFI, Secure Boot вимкнено" ;; *) spec "Режим завантаження" "UEFI" ;; esac
  else spec "Режим завантаження" "Legacy BIOS"; fi
  if [ -e /sys/class/tpm/tpm0 ]; then
    v=$(rd /sys/class/tpm/tpm0/tpm_version_major)
    res ok "Система" "TPM" "є${v:+, версія $v.x}"
  else res warn "Система" "TPM" "не знайдено або вимкнено в BIOS"; fi
}

t_hw_linux() {
  local cpu cores threads maxf mem line slots inst gpu drv n=0 c st name
  cpu=$(grep -m1 -E '^model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2-)
  [ -z "$cpu" ] && has lscpu && cpu=$(lscpu 2>/dev/null | grep -m1 'Model name' | cut -d: -f2-)
  cpu=$(trim "$cpu"); threads=$(cpu_count)
  cores=$(lscpu -p=core 2>/dev/null | grep -v '^#' | sort -u | wc -l | tr -d ' ')
  maxf=$(rd /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq)
  spec "Процесор" "${cpu:-невідомо}"
  spec "Ядра / потоки" "${cores:-?} / $threads"
  [ -n "$maxf" ] && spec "Максимальна частота" "$((maxf / 1000)) МГц"
  if [ -n "$cpu" ]; then res ok "Процесор" "Процесор" "$cpu"; else res skip "Процесор" "Процесор" "не вдалося визначити"; fi

  mem=$(awk '/^MemTotal:/ {printf "%.1f", $2/1048576}' /proc/meminfo 2>/dev/null)
  slots=""; inst=""
  if has dmidecode; then
    dmidecode -t 17 2>/dev/null | awk '
      function flush() { if (have && size != "" && size !~ /No Module|Not Installed|Unknown|^0/) { inst++; printf "M\t%s %s %s %s\n", size, type, speed, man } }
      /^Memory Device/ { flush(); have=1; slots++; size=""; type=""; speed=""; man=""; next }
      /^[ \t]+Size:/ { sub(/^[ \t]+Size: */, ""); size=$0 }
      /^[ \t]+Type:/ { sub(/^[ \t]+Type: */, ""); type=$0 }
      /^[ \t]+Speed:/ { if (speed == "") { sub(/^[^:]+: */, ""); speed=$0 } }
      /^[ \t]+Configured (Memory|Clock) Speed:/ { sub(/^[^:]+: */, ""); if ($0 !~ /Unknown/) speed=$0 }
      /^[ \t]+Manufacturer:/ { sub(/^[^:]+: */, ""); man=$0 }
      END { flush(); printf "T\t%d\t%d\n", slots, inst }' > "$WORK/mem.txt"
    while IFS=$'\t' read -r c line st; do
      case $c in M) n=$((n+1)); spec "Модуль пам'яті $n" "$line" ;; T) slots=$line; inst=$st ;; esac
    done < "$WORK/mem.txt"
  fi
  if [ -n "$mem" ]; then
    if [ -n "$slots" ] && [ "$slots" != 0 ]; then
      spec "Оперативна пам'ять" "$mem ГБ доступно системі, зайнято слотів: $inst з $slots"
      res ok "Пам'ять" "Оперативна пам'ять" "$mem ГБ, зайнято слотів: $inst з $slots"
    else
      spec "Оперативна пам'ять" "$mem ГБ доступно системі"
      res ok "Пам'ять" "Оперативна пам'ять" "$mem ГБ"
    fi
  else res skip "Пам'ять" "Оперативна пам'ять" "не вдалося визначити"; fi

  if has lspci; then
    n=0
    while IFS=$'\t' read -r gpu drv; do
      [ -z "$gpu" ] && continue; n=$((n+1))
      spec "Відеоадаптер" "$gpu${drv:+, драйвер $drv}"
      if [ "$drv" = "-" ]; then res warn "Відео" "Відеоадаптер" "$gpu — драйвер не завантажено"
      else res ok "Відео" "Відеоадаптер" "$gpu (драйвер $drv)"; fi
    done <<EOF
$(lspci -k 2>/dev/null | awk '
  /^[0-9a-f]/ { if (dev != "") print dev "\t" (drv == "" ? "-" : drv); dev=""; drv=""
               if ($0 ~ /(VGA compatible|3D controller|Display controller)/) { sub(/^[^ ]+ [^:]+: /, ""); dev=$0 }; next }
  /Kernel driver in use:/ { if (dev != "") { sub(/.*: /, ""); drv=$0 } }
  END { if (dev != "") print dev "\t" (drv == "" ? "-" : drv) }')
EOF
    [ "$n" = 0 ] && res fail "Відео" "Відеоадаптер" "не знайдено"
  else
    res skip "Відео" "Відеоадаптер" "утиліта lspci недоступна"
  fi

  local found="" conn mode
  for c in /sys/class/drm/card*-*; do
    [ -e "$c/status" ] || continue
    name=${c##*/}; name=${name#card*-}
    st=$(rd "$c/status")
    case $name in
      eDP*|LVDS*|DSI*)
        mode=$(head -n 1 "$c/modes" 2>/dev/null)
        if [ "$st" = connected ]; then found=ok; spec "Вбудований дисплей" "$name${mode:+, $mode}"
        elif [ -z "$found" ]; then found=off; fi ;;
      *) [ "$st" = connected ] && spec "Зовнішній дисплей" "$name, $(head -n 1 "$c/modes" 2>/dev/null)" ;;
    esac
  done
  case $found in
    ok)  res ok "Відео" "Вбудований дисплей" "визначається системою" ;;
    off) res warn "Відео" "Вбудований дисплей" "роз'єм є, але дисплей не визначається (кришка закрита або шлейф?)" ;;
    *)   res skip "Відео" "Вбудований дисплей" "не вдалося визначити (немає даних DRM)" ;;
  esac
}

smart_one() {  # $1 = /dev/xxx, $2 = назва
  local dev=$1 nm=$2 h a pct temp poh merr crit realloc pend unc wear
  h=$(smartctl -H "$dev" 2>&1)
  if printf '%s' "$h" | grep -Eq 'PASSED|: OK'; then res ok "Диск" "$nm — стан SMART" "справний (PASSED)"
  elif printf '%s' "$h" | grep -q 'FAILED'; then res fail "Диск" "$nm — стан SMART" "SMART повідомляє про несправність (FAILED)"
  else res skip "Диск" "$nm — стан SMART" "диск не віддає дані SMART"; return; fi
  a=$(smartctl -A "$dev" 2>/dev/null)
  case $dev in
    *nvme*)
      pct=$(printf '%s\n' "$a" | awk -F: '/Percentage Used/ {gsub(/[^0-9]/, "", $2); print $2; exit}')
      temp=$(printf '%s\n' "$a" | awk '/^Temperature:/ {print $2; exit}')
      poh=$(printf '%s\n' "$a" | awk -F: '/Power On Hours/ {gsub(/[^0-9]/, "", $2); print $2; exit}')
      merr=$(printf '%s\n' "$a" | awk -F: '/Media and Data Integrity Errors/ {gsub(/[^0-9]/, "", $2); print $2; exit}')
      crit=$(printf '%s\n' "$a" | awk -F: '/Critical Warning/ {gsub(/[ \t]/, "", $2); print $2; exit}')
      [ -n "$crit" ] && [ "$crit" != "0x00" ] && res fail "Диск" "$nm — критичне попередження" "NVMe Critical Warning = $crit"
      if [ -n "$merr" ]; then
        if [ "$merr" -gt 0 ]; then res fail "Диск" "$nm — помилки" "помилок цілісності даних: $merr"
        else res ok "Диск" "$nm — помилки" "помилок цілісності даних немає"; fi
      fi ;;
    *)
      realloc=$(printf '%s\n' "$a" | awk '$1==5   {print $10; exit}')
      pend=$(printf '%s\n' "$a"    | awk '$1==197 {print $10; exit}')
      unc=$(printf '%s\n' "$a"     | awk '$1==198 {print $10; exit}')
      poh=$(printf '%s\n' "$a"     | awk '$1==9   {print $10; exit}' | sed 's/[^0-9].*//')
      temp=$(printf '%s\n' "$a"    | awk '$1==194 || $1==190 {print $10; exit}')
      wear=$(printf '%s\n' "$a"    | awk '$1==177 || $1==202 || $1==231 || $1==233 {print $4+0; exit}')
      [ -n "$wear" ] && pct=$((100 - wear))
      realloc=$(num "$realloc"); pend=$(num "$pend"); unc=$(num "$unc")
      if [ -n "$pend$unc" ] && { [ "${pend:-0}" -gt 0 ] || [ "${unc:-0}" -gt 0 ]; }; then
        res fail "Диск" "$nm — нестабільні сектори" "очікують перепризначення: ${pend:-0}, невиправних: ${unc:-0}"
      fi
      if [ -n "$realloc" ]; then
        if [ "$realloc" -gt 100 ]; then res fail "Диск" "$nm — перепризначені сектори" "$realloc"
        elif [ "$realloc" -gt 0 ]; then res warn "Диск" "$nm — перепризначені сектори" "$realloc (диск почав сипатися)"
        else res ok "Диск" "$nm — перепризначені сектори" "немає"; fi
      fi ;;
  esac
  if [ -n "$pct" ]; then
    if [ "$pct" -ge 90 ]; then res fail "Диск" "$nm — знос" "використано $pct% ресурсу"
    elif [ "$pct" -ge 70 ]; then res warn "Диск" "$nm — знос" "використано $pct% ресурсу"
    else res ok "Диск" "$nm — знос" "використано $pct% ресурсу"; fi
  fi
  temp=$(num "$temp")
  if [ -n "$temp" ]; then
    if [ "$temp" -ge 75 ]; then res warn "Диск" "$nm — температура" "$temp °C"; else res ok "Диск" "$nm — температура" "$temp °C"; fi
  fi
  [ -n "$poh" ] && spec "Диск: $nm — напрацювання" "$poh год"
}

t_disks_linux() {
  local name type rota size tran model kind nm n=0 line free total pct
  while read -r name type rota size tran model; do
    [ "$type" = disk ] || continue
    case $name in loop*|zram*|ram*|sr*|fd*|mmcblk*boot*|dm-*|md*) continue ;; esac
    n=$((n+1))
    case $name in nvme*) kind="NVMe SSD" ;; *) if [ "$rota" = 1 ]; then kind="HDD"; else kind="SSD"; fi ;; esac
    nm=$(trim "${model:-$name}")
    spec "Диск: $nm" "/dev/$name, $kind, $size${tran:+, $tran}"
    progress "SMART $name"
    if has smartctl; then smart_one "/dev/$name" "$nm"
    else res skip "Диск" "$nm — стан SMART" "утиліта smartctl недоступна"; fi
  done <<EOF
$(lsblk -dn -o NAME,TYPE,ROTA,SIZE,TRAN,MODEL 2>/dev/null)
EOF
  [ "$n" = 0 ] && res fail "Диск" "Накопичувачі" "не знайдено жодного диска"
  line=$(df -Pk / 2>/dev/null | awk 'NR==2 {print $2, $4}')
  if [ -n "$line" ]; then
    total=${line% *}; free=${line#* }
    pct=$((free * 100 / total))
    if [ "$pct" -lt 10 ]; then st=warn; else st=ok; fi
    res "$st" "Диск" "Вільне місце на /" "$(calc "$free/1048576" 1) з $(calc "$total/1048576" 1) ГБ ($pct%)"
  fi
}

t_battery_linux() {
  local b found=0 full design cyc cap st unit h p ac=""
  for b in /sys/class/power_supply/*; do
    [ "$(rd "$b/type")" = Battery ] || continue
    [ "$(rd "$b/scope")" = Device ] && continue
    found=$((found+1))
    full=$(rd "$b/energy_full"); design=$(rd "$b/energy_full_design"); unit="Вт·год"
    if [ -z "$full" ]; then full=$(rd "$b/charge_full"); design=$(rd "$b/charge_full_design"); unit="А·год"; fi
    spec "Батарея ${b##*/}" "$(rd "$b/manufacturer") $(rd "$b/model_name") $(rd "$b/technology")"
    if [ -n "$design" ] && [ "$design" -gt 0 ] 2>/dev/null && [ -n "$full" ]; then
      h=$((full * 100 / design))
      if [ "$h" -lt 50 ]; then st=fail; elif [ "$h" -lt 75 ]; then st=warn; else st=ok; fi
      res "$st" "Батарея" "Стан батареї" "$h% від заводської ємності ($(calc "$full/1000000" 1) з $(calc "$design/1000000" 1) $unit)"
    else res skip "Батарея" "Стан батареї" "батарея не повідомляє ємність"; fi
    cyc=$(rd "$b/cycle_count")
    if [ -n "$cyc" ] && [ "$cyc" -gt 0 ] 2>/dev/null; then
      if [ "$cyc" -gt 800 ]; then res warn "Батарея" "Цикли заряду" "$cyc"; else res ok "Батарея" "Цикли заряду" "$cyc"; fi
    fi
    cap=$(rd "$b/capacity"); [ -n "$cap" ] && spec "Поточний заряд" "$cap% ($(rd "$b/status"))"
  done
  if [ "$found" = 0 ]; then res fail "Батарея" "Батарея" "не знайдена (відсутня, від'єднана або несправна)"; return; fi
  for p in /sys/class/power_supply/*; do
    [ "$(rd "$p/type")" = Mains ] || continue
    [ "$(rd "$p/online")" = 1 ] && ac=1 || ac=${ac:-0}
  done
  case $ac in
    1) res ok "Батарея" "Зарядний пристрій" "підключено" ;;
    0) res warn "Батарея" "Зарядний пристрій" "не підключено — перевірте зарядку вручну" ;;
    *) res skip "Батарея" "Зарядний пристрій" "не вдалося визначити" ;;
  esac
}

rfkill_state() {  # $1 = wlan|bluetooth → hard|soft|""
  local r
  for r in /sys/class/rfkill/rfkill*; do
    [ "$(rd "$r/type")" = "$1" ] || continue
    [ "$(rd "$r/hard")" = 1 ] && { echo hard; return; }
    [ "$(rd "$r/soft")" = 1 ] && { echo soft; return; }
  done
}
t_net_linux() {
  local i n drv wifi=0 eth=0 st rf
  for i in /sys/class/net/*; do
    n=${i##*/}; [ "$n" = lo ] && continue
    [ -e "$i/device" ] || continue
    drv=$(basename "$(readlink "$i/device/driver" 2>/dev/null)" 2>/dev/null)
    st=$(rd "$i/operstate")
    if [ -d "$i/wireless" ] || [ -d "$i/phy80211" ]; then
      wifi=$((wifi+1)); spec "Wi-Fi" "$n${drv:+, драйвер $drv}, MAC $(rd "$i/address")"
      res ok "Мережа" "Wi-Fi" "$n${drv:+ ($drv)}, стан: $st"
    elif [ "$(rd "$i/type")" = 1 ]; then
      eth=$((eth+1)); spec "Ethernet" "$n${drv:+, драйвер $drv}, MAC $(rd "$i/address")"
      res ok "Мережа" "Ethernet" "$n${drv:+ ($drv)}, стан: $st"
    fi
  done
  rf=$(rfkill_state wlan)
  [ "$rf" = hard ] && res warn "Мережа" "Wi-Fi вимкнено" "апаратно (перемикач або клавіша Fn)"
  [ "$rf" = soft ] && res warn "Мережа" "Wi-Fi вимкнено" "програмно (режим «у літаку» або налаштування)"
  if [ "$wifi" = 0 ]; then
    if has lspci && lspci 2>/dev/null | grep -Eiq 'network controller|wireless'; then
      res fail "Мережа" "Wi-Fi" "адаптер є, але не працює (немає драйвера?): $(lspci | grep -Ei 'network controller' | head -n 1 | sed 's/^[^:]*: [^:]*: //')"
    else res fail "Мережа" "Wi-Fi" "адаптер Wi-Fi не знайдено"; fi
  fi
  [ "$eth" = 0 ] && spec "Ethernet" "немає вбудованого порту"
  if ls /sys/class/bluetooth/hci* >/dev/null 2>&1; then
    rf=$(rfkill_state bluetooth)
    case $rf in hard|soft) res warn "Мережа" "Bluetooth" "адаптер є, але вимкнено ($rf)" ;; *) res ok "Мережа" "Bluetooth" "адаптер працює" ;; esac
  else res warn "Мережа" "Bluetooth" "адаптер не знайдено або вимкнено"; fi
}

t_periph_linux() {
  local cams cards play capt kb tp n
  cams=$(cat /sys/class/video4linux/video*/name 2>/dev/null | grep -Eiv 'metadata|IR |infrared' | sort -u | tr '\n' ';' | sed 's/;$//; s/;/; /g')
  if [ -n "$cams" ]; then res ok "Периферія" "Вебкамера" "$cams"
  else res warn "Периферія" "Вебкамера" "не знайдена (вимкнена клавішею/шторкою, у BIOS або несправна)"; fi
  cards=$(awk -F'- ' '/^ *[0-9]+ \[/ {print $2}' /proc/asound/cards 2>/dev/null | tr '\n' ';' | sed 's/;$//; s/;/; /g')
  play=$(ls -d /proc/asound/card*/pcm*p 2>/dev/null | wc -l | tr -d ' ')
  capt=$(ls -d /proc/asound/card*/pcm*c 2>/dev/null | wc -l | tr -d ' ')
  [ -n "$cards" ] && spec "Звукові карти" "$cards"
  if [ "${play:-0}" -gt 0 ]; then res ok "Периферія" "Вихід звуку (пристрій)" "${cards:-є}"
  elif [ -n "$cards" ]; then res warn "Периферія" "Вихід звуку (пристрій)" "звукова карта є, але вихід не знайдено"
  else res fail "Периферія" "Вихід звуку (пристрій)" "звукову карту не знайдено"; fi
  if [ "${capt:-0}" -gt 0 ]; then res ok "Периферія" "Мікрофон" "пристрій запису є"
  else res warn "Периферія" "Мікрофон" "пристрій запису не знайдено"; fi
  kb=$(awk -F'"' '/^N: Name=/ {print $2}' /proc/bus/input/devices 2>/dev/null | grep -Ei 'keyboard' | grep -Eiv 'video bus|power|sleep|button|consumer|system control|hotkey' | head -n 1)
  tp=$(awk -F'"' '/^N: Name=/ {print $2}' /proc/bus/input/devices 2>/dev/null | grep -Ei 'touchpad|trackpad|synaptics|glidepoint|alps|elan.*(pad|0[0-9a-f]{3})' | head -n 1)
  [ -n "$kb" ] && spec "Клавіатура" "$kb"
  if [ -n "$tp" ]; then res ok "Периферія" "Тачпад (пристрій)" "$tp"
  else res warn "Периферія" "Тачпад (пристрій)" "тачпад не визначено як окремий пристрій — перевірте в ручному тесті"; fi
  if has lsusb; then
    n=$(lsusb 2>/dev/null | grep -vc 'root hub')
    spec "USB-пристрої" "підключено: $n"
    lsusb 2>/dev/null | grep -Eiq 'fingerprint|fprint|goodix|validity|synaptics.*(fp|fingerprint)' && spec "Сканер відбитків" "$(lsusb | grep -Ei 'fingerprint|fprint|goodix|validity' | head -n 1 | cut -d' ' -f7-)"
  fi
  if has lspci; then
    n=$(lspci 2>/dev/null | grep -c 'USB controller')
    [ "$n" -gt 0 ] && res ok "Периферія" "USB-контролери" "знайдено: $n"
    lspci 2>/dev/null | grep -Eiq 'card reader|SD Host' && spec "Кардрідер" "$(lspci | grep -Ei 'card reader|SD Host' | head -n 1 | sed 's/^[^:]*: //')"
  fi
}

t_drivers_linux() {
  if ! has lspci; then res skip "Драйвери" "Драйвери пристроїв" "утиліта lspci недоступна"; return; fi
  local dev cnt=0
  while IFS= read -r dev; do
    [ -z "$dev" ] && continue
    cnt=$((cnt+1)); res warn "Драйвери" "$dev" "драйвер не завантажено"
  done <<EOF
$(lspci -k 2>/dev/null | awk '
  /^[0-9a-f]/ { if (dev != "" && !drv) print dev; dev=""; drv=0
               if ($0 ~ /(VGA|3D controller|Display|Network|Ethernet|Wireless|Audio device|Multimedia audio|USB controller|SATA|Non-Volatile|RAID|SD Host|Bluetooth)/) { sub(/^[^ ]+ /, ""); dev=$0 }; next }
  /Kernel driver in use:/ { drv=1 }
  END { if (dev != "" && !drv) print dev }')
EOF
  [ "$cnt" = 0 ] && res ok "Драйвери" "Драйвери пристроїв" "усі ключові пристрої мають драйвер"
}

t_logs_linux() {
  local log n
  log=$(dmesg 2>/dev/null); [ -z "$log" ] && has journalctl && log=$(journalctl -k -b --no-pager 2>/dev/null)
  if [ -z "$log" ]; then res skip "Журнал ядра" "Журнал ядра" "журнал недоступний"; return; fi
  n=$(printf '%s\n' "$log" | grep -Eic 'I/O error|Buffer I/O error|ata[0-9.]+: (failed command|exception Emask)|nvme[0-9]+: .*(timeout|controller is down)|medium error')
  if [ "$n" -ge 10 ]; then res fail "Журнал ядра" "Помилки диска (з моменту запуску)" "$n записів про збої читання/запису"
  elif [ "$n" -gt 0 ]; then res warn "Журнал ядра" "Помилки диска (з моменту запуску)" "$n записів про збої читання/запису"
  else res ok "Журнал ядра" "Помилки диска (з моменту запуску)" "не було"; fi
  n=$(printf '%s\n' "$log" | grep -Eic 'Hardware Error|Machine check|mce: \[')
  if [ "$n" -gt 0 ]; then res warn "Журнал ядра" "Апаратні помилки (MCE)" "$n записів"
  else res ok "Журнал ядра" "Апаратні помилки (MCE)" "не було"; fi
  n=$(printf '%s\n' "$log" | grep -Eic 'temperature above threshold|clock throttled|critical temperature')
  if [ "$n" -gt 0 ]; then res warn "Журнал ядра" "Перегрів (з моменту запуску)" "$n записів про перегрів або скидання частоти"
  else res ok "Журнал ядра" "Перегрів (з моменту запуску)" "не було"; fi
}

# ===================================================================== тести macOS
sp_get() {  # stdin = вивід system_profiler, $1 = назва поля
  awk -v k="$1" '{ line=$0; sub(/^[ \t]+/, "", line); i=index(line, ": "); if (i > 0 && substr(line, 1, i-1) == k) { print substr(line, i+2); exit } }'
}
# ---------------------------------------------------------------- обліковий запис (найважливіше, вгорі звіту)
ACC="Обліковий запис"
PLISTBUDDY=${PLISTBUDDY:-/usr/libexec/PlistBuddy}
mask_email() {  # j***@icloud.com — достатньо, щоб упізнати, без повної адреси
  local e=$1 u d
  case $e in
    *@*) u=${e%%@*}; d=${e#*@}; printf '%s***@%s' "$(printf '%s' "$u" | cut -c1-2)" "$d" ;;
    *)   printf '%s***' "$(printf '%s' "$e" | cut -c1-2)" ;;
  esac
}
t_account_mac() {
  local users u home role plist id logged n=0 signed=0 act fv mdm dep enr
  # Усі звичайні облікові записи на цьому Mac (і адміни, і стандартні).
  users=$(dscl . -list /Users UniqueID 2>/dev/null | awk '$2 >= 501 && $1 !~ /^_/ {print $1}')
  for u in $users; do
    home=$(dscl . -read "/Users/$u" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
    [ -n "$home" ] && [ -d "$home" ] || continue
    n=$((n+1))
    if dseditgroup -o checkmember -m "$u" admin >/dev/null 2>&1; then role="адмін"; else role="стандартний"; fi
    plist="$home/Library/Preferences/MobileMeAccounts.plist"
    if [ ! -e "$plist" ]; then
      res ok "$ACC" "iCloud — $u ($role)" "не увійдено"
      continue
    fi
    if ! "$PLISTBUDDY" -c 'Print' "$plist" >/dev/null 2>&1; then
      res skip "$ACC" "iCloud — $u ($role)" "не вдалося прочитати налаштування iCloud цього користувача"
      continue
    fi
    id=$("$PLISTBUDDY" -c 'Print :Accounts:0:AccountID' "$plist" 2>/dev/null)
    logged=$("$PLISTBUDDY" -c 'Print :Accounts:0:LoggedIn' "$plist" 2>/dev/null)
    if [ -n "$id" ] && [ "$logged" != false ]; then
      signed=$((signed+1))
      res fail "$ACC" "iCloud — $u ($role)" "УВІЙДЕНО: $(mask_email "$id") — перед передачею Mac вийдіть з iCloud у цьому обліковому записі"
    else
      res ok "$ACC" "iCloud — $u ($role)" "не увійдено"
    fi
  done
  [ "$n" = 0 ] && res skip "$ACC" "iCloud" "не знайдено облікових записів користувачів"

  # «Знайти Mac» тримає токен у NVRAM, поки функція увімкнена.
  if nvram fmm-mobileme-token-FMM >/dev/null 2>&1; then
    res fail "$ACC" "Знайти Mac" "УВІМКНЕНО — Mac прив'язаний до Apple ID; вимкніть у налаштуваннях iCloud"
  else
    res ok "$ACC" "Знайти Mac" "вимкнено"
  fi

  act=$(system_profiler SPHardwareDataType 2>/dev/null | sp_get "Activation Lock Status")
  case $act in
    Enabled*)  res fail "$ACC" "Блокування активації" "УВІМКНЕНО — без пароля Apple ID цей Mac не можна буде налаштувати заново" ;;
    Disabled*) res ok "$ACC" "Блокування активації" "вимкнено" ;;
    *)         res info "$ACC" "Блокування активації" "цей Mac не підтримує блокування активації (немає чипа T2 / Apple)" ;;
  esac

  fv=$(fdesetup status 2>/dev/null | head -n 1)
  case $fv in
    *"is On"*)  res info "$ACC" "FileVault" "увімкнено — диск зашифровано" ;;
    *"is Off"*) res info "$ACC" "FileVault" "вимкнено — диск не зашифровано" ;;
    "")         res skip "$ACC" "FileVault" "не вдалося перевірити" ;;
    *)          res info "$ACC" "FileVault" "$fv" ;;
  esac

  enr=$(profiles status -type enrollment 2>/dev/null)
  dep=$(printf '%s\n' "$enr" | awk -F': ' '/Enrolled via DEP/ {print $2; exit}')
  mdm=$(printf '%s\n' "$enr" | awk -F': ' '/MDM enrollment/ {print $2; exit}')
  if [ -z "$enr" ]; then res skip "$ACC" "Керування організацією (MDM)" "не вдалося перевірити"
  else
    case "$dep$mdm" in
      *Yes*) res info "$ACC" "Керування організацією (MDM)" "КЕРУЄТЬСЯ: MDM — ${mdm:-?}, через Apple Business Manager (DEP) — ${dep:-?}" ;;
      *)     res info "$ACC" "Керування організацією (MDM)" "не керується (MDM: ${mdm:-No}, DEP: ${dep:-No})" ;;
    esac
  fi
}

t_system_mac() {
  local hw host model ident serial fw os sip
  hw=$(system_profiler SPHardwareDataType 2>/dev/null)
  host=$(scutil --get ComputerName 2>/dev/null || hostname)
  model=$(printf '%s\n' "$hw" | sp_get "Model Name"); ident=$(printf '%s\n' "$hw" | sp_get "Model Identifier")
  serial=$(printf '%s\n' "$hw" | sp_get "Serial Number (system)")
  bad_serial "$serial" && serial=""
  fw=$(printf '%s\n' "$hw" | sp_get "System Firmware Version")
  os="macOS $(sw_vers -productVersion 2>/dev/null) ($(sw_vers -buildVersion 2>/dev/null))"
  meta hostname "$host"; meta model "$model${ident:+ ($ident)}"; meta serial "$serial"; meta os "$os"
  spec "Назва ПК" "$host"; spec "Модель" "$model${ident:+ ($ident)}"
  spec "Серійний номер" "${serial:-не вдалося прочитати}"
  [ -n "$fw" ] && spec "Прошивка" "$fw"
  spec "Операційна система" "$os, $(uname -m)"
  if [ -n "$serial" ]; then res ok "Система" "Серійний номер" "$serial"; else res warn "Система" "Серійний номер" "не вдалося прочитати"; fi
  sip=$(csrutil status 2>/dev/null)
  case $sip in
    *enabled*)  res ok "Система" "Захист цілісності системи (SIP)" "увімкнено" ;;
    *disabled*) res warn "Система" "Захист цілісності системи (SIP)" "вимкнено" ;;
  esac
}

t_hw_mac() {
  local hw chip cores mem gpu disp
  hw=$(system_profiler SPHardwareDataType 2>/dev/null)
  chip=$(printf '%s\n' "$hw" | sp_get "Chip"); [ -z "$chip" ] && chip="$(printf '%s\n' "$hw" | sp_get "Processor Name") $(printf '%s\n' "$hw" | sp_get "Processor Speed")"
  cores=$(printf '%s\n' "$hw" | sp_get "Total Number of Cores")
  mem=$(printf '%s\n' "$hw" | sp_get "Memory")
  chip=$(trim "$chip")
  spec "Процесор" "$chip"; [ -n "$cores" ] && spec "Ядра" "$cores"; spec "Оперативна пам'ять" "$mem"
  if [ -n "$chip" ]; then res ok "Процесор" "Процесор" "$chip"; else res skip "Процесор" "Процесор" "не вдалося визначити"; fi
  if [ -n "$mem" ]; then res ok "Пам'ять" "Оперативна пам'ять" "$mem"; else res skip "Пам'ять" "Оперативна пам'ять" "не вдалося визначити"; fi
  disp=$(system_profiler SPDisplaysDataType 2>/dev/null)
  gpu=$(printf '%s\n' "$disp" | sp_get "Chipset Model")
  if [ -n "$gpu" ]; then res ok "Відео" "Відеоадаптер" "$gpu"; spec "Відеоадаптер" "$gpu"
  else res skip "Відео" "Відеоадаптер" "не вдалося визначити"; fi
  if printf '%s\n' "$disp" | grep -Eiq 'Connection Type: Internal|Built-?in|Built-In'; then
    res ok "Відео" "Вбудований дисплей" "визначається системою"
    spec "Вбудований дисплей" "$(printf '%s\n' "$disp" | sp_get "Resolution")"
  else
    case $(printf '%s\n' "$hw" | sp_get "Model Name") in
      MacBook*) res warn "Відео" "Вбудований дисплей" "система не бачить вбудований дисплей (кришка закрита?)" ;;
      *) spec "Вбудований дисплей" "немає (настільний Mac)" ;;
    esac
  fi
}

t_disks_mac() {
  local d info nm size smart ssd proto n=0 line free total pct st
  for d in $(diskutil list internal physical 2>/dev/null | awk '/^\/dev\/disk/ {print $1}'); do
    n=$((n+1))
    info=$(diskutil info "$d" 2>/dev/null)
    nm=$(printf '%s\n' "$info" | sp_get "Device / Media Name"); [ -z "$nm" ] && nm=$d
    size=$(printf '%s\n' "$info" | sp_get "Disk Size" | sed 's/ (.*//')
    ssd=$(printf '%s\n' "$info" | sp_get "Solid State"); proto=$(printf '%s\n' "$info" | sp_get "Protocol")
    smart=$(printf '%s\n' "$info" | sp_get "SMART Status")
    spec "Диск: $nm" "$d, $size, ${proto:-?}, SSD: ${ssd:-?}"
    case $smart in
      Verified*) res ok "Диск" "$nm — стан" "справний (SMART: Verified)" ;;
      Failing*)  res fail "Диск" "$nm — стан" "SMART повідомляє про несправність (Failing)" ;;
      *)         res skip "Диск" "$nm — стан" "SMART не підтримується (${smart:-немає даних})" ;;
    esac
  done
  [ "$n" = 0 ] && res fail "Диск" "Накопичувачі" "не знайдено внутрішнього диска"
  line=$(df -k /System/Volumes/Data 2>/dev/null | awk 'NR==2 {print $2, $4}')
  [ -z "$line" ] && line=$(df -k / 2>/dev/null | awk 'NR==2 {print $2, $4}')
  if [ -n "$line" ]; then
    total=${line% *}; free=${line#* }; pct=$((free * 100 / total))
    if [ "$pct" -lt 10 ]; then st=warn; else st=ok; fi
    res "$st" "Диск" "Вільне місце" "$(calc "$free/1048576" 1) з $(calc "$total/1048576" 1) ГБ ($pct%)"
  fi
}

t_battery_mac() {
  local pw io cyc cond maxc design raw nominal maxcap h st model src detail
  pw=$(system_profiler SPPowerDataType 2>/dev/null)
  io=$(ioreg -rn AppleSmartBattery 2>/dev/null)
  model=$(system_profiler SPHardwareDataType 2>/dev/null | sp_get "Model Name")
  if [ -z "$io" ] && ! printf '%s\n' "$pw" | grep -q 'Cycle Count'; then
    case $model in
      MacBook*) res fail "Батарея" "Батарея" "не знайдена (відсутня, від'єднана або несправна)" ;;
      *) spec "Батарея" "немає (настільний Mac)" ;;
    esac
    return
  fi
  cyc=$(printf '%s\n' "$pw" | sp_get "Cycle Count")
  cond=$(printf '%s\n' "$pw" | sp_get "Condition")
  maxc=$(num "$(printf '%s\n' "$pw" | sp_get "Maximum Capacity")")
  design=$(printf '%s\n' "$io" | awk -F'= ' '/^ *"DesignCapacity" = / {print $2+0; exit}')
  raw=$(printf '%s\n' "$io" | awk -F'= ' '/^ *"AppleRawMaxCapacity" = / {print $2+0; exit}')
  nominal=$(printf '%s\n' "$io" | awk -F'= ' '/^ *"NominalChargeCapacity" = / {print $2+0; exit}')
  maxcap=$(printf '%s\n' "$io" | awk -F'= ' '/^ *"MaxCapacity" = / {print $2+0; exit}')
  h=""; src=""
  # 1) те саме число, що macOS показує в Налаштуваннях → Батарея → «Максимальна ємність»
  if [ -n "$maxc" ]; then h=$maxc; src="як у Налаштуваннях macOS"
  # 2) старіші macOS: номінальна ємність / заводська (так рахує сама macOS)
  elif [ -n "$nominal" ] && [ "${design:-0}" -gt 0 ]; then h=$((nominal * 100 / design)); src="розрахунок macOS"
  elif [ -n "$raw" ] && [ "${design:-0}" -gt 0 ]; then h=$((raw * 100 / design)); src="за даними контролера батареї"
  elif [ "${maxcap:-0}" -gt 100 ] && [ "${design:-0}" -gt 0 ]; then h=$((maxcap * 100 / design)); src="за даними контролера батареї"; fi
  if [ -n "$h" ]; then
    if [ "$h" -lt 50 ]; then st=fail; elif [ "$h" -lt 75 ]; then st=warn; else st=ok; fi
    detail="$src"
    [ "${design:-0}" -gt 0 ] && detail="$detail; заводська ємність $design мА·год"
    if [ -n "$raw" ] && [ "${design:-0}" -gt 0 ] && [ "$src" = "як у Налаштуваннях macOS" ]; then
      detail="$detail; сирі дані контролера: $raw мА·год ($((raw * 100 / design))%)"
    fi
    res "$st" "Батарея" "Стан батареї" "$h% від заводської ємності ($detail)"
  else res skip "Батарея" "Стан батареї" "не вдалося визначити ємність"; fi
  case $cond in
    Normal*|"") ;;
    *Replace*|*"Service Battery"*) res fail "Батарея" "Висновок macOS" "$cond" ;;
    *) res warn "Батарея" "Висновок macOS" "$cond" ;;
  esac
  [ "$cond" = Normal ] && res ok "Батарея" "Висновок macOS" "Normal"
  if [ -n "$cyc" ]; then
    if [ "$cyc" -gt 800 ] 2>/dev/null; then res warn "Батарея" "Цикли заряду" "$cyc"; else res ok "Батарея" "Цикли заряду" "$cyc"; fi
  fi
  spec "Поточний заряд" "$(pmset -g batt 2>/dev/null | grep -Eo '[0-9]+%' | head -n 1)"
  if pmset -g batt 2>/dev/null | head -n 1 | grep -q "AC Power"; then res ok "Батарея" "Зарядний пристрій" "підключено"
  else res warn "Батарея" "Зарядний пристрій" "не підключено — перевірте зарядку вручну"; fi
}

t_net_mac() {
  local ports wdev pwr bt st chip
  ports=$(networksetup -listallhardwareports 2>/dev/null)
  wdev=$(printf '%s\n' "$ports" | awk '/^Hardware Port: (Wi-Fi|AirPort)/ {getline; print $2; exit}')
  if [ -n "$wdev" ]; then
    pwr=$(networksetup -getairportpower "$wdev" 2>/dev/null)
    spec "Wi-Fi" "$wdev, MAC $(ifconfig "$wdev" 2>/dev/null | awk '/ether/ {print $2; exit}')"
    case $pwr in *On) res ok "Мережа" "Wi-Fi" "$wdev, увімкнено" ;; *) res warn "Мережа" "Wi-Fi" "$wdev, вимкнено" ;; esac
  else res fail "Мережа" "Wi-Fi" "адаптер Wi-Fi не знайдено"; fi
  printf '%s\n' "$ports" | awk '/^Hardware Port: .*(Ethernet|LAN)/ {p=$0; sub(/^Hardware Port: /, "", p); getline; print p " (" $2 ")"}' | while IFS= read -r st; do spec "Ethernet" "$st"; done
  bt=$(system_profiler SPBluetoothDataType 2>/dev/null)
  st=$(printf '%s\n' "$bt" | sp_get "State"); [ -z "$st" ] && st=$(printf '%s\n' "$bt" | sp_get "Bluetooth Power")
  chip=$(printf '%s\n' "$bt" | sp_get "Chipset")
  if [ -z "$bt" ]; then res warn "Мережа" "Bluetooth" "адаптер не знайдено"
  else case $st in On*) res ok "Мережа" "Bluetooth" "увімкнено${chip:+, $chip}" ;; Off*) res warn "Мережа" "Bluetooth" "вимкнено" ;; *) res ok "Мережа" "Bluetooth" "адаптер є${chip:+, $chip}" ;; esac; fi
}

t_periph_mac() {
  local cam aud model tp usb
  model=$(system_profiler SPHardwareDataType 2>/dev/null | sp_get "Model Name")
  cam=$(system_profiler SPCameraDataType 2>/dev/null | awk '/^    [^ ].*:$/ {sub(/^ +/, ""); sub(/:$/, ""); print}' | head -n 3 | tr '\n' ';' | sed 's/;$//; s/;/; /g')
  if [ -n "$cam" ]; then res ok "Периферія" "Вебкамера" "$cam"
  else res warn "Периферія" "Вебкамера" "не знайдена"; fi
  aud=$(system_profiler SPAudioDataType 2>/dev/null)
  if printf '%s\n' "$aud" | grep -q 'Output Channels'; then res ok "Периферія" "Вихід звуку (пристрій)" "є"
  else res fail "Периферія" "Вихід звуку (пристрій)" "не знайдено"; fi
  if printf '%s\n' "$aud" | grep -q 'Input Channels'; then res ok "Периферія" "Мікрофон" "є"
  else res warn "Периферія" "Мікрофон" "не знайдено"; fi
  tp=$(ioreg -r -c AppleMultitouchDevice -d 1 2>/dev/null | grep -c '"Product"')
  case $model in
    MacBook*)
      if [ "${tp:-0}" -gt 0 ]; then res ok "Периферія" "Трекпад (пристрій)" "визначається системою"
      else res warn "Периферія" "Трекпад (пристрій)" "не визначено — перевірте в ручному тесті"; fi ;;
  esac
  usb=$(system_profiler SPUSBHostDataType SPUSBDataType 2>/dev/null | grep -c 'Product ID')
  spec "USB-пристрої" "підключено: ${usb:-0}"
}

t_logs_mac() {
  local n
  n=$(find /Library/Logs/DiagnosticReports -maxdepth 2 \( -name '*.panic' -o -name 'panic-*' -o -name 'Kernel*' \) -mtime -30 2>/dev/null | wc -l | tr -d ' ')
  if [ "${n:-0}" -ge 3 ]; then res fail "Журнал macOS" "Аварійні перезавантаження (30 днів)" "$n разів (kernel panic)"
  elif [ "${n:-0}" -gt 0 ]; then res warn "Журнал macOS" "Аварійні перезавантаження (30 днів)" "$n разів (kernel panic)"
  else res ok "Журнал macOS" "Аварійні перезавантаження (30 днів)" "не було"; fi
}

# ===================================================================== навантаження CPU
cpu_temp_linux() {
  local h n t best=""
  for h in /sys/class/hwmon/hwmon*; do
    n=$(rd "$h/name")
    case $n in coretemp|k10temp|zenpower|cpu_thermal|cpu-thermal|soc_thermal)
      t=$(cat "$h"/temp*_input 2>/dev/null | sort -n | tail -n 1)
      [ -n "$t" ] && { echo $((t / 1000)); return; } ;;
    esac
  done
  for h in /sys/class/thermal/thermal_zone*; do
    case $(rd "$h/type") in x86_pkg_temp|cpu*|soc*|acpitz)
      t=$(rd "$h/temp"); [ -n "$t" ] && [ "$t" -gt "${best:-0}" ] 2>/dev/null && best=$t ;;
    esac
  done
  [ -n "$best" ] && echo $((best / 1000))
}
throttle_count() { cat /sys/devices/system/cpu/cpu*/thermal_throttle/*throttle_count 2>/dev/null | awk '{s+=$1} END {print s+0}'; }
read_cpu() { awk '/^cpu / {idle=$5+$6; t=0; for (i=2; i<=NF; i++) t+=$i; print t, idle; exit}' /proc/stat; }

t_stress() {
  local n pids="" i t0 el load freq temp tot idle pt=0 pi=0 thr0=0 thr1=0 lim minlim=100 pr worst="" k=0 ac=""
  n=$(cpu_count)
  trap 'kill $pids 2>/dev/null; exit 0' TERM
  for i in $(seq 1 "$n"); do ( while :; do :; done ) & pids="$pids $!"; done
  : > "$WORK/stress.dat"
  if [ "$OS_KIND" = linux ]; then thr0=$(throttle_count); set -- $(read_cpu); pt=$1; pi=$2; fi
  t0=$(date +%s)
  while :; do
    sleep 2
    el=$(( $(date +%s) - t0 )); [ "$el" -ge "$CPU_SECONDS" ] && break
    load=0; freq="-"; temp="-"
    if [ "$OS_KIND" = linux ]; then
      set -- $(read_cpu); tot=$1; idle=$2
      [ $((tot - pt)) -gt 0 ] && load=$(( 100 * ((tot - pt) - (idle - pi)) / (tot - pt) ))
      pt=$tot; pi=$idle
      freq=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null | awk '{s+=$1; c++} END {if (c) printf "%d", s/c/1000}')
      [ -z "$freq" ] && freq=$(awk -F: '/^cpu MHz/ {s+=$2; c++} END {if (c) printf "%d", s/c}' /proc/cpuinfo)
      temp=$(cpu_temp_linux); [ -z "$temp" ] && temp="-"; [ -z "$freq" ] && freq="-"
    else
      load=$(ps -A -o %cpu= 2>/dev/null | awk -v n="$n" '{s+=$1} END {printf "%d", s/n}')
      lim=$(pmset -g therm 2>/dev/null | awk -F'= *' '/CPU_Speed_Limit/ {print $2+0; exit}')
      [ -n "$lim" ] && [ "$lim" -lt "$minlim" ] && minlim=$lim
      k=$((k+1))
      if [ $((k % 8)) = 1 ] && has powermetrics; then
        pr=$(powermetrics --samplers thermal -i 500 -n 1 2>/dev/null | awk -F': ' '/pressure level/ {print $2; exit}')
        case $pr in Heavy|Trapping|Sleeping) worst=$pr ;; Moderate) [ -z "$worst" ] && worst=$pr ;; esac
      fi
    fi
    echo "$el $load $freq $temp" >> "$WORK/stress.dat"
    progress "залишилось $((CPU_SECONDS - el)) с · навантаження ${load}%$( [ "$freq" != "-" ] && printf ' · ~%s МГц' "$freq")$( [ "$temp" != "-" ] && printf ' · %s °C' "$temp")"
  done
  kill $pids 2>/dev/null; wait 2>/dev/null
  trap - TERM

  if [ "$OS_KIND" = linux ]; then
    for i in /sys/class/power_supply/*; do [ "$(rd "$i/type")" = Mains ] && { [ "$(rd "$i/online")" = 1 ] && ac=1 || ac=${ac:-0}; }; done
  else pmset -g batt 2>/dev/null | head -n 1 | grep -q "AC Power" && ac=1 || ac=0; fi
  local acnote=""; [ "$ac" = 0 ] && acnote=" Тест ішов від батареї — результат може бути занижений."

  set -- $(awk '$1 >= 10 {c++; L+=$2; f[c]=$3; if ($4 != "-" && $4 > mt) mt=$4}
    END { if (c < 3) { print 0; exit }
          t=int(c/3); if (t < 1) t=1; a=0; b=0; na=0; nb=0
          for (i=1; i<=t; i++) if (f[i] != "-") { a+=f[i]; na++ }
          for (i=c-t+1; i<=c; i++) if (f[i] != "-") { b+=f[i]; nb++ }
          printf "%d %d %d %d %d\n", c, L/c, (na ? a/na : 0), (nb ? b/nb : 0), mt+0 }' "$WORK/stress.dat")
  local cnt=${1:-0} avg=${2:-0} f1=${3:-0} f3=${4:-0} mt=${5:-0}
  if [ "$cnt" -lt 3 ]; then res skip "Навантаження" "Стрес-тест" "не вдалося зняти показники процесора"; return; fi
  if [ "$avg" -ge 80 ]; then res ok "Навантаження" "Завантаження процесора" "середнє $avg% на $n потоках протягом $CPU_SECONDS с"
  else res warn "Навантаження" "Завантаження процесора" "лише $avg% — процесор не вийшов на повне навантаження.$acnote"; fi

  if [ "$OS_KIND" = linux ]; then
    thr1=$(throttle_count)
    if [ "$f1" -gt 0 ]; then
      local drop=$(( 100 - f3 * 100 / f1 )) dthr=$((thr1 - thr0))
      if [ "$drop" -ge 35 ] || [ "$dthr" -gt 0 ]; then
        res warn "Навантаження" "Троттлінг (скидання частоти)" "частота ~$f1 → ~$f3 МГц$( [ "$dthr" -gt 0 ] && printf ', скидань через перегрів: %s' "$dthr") — перегрів, пил або висохла термопаста.$acnote"
      else res ok "Навантаження" "Троттлінг (скидання частоти)" "частота стабільна: ~$f1 → ~$f3 МГц"; fi
    else res skip "Навантаження" "Троттлінг (скидання частоти)" "система не віддає частоту процесора"; fi
    if [ "$mt" -gt 0 ]; then
      if [ "$mt" -ge 100 ]; then st=fail; elif [ "$mt" -ge 92 ]; then st=warn; else st=ok; fi
      res "$st" "Навантаження" "Температура під навантаженням" "максимум $mt °C"
    else res skip "Навантаження" "Температура під навантаженням" "датчик температури недоступний"; fi
  else
    if [ "$minlim" -lt 100 ]; then
      res warn "Навантаження" "Троттлінг (скидання частоти)" "macOS обмежувала процесор до $minlim% через нагрів.$acnote"
    else
      case $worst in
        Heavy|Trapping|Sleeping) res warn "Навантаження" "Троттлінг (скидання частоти)" "macOS фіксувала сильний нагрів (рівень: $worst).$acnote" ;;
        *) res ok "Навантаження" "Троттлінг (скидання частоти)" "обмежень через нагрів не було${worst:+ (рівень: $worst)}" ;;
      esac
    fi
  fi
  res ok "Навантаження" "Стабільність" "система не зависла під повним навантаженням $CPU_SECONDS с"
}

# ===================================================================== швидкість диска
t_diskspeed() {
  local dir f avail need cnt t0 t1 t2 w r kind="SSD" lw=150 lr=200 st src pk
  if [ "$OS_KIND" = macos ]; then dir=/private/var/tmp; else dir=/var/tmp; fi
  f="$dir/bibibi_disktest.tmp"
  avail=$(df -Pk "$dir" 2>/dev/null | awk 'NR==2 {print int($4/1024)}')
  need=$((DISK_MB + 2048))
  if [ -z "$avail" ] || [ "$avail" -lt "$need" ]; then
    res skip "Диск" "Швидкість диска" "замало вільного місця для тесту (потрібно $(calc "$need/1024" 1) ГБ)"; return
  fi
  if [ "$OS_KIND" = linux ]; then
    src=$(df -P "$dir" | awk 'NR==2 {print $1}'); pk=$(lsblk -no PKNAME "$src" 2>/dev/null | head -n 1)
    [ -z "$pk" ] && pk=${src##*/}
    case $pk in nvme*) kind="NVMe SSD"; lw=300; lr=500 ;; *) [ "$(rd "/sys/block/$pk/queue/rotational")" = 1 ] && { kind=HDD; lw=40; lr=50; } ;; esac
  else
    kind="SSD"; lw=300; lr=500
  fi
  cnt=$((DISK_MB / 4))
  trap 'rm -f "$f"; exit 0' TERM
  progress "запис $DISK_MB МБ"
  t0=$(now)
  if [ "$OS_KIND" = linux ]; then
    dd if=/dev/zero of="$f" bs=4M count="$cnt" oflag=direct conv=fsync status=none 2>/dev/null ||
      dd if=/dev/zero of="$f" bs=4M count="$cnt" conv=fdatasync 2>/dev/null
  else
    dd if=/dev/zero of="$f" bs=4m count="$cnt" 2>/dev/null; sync
  fi
  t1=$(now)
  progress "читання $DISK_MB МБ"
  if [ "$OS_KIND" = linux ]; then
    sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
    t1=$(now)
    dd if="$f" of=/dev/null bs=4M iflag=direct status=none 2>/dev/null || dd if="$f" of=/dev/null bs=4M 2>/dev/null
  else
    purge 2>/dev/null; t1=$(now)
    dd if="$f" of=/dev/null bs=4m 2>/dev/null
  fi
  t2=$(now)
  rm -f "$f"; trap - TERM
  w=$(calc "$DISK_MB / ($t1 - $t0 + 0.0001)"); r=$(calc "$DISK_MB / ($t2 - $t1 + 0.0001)")
  for st in "Швидкість запису:$w:$lw" "Швидкість читання:$r:$lr"; do
    local nm=${st%%:*} rest=${st#*:} v lim s note=""
    v=${rest%%:*}; lim=${rest#*:}
    if [ -z "$v" ]; then res skip "Диск" "$nm" "не вдалося виміряти"; continue; fi
    if [ "$v" -lt 15 ]; then s=fail; elif [ "$v" -lt "$lim" ]; then s=warn; else s=ok; fi
    [ "$s" != ok ] && note=" (для $kind очікується від $lim МБ/с)"
    res "$s" "Диск" "$nm" "$v МБ/с$note"
  done
}

# ===================================================================== звіт
write_template() {
cat > "$WORK/tpl_head" <<'BIBIBI_HEAD_EOF'
<!DOCTYPE html>
<html lang="uk">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>bibibi_test — звіт</title>
<style>
:root{
  --bg:#f3f4f7;--card:#fff;--fg:#1b1f27;--mut:#646b78;--line:#e3e6eb;
  --fail:#d93025;--fail-bg:#fdecea;--warn:#e8710a;--warn-bg:#fef3e6;
  --ok:#188038;--ok-bg:#e7f4eb;--skip:#6f7682;--skip-bg:#eef0f3;--acc:#2f6fed;
  --dk:#12161d;--dk2:#1c222c;--dk3:#2a313d;--dkt:#e9ecf1;--dkm:#98a1b0;
}
*{box-sizing:border-box}
html,body{margin:0}
body{background:var(--bg);color:var(--fg);font:15px/1.5 "Segoe UI",-apple-system,BlinkMacSystemFont,Roboto,Ubuntu,"Helvetica Neue",Arial,sans-serif;padding-bottom:96px}
.wrap{max-width:1040px;margin:0 auto;padding:24px 16px}
.hero{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:22px 24px;display:grid;grid-template-columns:1fr auto;gap:18px;border-top:6px solid var(--skip)}
.hero.v-fail{border-top-color:var(--fail)}.hero.v-warn{border-top-color:var(--warn)}.hero.v-ok{border-top-color:var(--ok)}
.hero h1{margin:0;font-size:26px;letter-spacing:-.01em;word-break:break-word}
.hero .sub{color:var(--mut);margin-top:2px}
.facts{display:flex;flex-wrap:wrap;gap:4px 18px;margin-top:12px;font-size:13px;color:var(--mut)}
.facts b{color:var(--fg);font-weight:600}
.verdict{text-align:right}
.pill{display:inline-block;padding:10px 16px;border-radius:12px;font-weight:700;color:#fff;background:var(--skip);font-size:15px;letter-spacing:.01em}
.v-fail .pill{background:var(--fail)}.v-warn .pill{background:var(--warn)}.v-ok .pill{background:var(--ok)}
.counts{display:flex;gap:6px;justify-content:flex-end;margin-top:10px;flex-wrap:wrap}
.cnt{font-size:12px;font-weight:600;padding:3px 9px;border-radius:999px}
.cnt.fail{background:var(--fail-bg);color:var(--fail)}.cnt.warn{background:var(--warn-bg);color:var(--warn)}
.cnt.ok{background:var(--ok-bg);color:var(--ok)}.cnt.skip{background:var(--skip-bg);color:var(--skip)}
.stamp{margin-top:8px;font-size:12px;color:var(--mut)}
@media(max-width:680px){.hero{grid-template-columns:1fr}.verdict{text-align:left}.counts{justify-content:flex-start}}

.manual{margin-top:18px;background:var(--dk);color:var(--dkt);border-radius:16px;padding:20px 22px}
.manual h2{margin:0 0 4px;font-size:18px}
.manual>p{margin:0 0 14px;color:var(--dkm);font-size:14px}
.mgrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:10px}
.mcard{background:var(--dk2);border:1px solid var(--dk3);border-radius:12px;padding:14px;display:flex;flex-direction:column;gap:8px}
.mcard .t{font-weight:700;font-size:16px}
.mcard .d{font-size:13px;color:var(--dkm);flex:1}
.st{font-size:12px;font-weight:700}
.st.pending{color:var(--dkm)}.st.ok{color:#5fd38a}.st.warn{color:#ffad5c}.st.fail{color:#ff7a70}.st.skip{color:#b6bcc7}
.mactions{margin-top:14px;display:flex;gap:8px;flex-wrap:wrap}
.btn{font:inherit;font-weight:600;border:0;border-radius:10px;padding:9px 14px;cursor:pointer;background:var(--acc);color:#fff}
.btn:hover{filter:brightness(1.1)}
.btn.ghost{background:var(--dk3);color:var(--dkt)}
.btn.ok{background:var(--ok)}.btn.fail{background:var(--fail)}.btn.skip{background:#596070}
.btn.big{padding:12px 20px;font-size:16px}

.block{margin-top:18px;background:var(--card);border:1px solid var(--line);border-radius:16px;overflow:hidden}
.block>summary{list-style:none;cursor:pointer;padding:14px 18px;display:flex;align-items:center;gap:10px;font-weight:700;font-size:16px}
.block>summary::-webkit-details-marker{display:none}
.block .dot{width:12px;height:12px;border-radius:50%;flex:none;background:var(--skip)}
.block .n{margin-left:auto;font-size:13px;font-weight:600;opacity:.85}
.block.fail>summary{background:var(--fail-bg);color:var(--fail)}.block.fail .dot{background:var(--fail)}
.block.warn>summary{background:var(--warn-bg);color:var(--warn)}.block.warn .dot{background:var(--warn)}
.block.ok>summary{background:var(--ok-bg);color:var(--ok)}.block.ok .dot{background:var(--ok)}
.block.skip>summary{background:var(--skip-bg);color:var(--skip)}
.block.specs>summary{color:var(--fg)}
.item{display:grid;grid-template-columns:240px 1fr;gap:4px 18px;padding:10px 18px;border-top:1px solid var(--line)}
.item .c{font-size:11px;color:var(--mut);text-transform:uppercase;letter-spacing:.04em}
.item .tt{font-weight:600}
.item .v{color:#323946;word-break:break-word;align-self:center}
.empty{padding:12px 18px;color:var(--mut);border-top:1px solid var(--line)}
.specs table{width:100%;border-collapse:collapse}
.specs td{padding:8px 18px;border-top:1px solid var(--line);vertical-align:top;word-break:break-word}
.specs td:first-child{width:32%;color:var(--mut)}
@media(max-width:680px){.item{grid-template-columns:1fr}.specs td:first-child{width:40%}}
footer{color:var(--mut);font-size:12px;margin-top:22px;text-align:center}
.account{margin-top:18px;background:var(--card);border:1px solid var(--line);border-left:8px solid var(--ok);border-radius:16px;overflow:hidden}
.account.fail{border-left-color:var(--fail)}.account.warn{border-left-color:var(--warn)}
.account>h2{margin:0;padding:14px 18px;font-size:17px;display:flex;align-items:center;gap:10px}
.account.fail>h2{background:var(--fail-bg);color:var(--fail)}.account.ok>h2{background:var(--ok-bg);color:var(--ok)}.account.warn>h2{background:var(--warn-bg);color:var(--warn)}
.account>h2 small{margin-left:auto;font-size:13px;font-weight:600}
.arow{display:grid;grid-template-columns:110px 240px 1fr;gap:4px 14px;padding:11px 18px;border-top:1px solid var(--line);align-items:center}
.arow .tt{font-weight:600}
.arow .v{word-break:break-word}
.arow.fail .v{color:var(--fail);font-weight:700}
.tag{display:inline-block;font-size:11px;font-weight:700;padding:3px 8px;border-radius:6px;color:#fff;background:var(--skip);text-align:center}
.tag.ok{background:var(--ok)}.tag.warn{background:var(--warn)}.tag.fail{background:var(--fail)}.tag.info{background:#2f6fed}
@media(max-width:680px){.arow{grid-template-columns:1fr}}


.savebar{position:fixed;left:0;right:0;bottom:0;background:var(--dk);color:var(--dkt);padding:12px 16px;display:flex;align-items:center;gap:14px;justify-content:center;flex-wrap:wrap;box-shadow:0 -6px 24px rgba(0,0,0,.18);z-index:20}
.savebar .fn{font-size:13px;color:var(--dkm);word-break:break-all}
.toast{position:fixed;left:50%;bottom:92px;transform:translateX(-50%);background:#1d6b3c;color:#fff;padding:12px 18px;border-radius:12px;z-index:30;max-width:92vw;box-shadow:0 8px 24px rgba(0,0,0,.25);font-weight:600}

.stage{position:fixed;inset:0;background:var(--dk);color:var(--dkt);z-index:40;display:flex;flex-direction:column}
.stage[hidden]{display:none}
.stage>header{padding:16px 20px;border-bottom:1px solid var(--dk3)}
.stage h2{margin:0;font-size:20px}
.stage .hint{margin:4px 0 0;color:var(--dkm);font-size:14px;max-width:960px}
.stage .body{flex:1;overflow:auto;padding:20px}
.stage .foot{padding:12px 20px;border-top:1px solid var(--dk3);display:flex;gap:10px;align-items:center;flex-wrap:wrap}
.stage .foot input{flex:1;min-width:220px;font:inherit;padding:10px 12px;border-radius:10px;border:1px solid var(--dk3);background:var(--dk2);color:var(--dkt)}
.auto{font-size:13px;color:var(--dkm);width:100%}
.note{color:var(--dkm);font-size:14px;margin:12px 0 0}

.kb{display:flex;flex-direction:column;gap:6px;max-width:1040px;margin:0 auto;user-select:none}
.krow{display:flex;gap:6px}
.k{height:48px;flex:1 1 0;min-width:0;background:var(--dk3);border:1px solid #384152;border-radius:8px;display:flex;align-items:center;justify-content:center;font-size:12px;color:#b3bbc8;overflow:hidden;white-space:nowrap;padding:0 2px}
.k.done{background:#1c6b3c;color:#e0ffea;border-color:#2b9a59}
.k.down{background:#ffd34d;color:#111;border-color:#ffd34d}
.kopt{max-width:1040px;margin:16px auto 0}
.kopt h3{font-size:13px;color:var(--dkm);margin:0 0 6px;font-weight:600}
.kopt .krow{flex-wrap:wrap}.kopt .k{flex:0 0 auto;padding:0 12px}
.kstat{text-align:center;margin-top:14px;color:var(--dkm)}
.kstat b{color:#fff}

.tp{position:relative;max-width:1040px;margin:0 auto;height:min(52vh,460px);border-radius:14px;overflow:hidden;border:1px solid var(--dk3);touch-action:none;cursor:crosshair}
.tpgrid{position:absolute;inset:0;display:grid;grid-template-columns:repeat(8,1fr);grid-template-rows:repeat(5,1fr)}
.tpgrid div{border:1px solid #1a1f28;background:#171c25;transition:background .15s}
.tpgrid div.on{background:#1c5a36}
.tp canvas{position:absolute;inset:0;width:100%;height:100%}
.ind{display:flex;flex-wrap:wrap;gap:8px;justify-content:center;margin-top:14px}
.ind span{padding:7px 12px;border-radius:9px;background:var(--dk3);color:var(--dkm);font-size:13px}
.ind span.on{background:#2b9a59;color:#fff}
.sgrid{display:flex;flex-wrap:wrap;gap:10px}

#fs{position:fixed;inset:0;z-index:60;cursor:none}
#fs[hidden]{display:none}
#fsLabel{position:fixed;left:50%;bottom:14px;transform:translateX(-50%);font:12px system-ui,sans-serif;color:#888;mix-blend-mode:difference;z-index:61}
@media print{.savebar,.manual,.stage,.toast{display:none!important}body{background:#fff;padding:0}.block{break-inside:avoid}}
</style>
</head>
<body>
<div id="app"></div>

<div id="stage" class="stage" hidden>
  <header><h2 id="stTitle"></h2><p class="hint" id="stHint"></p></header>
  <div class="body" id="stBody"></div>
  <div class="foot">
    <div class="auto" id="stAuto"></div>
    <input id="stComment" type="text" placeholder="Коментар (необов'язково): що саме не так">
    <button class="btn ok" data-v="ok" type="button">Працює</button>
    <button class="btn fail" data-v="fail" type="button">Проблема</button>
    <button class="btn skip" data-v="skip" type="button">Пропустити</button>
  </div>
</div>
<div id="fs" hidden><div id="fsLabel"></div></div>

<script id="bibibi-data" type="application/json">
BIBIBI_HEAD_EOF
cat > "$WORK/tpl_tail" <<'BIBIBI_TAIL_EOF'
</script>
<script>
(function () {
  'use strict';
  var ORIGINAL = '<!DOCTYPE html>\n' + document.documentElement.outerHTML;
  var DATA = null;
  try { DATA = JSON.parse(document.getElementById('bibibi-data').textContent); } catch (e) { DATA = null; }
  if (!DATA || typeof DATA !== 'object') DATA = demoData();
  DATA.meta = DATA.meta || {}; DATA.results = DATA.results || []; DATA.specs = DATA.specs || []; DATA.manual = DATA.manual || {};
  var FINAL = DATA.final === true;
  var IS_MAC = DATA.meta.platform ? DATA.meta.platform === 'macos' : /Mac/i.test(navigator.platform);

  var ORDER = ['fail', 'warn', 'ok', 'skip'];
  // Results of this category are shown in a separate block at the very top.
  var TOP_CAT = 'Обліковий запис';
  var TAG = { ok: 'Норма', warn: 'Увага', fail: 'Критично', skip: 'Не перевірено', info: 'Інфо' };
  var TITLES = { fail: 'Критично', warn: 'Зауваження', ok: 'Норма', skip: 'Не вдалося перевірити' };
  var SHORT = { fail: 'Критично', warn: 'Зауваження', ok: 'Норма', skip: 'Не перевірено' };
  var MSTATE = { ok: 'Працює', fail: 'Проблема', skip: 'Пропущено', warn: 'Зауваження' };
  var MANUAL = [
    { id: 'screen', name: 'Екран', desc: 'Кольори на весь екран: биті пікселі, засвіти, смуги.' },
    { id: 'sound', name: 'Динаміки', desc: 'Лівий і правий канал, свіп частот, без хрипу.' },
    { id: 'keyboard', name: 'Клавіатура', desc: 'Натиснути всі основні клавіші.' },
    { id: 'touchpad', name: 'Тачпад', desc: 'Усі зони сенсора, кліки, прокрутка, жести.' }
  ];

  function $(id) { return document.getElementById(id); }
  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  // ---------------------------------------------------------------- дані
  function manualItems() {
    return MANUAL.map(function (m) {
      var r = DATA.manual[m.id];
      if (r && r.status) {
        return { cat: 'Ручні тести', test: m.name, status: r.status,
          value: (r.value || '') + (r.comment ? ' — коментар: ' + r.comment : '') };
      }
      return { cat: 'Ручні тести', test: m.name, status: 'skip', value: FINAL ? 'не перевірялось' : 'ще не перевірено' };
    });
  }
  function allItems() { return DATA.results.concat(manualItems()); }
  function summary() {
    var c = { fail: 0, warn: 0, ok: 0, skip: 0 };
    allItems().forEach(function (i) { if (c[i.status] != null) c[i.status]++; });
    var v = c.fail ? 'fail' : (c.warn ? 'warn' : 'ok');
    return { cls: v, verdict: { fail: 'Є КРИТИЧНІ ПРОБЛЕМИ', warn: 'Є ЗАУВАЖЕННЯ', ok: 'ВСЕ ДОБРЕ' }[v],
      fail: c.fail, warn: c.warn, ok: c.ok, skip: c.skip };
  }

  // ---------------------------------------------------------------- звіт
  function render() {
    var m = DATA.meta, s = summary(), h = '<div class="wrap">';
    h += '<section class="hero v-' + s.cls + '"><div>';
    h += '<h1>' + esc(m.hostname || 'Без назви') + '</h1>';
    h += '<div class="sub">' + esc(m.model || '') + '</div><div class="facts">';
    h += fact('S/N', m.serial || 'не вказано') + fact('Дата', m.datetime || m.date) + fact('ОС', m.os) +
      fact('Тривалість', m.duration ? m.duration + ' хв' : '');
    h += '</div></div><div class="verdict"><span class="pill">' + esc(s.verdict) + '</span><div class="counts">';
    ORDER.forEach(function (st) { h += '<span class="cnt ' + st + '">' + SHORT[st] + ': ' + s[st] + '</span>'; });
    h += '</div><div class="stamp">' + (FINAL ? 'Фінальний звіт' : 'Проміжний звіт: пройдіть ручні тести і натисніть «Зберегти звіт»') + '</div></div></section>';
    h += accountBlock();
    if (!FINAL) h += manualPanel();
    ORDER.forEach(function (st) { h += block(st); });
    h += specsBlock();
    h += '<footer>bibibi_test ' + esc(DATA.version || '') + ' · звіт створено локально на цьому ПК і нікуди не відправлявся</footer></div>';
    if (!FINAL) {
      h += '<div class="savebar"><span class="fn">Файл: ' + esc(m.filename || '') + '</span>' +
        '<button class="btn big ok" id="saveBtn" type="button">Зберегти звіт</button></div>';
    }
    $('app').innerHTML = h;
    bindApp();
  }
  function fact(k, v) { return v ? '<span>' + esc(k) + ': <b>' + esc(v) + '</b></span>' : ''; }
  function accountBlock() {
    var items = DATA.results.filter(function (i) { return i.cat === TOP_CAT; });
    if (!items.length) return '';
    var worst = items.some(function (i) { return i.status === 'fail'; }) ? 'fail'
      : items.some(function (i) { return i.status === 'warn'; }) ? 'warn' : 'ok';
    var head = { fail: 'Пристрій прив\'язаний до облікового запису', warn: 'Обліковий запис: є зауваження', ok: 'Обліковий запис: пристрій вільний' }[worst];
    var h = '<section class="account ' + worst + '"><h2>' + esc(head) + '<small>iCloud · Знайти · блокування · шифрування · MDM</small></h2>';
    items.forEach(function (i) {
      h += '<div class="arow ' + esc(i.status) + '"><div><span class="tag ' + esc(i.status) + '">' + esc(TAG[i.status] || i.status) +
        '</span></div><div class="tt">' + esc(i.test) + '</div><div class="v">' + esc(i.value) + '</div></div>';
    });
    return h + '</section>';
  }
  function block(st) {
    var items = allItems().filter(function (i) { return i.status === st && i.cat !== TOP_CAT; });
    var h = '<details class="block ' + st + '"' + (st === 'ok' && items.length > 12 ? '' : ' open') + '><summary><span class="dot"></span>' +
      TITLES[st] + '<span class="n">' + items.length + '</span></summary>';
    if (!items.length) h += '<div class="empty">Немає</div>';
    items.forEach(function (i) {
      h += '<div class="item"><div><div class="c">' + esc(i.cat) + '</div><div class="tt">' + esc(i.test) +
        '</div></div><div class="v">' + esc(i.value) + '</div></div>';
    });
    return h + '</details>';
  }
  function specsBlock() {
    var h = '<details class="block specs" open><summary><span class="dot"></span>Характеристики<span class="n">' +
      DATA.specs.length + '</span></summary><table>';
    DATA.specs.forEach(function (s) { h += '<tr><td>' + esc(s.k) + '</td><td>' + esc(s.v) + '</td></tr>'; });
    return h + '</table></details>';
  }
  function manualPanel() {
    var h = '<section class="manual"><h2>Ручні тести</h2><p>Ці перевірки робить людина. Після кожної натисніть «Працює», «Проблема» або «Пропустити».</p><div class="mgrid">';
    MANUAL.forEach(function (m) {
      var r = DATA.manual[m.id], st = r && r.status ? r.status : 'pending';
      h += '<div class="mcard"><div class="t">' + m.name + '</div><div class="d">' + m.desc + '</div>' +
        '<div class="st ' + st + '">' + (st === 'pending' ? 'Не перевірено' : MSTATE[st]) + '</div>' +
        '<button class="btn ghost" type="button" data-test="' + m.id + '">' + (st === 'pending' ? 'Почати' : 'Повторити') + '</button></div>';
    });
    return h + '</div><div class="mactions"><button class="btn big" id="wizardBtn" type="button">Пройти всі по черзі</button></div></section>';
  }
  function bindApp() {
    Array.prototype.forEach.call(document.querySelectorAll('[data-test]'), function (b) {
      b.addEventListener('click', function () { wizard = false; openTest(b.getAttribute('data-test')); });
    });
    if ($('wizardBtn')) $('wizardBtn').addEventListener('click', function () {
      wizard = true;
      var next = MANUAL.filter(function (m) { return !(DATA.manual[m.id] && DATA.manual[m.id].status); })[0] || MANUAL[0];
      openTest(next.id);
    });
    if ($('saveBtn')) $('saveBtn').addEventListener('click', save);
  }

  // ---------------------------------------------------------------- ручні тести: каркас
  var current = null, wizard = false, tests = {};
  function openTest(id) {
    current = id;
    var t = tests[id], m = MANUAL.filter(function (x) { return x.id === id; })[0];
    $('stTitle').textContent = m.name;
    $('stHint').textContent = t.hint();
    $('stBody').innerHTML = '';
    $('stComment').value = (DATA.manual[id] && DATA.manual[id].comment) || '';
    $('stage').hidden = false;
    document.body.style.overflow = 'hidden';
    t.open($('stBody'));
    updateAuto();
  }
  function updateAuto() { if (current) $('stAuto').textContent = tests[current].auto(); }
  function finish(v) {
    var id = current, t = tests[id];
    DATA.manual[id] = { status: v, value: v === 'skip' ? 'пропущено' : t.auto(), comment: $('stComment').value.trim() };
    t.close();
    current = null;
    $('stage').hidden = true;
    document.body.style.overflow = '';
    render();
    if (wizard) {
      var idx = MANUAL.map(function (m) { return m.id; }).indexOf(id);
      if (idx >= 0 && idx < MANUAL.length - 1) { openTest(MANUAL[idx + 1].id); return; }
      wizard = false;
    }
    window.scrollTo(0, 0);
  }
  Array.prototype.forEach.call(document.querySelectorAll('#stage .foot [data-v]'), function (b) {
    b.addEventListener('click', function () { finish(b.getAttribute('data-v')); });
  });

  // ---------------------------------------------------------------- екран
  var SLIDES = [
    ['#000', 'чорний'], ['#fff', 'білий'], ['#f00', 'червоний'], ['#0f0', 'зелений'], ['#00f', 'синій'],
    ['#808080', 'сірий'], ['#ff0', 'жовтий'], ['#0ff', 'блакитний'], ['#f0f', 'пурпурний'],
    ['linear-gradient(90deg,#000,#fff)', 'градієнт'],
    ['repeating-linear-gradient(0deg,#000 0 1px,#fff 1px 2px)', 'тонкі смужки']
  ];
  var slide = 0, seen = 0;
  function paintSlide() {
    $('fs').style.background = SLIDES[slide][0];
    $('fsLabel').textContent = (slide + 1) + ' / ' + SLIDES.length + ' · ' + SLIDES[slide][1] + ' · клік — далі, Esc — вихід';
    seen = Math.max(seen, slide + 1);
  }
  function startSlides() {
    slide = 0; paintSlide(); $('fs').hidden = false;
    var el = document.documentElement;
    var rq = el.requestFullscreen || el.webkitRequestFullscreen;
    if (rq) { try { var p = rq.call(el); if (p && p.catch) p.catch(function () {}); } catch (e) {} }
  }
  function nextSlide() { slide++; if (slide >= SLIDES.length) endSlides(); else paintSlide(); }
  function endSlides() {
    $('fs').hidden = true;
    var fe = document.fullscreenElement || document.webkitFullscreenElement;
    var ex = document.exitFullscreen || document.webkitExitFullscreen;
    if (fe && ex) { try { var p = ex.call(document); if (p && p.catch) p.catch(function () {}); } catch (e) {} }
    updateAuto();
  }
  $('fs').addEventListener('click', nextSlide);
  function onFsChange() {
    if (!(document.fullscreenElement || document.webkitFullscreenElement) && !$('fs').hidden) endSlides();
  }
  document.addEventListener('fullscreenchange', onFsChange);
  document.addEventListener('webkitfullscreenchange', onFsChange);
  tests.screen = {
    hint: function () { return 'Екран заливається кольорами на весь розмір. Клік або будь-яка клавіша — наступний колір, Esc — вихід. На чорному шукайте засвіти по краях і світлі точки, на білому та кольорових — темні або кольорові точки (биті пікселі), на сірому та градієнті — плями й смуги.'; },
    open: function (b) {
      seen = 0;
      b.innerHTML = '<button class="btn big" type="button" id="scrGo">Показати кольори на весь екран</button><p class="note">Кольорів: ' + SLIDES.length + '. Можна пройти кілька разів.</p>';
      $('scrGo').addEventListener('click', startSlides);
    },
    auto: function () { return seen ? 'переглянуто кольорів: ' + seen + ' з ' + SLIDES.length : 'кольори ще не показувались'; },
    close: function () { if (!$('fs').hidden) endSlides(); }
  };

  // ---------------------------------------------------------------- звук
  var ac = null, played = {}, osc = [];
  function actx() {
    if (!ac) { var C = window.AudioContext || window.webkitAudioContext; ac = new C(); }
    if (ac.state === 'suspended') ac.resume();
    return ac;
  }
  function stopSound() { osc.forEach(function (o) { try { o.stop(); } catch (e) {} }); osc = []; }
  function tone(pan, key) {
    stopSound();
    var a = actx(), o = a.createOscillator(), g = a.createGain(), t = a.currentTime, out = g;
    o.frequency.value = 440;
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(0.35, t + 0.05);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 1.5);
    o.connect(g);
    if (a.createStereoPanner) { var p = a.createStereoPanner(); p.pan.value = pan; g.connect(p); out = p; }
    out.connect(a.destination);
    o.start(t); o.stop(t + 1.6); osc.push(o);
    played[key] = true; updateAuto();
  }
  function sweep() {
    stopSound();
    var a = actx(), o = a.createOscillator(), g = a.createGain(), t = a.currentTime;
    o.frequency.setValueAtTime(60, t);
    o.frequency.exponentialRampToValueAtTime(12000, t + 8);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(0.3, t + 0.2);
    g.gain.setValueAtTime(0.3, t + 7.8);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 8);
    o.connect(g); g.connect(a.destination);
    o.start(t); o.stop(t + 8.1); osc.push(o);
    played.sweep = true; updateAuto();
  }
  tests.sound = {
    hint: function () { return 'Поставте гучність приблизно на 70%. Звук «Лівий» має йти лише з лівого динаміка, «Правий» — лише з правого. На свіпі (від низьких до високих частот) слухайте, чи немає хрипу, дребезжання корпусу або провалів звуку.'; },
    open: function (b) {
      played = {};
      b.innerHTML = '<div class="sgrid">' +
        '<button class="btn big" type="button" id="sL">◀ Лівий</button>' +
        '<button class="btn big" type="button" id="sR">Правий ▶</button>' +
        '<button class="btn big" type="button" id="sB">Обидва</button>' +
        '<button class="btn big ghost" type="button" id="sS">Свіп 60 Гц → 12 кГц</button>' +
        '<button class="btn big ghost" type="button" id="sX">Стоп</button></div>' +
        '<p class="note">Якщо є роз\'єм для навушників — підключіть їх і повторіть.</p>';
      $('sL').addEventListener('click', function () { tone(-1, 'left'); });
      $('sR').addEventListener('click', function () { tone(1, 'right'); });
      $('sB').addEventListener('click', function () { tone(0, 'both'); });
      $('sS').addEventListener('click', sweep);
      $('sX').addEventListener('click', stopSound);
    },
    auto: function () {
      var n = { left: 'лівий', right: 'правий', both: 'обидва', sweep: 'свіп' }, done = [];
      Object.keys(n).forEach(function (k) { if (played[k]) done.push(n[k]); });
      return done.length ? 'відтворено: ' + done.join(', ') : 'звук ще не відтворювався';
    },
    close: stopSound
  };

  // ---------------------------------------------------------------- клавіатура
  var KL = {
    Backquote: '`', Minus: '-', Equal: '=', BracketLeft: '[', BracketRight: ']', Backslash: '\\', Semicolon: ';',
    Quote: "'", Comma: ',', Period: '.', Slash: '/', Escape: 'Esc', Backspace: IS_MAC ? 'delete' : 'Backspace',
    Tab: 'Tab', CapsLock: 'Caps', Enter: IS_MAC ? 'return' : 'Enter', ShiftLeft: 'Shift', ShiftRight: 'Shift',
    ControlLeft: IS_MAC ? 'control' : 'Ctrl', ControlRight: 'Ctrl', MetaLeft: IS_MAC ? '⌘ cmd' : 'Win',
    MetaRight: '⌘ cmd', AltLeft: IS_MAC ? '⌥ option' : 'Alt', AltRight: IS_MAC ? '⌥ option' : 'Alt',
    Space: 'Пробіл', ContextMenu: 'Меню', ArrowLeft: '←', ArrowRight: '→', ArrowUp: '↑', ArrowDown: '↓',
    Delete: 'Del', Insert: 'Ins', Home: 'Home', End: 'End', PageUp: 'PgUp', PageDown: 'PgDn',
    PrintScreen: 'PrtSc', IntlBackslash: '\\ (ISO)', NumLock: 'NumLk', ScrollLock: 'ScrLk', Pause: 'Pause'
  };
  function lbl(c) { return KL[c] || c.replace(/^Key/, '').replace(/^Digit/, '').replace(/^Numpad/, 'Num '); }
  function seq(s) { return s.split('').map(function (c) { return (/\d/.test(c) ? 'Digit' : 'Key') + c; }); }
  var FK = []; for (var fi = 1; fi <= 12; fi++) FK.push('F' + fi);
  var ROWS_MID = [
    ['Backquote'].concat(seq('1234567890'), ['Minus', 'Equal', ['Backspace', 2]]),
    [['Tab', 1.5]].concat(seq('QWERTYUIOP'), ['BracketLeft', 'BracketRight', ['Backslash', 1.5]]),
    [['CapsLock', 1.8]].concat(seq('ASDFGHJKL'), ['Semicolon', 'Quote', ['Enter', 2.2]]),
    [['ShiftLeft', 2.4]].concat(seq('ZXCVBNM'), ['Comma', 'Period', 'Slash', ['ShiftRight', 2.6]])
  ];
  var ROWS = IS_MAC
    ? [['Escape'].concat(FK)].concat(ROWS_MID, [['ControlLeft', 'AltLeft', ['MetaLeft', 1.4], ['Space', 6], ['MetaRight', 1.4], 'AltRight', 'ArrowLeft', 'ArrowUp', 'ArrowDown', 'ArrowRight']])
    : [['Escape'].concat(FK, ['Delete'])].concat(ROWS_MID, [[['ControlLeft', 1.3], 'MetaLeft', 'AltLeft', ['Space', 6], 'AltRight', ['ControlRight', 1.3], 'ArrowLeft', 'ArrowUp', 'ArrowDown', 'ArrowRight']]);
  var OPTIONAL = IS_MAC ? [] : ['PrintScreen', 'Insert', 'Home', 'End', 'PageUp', 'PageDown', 'ContextMenu'];
  var REQUIRED = [];
  ROWS.forEach(function (r) { r.forEach(function (k) { REQUIRED.push(Array.isArray(k) ? k[0] : k); }); });
  var kbEls = {}, kbDone = {};
  function kbBuild(b) {
    kbEls = {}; kbDone = {};
    var h = '<div class="kb">';
    ROWS.forEach(function (r) {
      h += '<div class="krow">';
      r.forEach(function (k) {
        var code = Array.isArray(k) ? k[0] : k, w = Array.isArray(k) ? k[1] : 1;
        h += '<div class="k" data-code="' + code + '" style="flex-grow:' + w + '">' + esc(lbl(code)) + '</div>';
      });
      h += '</div>';
    });
    h += '</div><div class="kopt"><h3>Додаткові (є не на всіх ноутбуках, не обов\'язкові)</h3><div class="krow" id="kExtra">';
    OPTIONAL.forEach(function (c) { h += '<div class="k" data-code="' + c + '">' + esc(lbl(c)) + '</div>'; });
    h += '</div></div><div class="kstat">Основні: <b id="kN">0</b> з <b>' + REQUIRED.length + '</b> · остання: <b id="kLast">—</b></div>' +
      '<p class="note" style="text-align:center"><button class="btn ghost" type="button" id="kReset">Скинути</button></p>';
    b.innerHTML = h;
    Array.prototype.forEach.call(b.querySelectorAll('.k'), function (el) { kbEls[el.getAttribute('data-code')] = el; });
    $('kReset').addEventListener('click', function () { kbBuild(b); updateAuto(); });
  }
  function kbEl(code) {
    if (!kbEls[code]) {
      var el = document.createElement('div');
      el.className = 'k'; el.textContent = lbl(code); el.setAttribute('data-code', code);
      $('kExtra').appendChild(el); kbEls[code] = el;
    }
    return kbEls[code];
  }
  function kbMark(code) {
    kbDone[code] = true;
    kbEl(code).classList.add('done');
    var n = REQUIRED.filter(function (c) { return kbDone[c]; }).length;
    $('kN').textContent = n;
    updateAuto();
  }
  function kbActive(e) {
    return current === 'keyboard' && $('fs').hidden && document.activeElement !== $('stComment') && e.code;
  }
  document.addEventListener('keydown', function (e) {
    if (!$('fs').hidden) { e.preventDefault(); if (e.key !== 'Escape') nextSlide(); else endSlides(); return; }
    if (!kbActive(e)) return;
    e.preventDefault();
    kbEl(e.code).classList.add('down');
    $('kLast').textContent = e.code + (e.key && e.key.length === 1 ? ' (' + e.key + ')' : '');
    kbMark(e.code);
  }, true);
  document.addEventListener('keyup', function (e) {
    if (!kbActive(e)) return;
    e.preventDefault();
    kbEl(e.code).classList.remove('down');
    if (!kbDone[e.code]) kbMark(e.code);   // PrintScreen у Windows приходить тільки як keyup
  }, true);
  window.addEventListener('blur', function () {
    Array.prototype.forEach.call(document.querySelectorAll('.k.down'), function (k) { k.classList.remove('down'); });
  });
  tests.keyboard = {
    hint: function () {
      return 'Натисніть по черзі всі клавіші: кожна має стати зеленою. Жовта — затиснута зараз; якщо клавіша світиться жовтим без натискання, вона залипає. Fn браузер не бачить — перевірте її через яскравість чи гучність. ' +
        (IS_MAC ? 'Не натискайте ⌘ разом з іншими клавішами (⌘W закриє вкладку). F1–F12 натискайте разом з fn.' : 'Клавіша Win відкриє меню «Пуск» — просто закрийте його.');
    },
    open: kbBuild,
    auto: function () {
      var miss = REQUIRED.filter(function (c) { return !kbDone[c]; });
      var extra = Object.keys(kbDone).filter(function (c) { return REQUIRED.indexOf(c) < 0; }).length;
      var s = miss.length ? 'не натиснуто ' + miss.length + ' з ' + REQUIRED.length + ': ' + miss.map(lbl).join(' ') : 'усі ' + REQUIRED.length + ' основних клавіш спрацювали';
      return s + (extra ? '; додаткових: ' + extra : '');
    },
    close: function () {}
  };

  // ---------------------------------------------------------------- тачпад
  var TP_COLS = 8, TP_ROWS = 5, tpCells = {}, tpFlags = {}, tpLast = null, tpCtx = null;
  var TP_IND = [['left', 'Лівий клік / тап'], ['right', 'Правий клік'], ['up', 'Прокрутка ↑'], ['down', 'Прокрутка ↓'],
    ['l', 'Прокрутка ←'], ['r', 'Прокрутка →'], ['zoom', 'Масштаб (зведення пальців)']];
  function tpFlag(k) { if (!tpFlags[k]) { tpFlags[k] = true; var s = document.querySelector('#tpInd [data-i="' + k + '"]'); if (s) s.classList.add('on'); updateAuto(); } }
  function tpOpen(b) {
    tpCells = {}; tpFlags = {}; tpLast = null;
    var h = '<div class="tp" id="tp"><div class="tpgrid" id="tpGrid">';
    for (var i = 0; i < TP_COLS * TP_ROWS; i++) h += '<div></div>';
    h += '</div><canvas id="tpC"></canvas></div><div class="ind" id="tpInd">';
    TP_IND.forEach(function (x) { h += '<span data-i="' + x[0] + '">' + x[1] + '</span>'; });
    h += '</div><div class="kstat">Зони сенсора: <b id="tpN">0</b> з ' + (TP_COLS * TP_ROWS) +
      '</div><p class="note" style="text-align:center"><button class="btn ghost" type="button" id="tpReset">Скинути</button></p>';
    b.innerHTML = h;
    var tp = $('tp'), c = $('tpC'), r = tp.getBoundingClientRect(), d = window.devicePixelRatio || 1;
    c.width = Math.round(r.width * d); c.height = Math.round(r.height * d);
    tpCtx = c.getContext('2d'); tpCtx.scale(d, d);
    var cells = $('tpGrid').children;
    tp.addEventListener('pointermove', function (e) {
      var rr = tp.getBoundingClientRect(), x = e.clientX - rr.left, y = e.clientY - rr.top;
      var col = Math.min(TP_COLS - 1, Math.max(0, Math.floor(x / rr.width * TP_COLS)));
      var row = Math.min(TP_ROWS - 1, Math.max(0, Math.floor(y / rr.height * TP_ROWS)));
      var idx = row * TP_COLS + col;
      if (!tpCells[idx]) { tpCells[idx] = true; cells[idx].className = 'on'; $('tpN').textContent = Object.keys(tpCells).length; updateAuto(); }
      if (tpLast) {
        tpCtx.strokeStyle = e.buttons ? '#ffd34d' : '#6aa8ff'; tpCtx.lineWidth = e.buttons ? 4 : 2; tpCtx.lineCap = 'round';
        tpCtx.beginPath(); tpCtx.moveTo(tpLast[0], tpLast[1]); tpCtx.lineTo(x, y); tpCtx.stroke();
      }
      tpLast = [x, y];
    });
    tp.addEventListener('pointerleave', function () { tpLast = null; });
    tp.addEventListener('mousedown', function (e) { if (e.button === 0) tpFlag('left'); if (e.button === 2) tpFlag('right'); e.preventDefault(); });
    tp.addEventListener('contextmenu', function (e) { e.preventDefault(); tpFlag('right'); });
    tp.addEventListener('wheel', function (e) {
      e.preventDefault();
      if (e.ctrlKey) { tpFlag('zoom'); return; }
      if (e.deltaY < 0) tpFlag('up'); if (e.deltaY > 0) tpFlag('down');
      if (e.deltaX < 0) tpFlag('l'); if (e.deltaX > 0) tpFlag('r');
    }, { passive: false });
    tp.addEventListener('gesturestart', function (e) { e.preventDefault(); });
    tp.addEventListener('gesturechange', function (e) { e.preventDefault(); tpFlag('zoom'); });
    $('tpReset').addEventListener('click', function () { tpOpen(b); updateAuto(); });
  }
  window.addEventListener('wheel', function (e) { if (current === 'touchpad' && e.ctrlKey) e.preventDefault(); }, { passive: false });
  tests.touchpad = {
    hint: function () { return 'Поводьте пальцем по всьому полю, поки всі клітинки не стануть зеленими: незафарбовані місця означають мертві зони сенсора. Лінія має бути плавною, без стрибків. Перевірте лівий і правий клік, тап, прокрутку двома пальцями в усі боки та зведення-розведення двох пальців.'; },
    open: tpOpen,
    auto: function () {
      var n = Object.keys(tpCells).length, all = TP_COLS * TP_ROWS;
      var ok = [], no = [];
      TP_IND.forEach(function (x) { (tpFlags[x[0]] ? ok : no).push(x[1].toLowerCase()); });
      return 'зони сенсора: ' + n + ' з ' + all + (ok.length ? '; працює: ' + ok.join(', ') : '') + (no.length ? '; не перевірено: ' + no.join(', ') : '');
    },
    close: function () {}
  };

  // ---------------------------------------------------------------- збереження
  function toast(msg) {
    var t = document.createElement('div'); t.className = 'toast'; t.textContent = msg;
    document.body.appendChild(t);
    setTimeout(function () { t.remove(); }, 7000);
  }
  function save() {
    var pend = MANUAL.filter(function (m) { return !(DATA.manual[m.id] && DATA.manual[m.id].status); });
    if (pend.length && !confirm('Не пройдено ручні тести: ' + pend.map(function (m) { return m.name; }).join(', ') +
      '.\nВони потраплять у блок «Не вдалося перевірити».\n\nЗберегти звіт?')) return;
    var copy = JSON.parse(JSON.stringify(DATA));
    var s = summary();
    copy.final = true;
    copy.savedAt = new Date().toISOString();
    copy.summary = { verdict: s.verdict, fail: s.fail, warn: s.warn, ok: s.ok, skip: s.skip };
    var json = JSON.stringify(copy).replace(/</g, '\\u003c').replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
    var re = /(<script id="bibibi-data" type="application\/json">)[\s\S]*?(<\/script>)/;
    var html = ORIGINAL.replace(re, function (all, a, b) { return a + json + b; });
    var blob = new Blob([html], { type: 'text/html;charset=utf-8' });
    var a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = DATA.meta.filename || 'bibibi_report.html';
    document.body.appendChild(a); a.click();
    setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 5000);
    toast('Звіт збережено. Скрипт сам перенесе його на робочий стіл — дивіться в консоль.');
  }

  // ---------------------------------------------------------------- демо (коли сторінку відкрито без даних)
  function demoData() {
    return {
      version: 'demo', final: false,
      meta: { hostname: 'DEMO-PC', model: 'Демо-ноутбук', serial: 'DEMO123', os: 'демо', platform: '', datetime: new Date().toLocaleString('uk-UA'), duration: '0', filename: 'DEMO-PC - SN DEMO123.html' },
      results: [
        { cat: 'Батарея', test: 'Стан батареї', value: '41% від заводської ємності', status: 'fail' },
        { cat: 'Диск', test: 'Знос SSD', value: '72% ресурсу використано', status: 'warn' },
        { cat: 'Процесор', test: 'Продуктивність під навантаженням', value: 'частота стабільна', status: 'ok' },
        { cat: 'Система', test: 'TPM', value: 'датчик недоступний', status: 'skip' }
      ],
      specs: [{ k: 'Модель', v: 'Демо' }], manual: {}
    };
  }

  render();
})();
</script>
</body>
</html>
BIBIBI_TAIL_EOF
}

build_json() {
  local i n dur
  dur=$(( ($(date +%s) - START_TS + 30) / 60 ))
  printf '{"version":"%s","final":false,"meta":{' "$BIBIBI_VERSION"
  printf '"hostname":"%s","model":"%s","serial":"%s","os":"%s","platform":"%s",' \
    "$(jesc "$M_HOST")" "$(jesc "$M_MODEL")" "$(jesc "$M_SERIAL")" "$(jesc "$M_OS")" "$OS_KIND"
  printf '"date":"%s","datetime":"%s","duration":"%s","filename":"%s","user":"%s"},' \
    "$(date +%Y-%m-%d)" "$(date '+%d.%m.%Y %H:%M')" "$dur" "$(jesc "$REPORT_NAME")" "$(jesc "$CU")"
  printf '"results":['
  n=${#RS[@]}; i=0
  while [ "$i" -lt "$n" ]; do
    [ "$i" -gt 0 ] && printf ','
    printf '{"cat":"%s","test":"%s","value":"%s","status":"%s"}' "$(jesc "${RC[$i]}")" "$(jesc "${RT[$i]}")" "$(jesc "${RV[$i]}")" "${RS[$i]}"
    i=$((i+1))
  done
  printf '],"specs":['
  n=${#SK[@]}; i=0
  while [ "$i" -lt "$n" ]; do
    [ "$i" -gt 0 ] && printf ','
    printf '{"k":"%s","v":"%s"}' "$(jesc "${SK[$i]}")" "$(jesc "${SV[$i]}")"
    i=$((i+1))
  done
  printf '],"manual":{}}'
}

count_status() { local s c=0 x; s=$1; for x in "${RS[@]}"; do [ "$x" = "$s" ] && c=$((c+1)); done; echo $c; }

wait_final() {
  local base=$1 dir f has_tty=0 line verdict
  { : < /dev/tty; } 2>/dev/null && has_tty=1
  printf '\n%s%s>> Ручні тести%s\n' "$C_C" "$C_B" "$C_0"
  echo "   У браузері відкрився звіт. Пройдіть ручні тести (екран, звук, клавіатура, тачпад)"
  echo "   і натисніть «Зберегти звіт» — файл автоматично перенесеться на робочий стіл."
  echo "   ${C_D}Чекаю на фінальний звіт… (Enter — завершити без нього)${C_0}"
  SKIP_FLAG=0
  while [ "$ABORT" != 1 ] && [ "$SKIP_FLAG" != 1 ]; do
    for dir in "$U_DOWNLOADS" "$U_DESKTOP"; do
      [ -d "$dir" ] || continue
      for f in "$dir/$base"*.html; do
        [ -f "$f" ] || continue
        [ "$f" = "$REPORT_PATH" ] && continue
        [ "$f" -nt "$WORK/opened" ] || continue
        sleep 1
        grep -q '"final":true' "$f" 2>/dev/null || continue
        mv -f "$f" "$REPORT_PATH" && own "$REPORT_PATH"
        verdict=$(grep -o '"verdict":"[^"]*"' "$REPORT_PATH" | head -n 1 | sed 's/^"verdict":"//; s/"$//')
        line=$(grep -o '"summary":{[^}]*}' "$REPORT_PATH" | head -n 1)
        printf '\n'
        case $verdict in *КРИТИЧ*) printf '   %s%sВИСНОВОК: %s%s\n' "$C_R" "$C_B" "$verdict" "$C_0" ;;
                         *ЗАУВАЖ*) printf '   %s%sВИСНОВОК: %s%s\n' "$C_Y" "$C_B" "$verdict" "$C_0" ;;
                         *)        printf '   %s%sВИСНОВОК: %s%s\n' "$C_G" "$C_B" "$verdict" "$C_0" ;; esac
        printf '   Критично: %s · зауважень: %s · норма: %s · не перевірено: %s\n' \
          "$(printf '%s' "$line" | sed -n 's/.*"fail":\([0-9]*\).*/\1/p')" "$(printf '%s' "$line" | sed -n 's/.*"warn":\([0-9]*\).*/\1/p')" \
          "$(printf '%s' "$line" | sed -n 's/.*"ok":\([0-9]*\).*/\1/p')" "$(printf '%s' "$line" | sed -n 's/.*"skip":\([0-9]*\).*/\1/p')"
        printf '   %sФінальний звіт: %s%s\n' "$C_G" "$REPORT_PATH" "$C_0"
        return 0
      done
    done
    if [ "$has_tty" = 1 ]; then read -r -t 1 line < /dev/tty && break; else sleep 1; fi
  done
  printf '\n   %sФінальний звіт не збережено. На робочому столі лишився проміжний: %s%s\n' "$C_Y" "$REPORT_PATH" "$C_0"
}

cleanup() {
  [ "$CLEANED" = 1 ] && return; CLEANED=1
  [ -n "$CUR_PID" ] && kill_tree "$CUR_PID" 2>/dev/null
  rm -f /var/tmp/bibibi_disktest.tmp /private/var/tmp/bibibi_disktest.tmp 2>/dev/null
  [ "$OS_KIND" = linux ] && linux_remove_tools
  [ -n "$WORK" ] && rm -rf "$WORK"
  printf '\n%s   bibibi_test завершено.%s\n' "$C_M" "$C_0"
}

# ===================================================================== головна
main() {
  while [ $# -gt 0 ]; do
    case $1 in
      --no-browser) NO_BROWSER=1 ;;
      --cpu-seconds) shift; CPU_SECONDS=${1:-300} ;;
      --disk-mb) shift; DISK_MB=${1:-2048} ;;
      --quick) CPU_SECONDS=60; DISK_MB=512 ;;
    esac
    shift
  done
  case $(uname -s) in Darwin) OS_KIND=macos ;; Linux) OS_KIND=linux ;; *) echo "Непідтримувана система: $(uname -s)"; exit 1 ;; esac
  if [ "$(id -u)" -ne 0 ]; then
    echo "${C_R}bibibi_test потребує прав адміністратора.${C_0}"
    echo "Запустіть так:  sudo bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/w00o-o00w/bibibi_test/main/bibibi_test.sh)\""
    exit 1
  fi
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/bibibi.XXXXXX") || { echo "Не вдалося створити тимчасову папку"; exit 1; }
  trap cleanup EXIT
  trap on_int INT
  trap 'exit 143' TERM HUP
  START_TS=$(date +%s)

  printf '%s=====================================================%s\n' "$C_M" "$C_0"
  printf '%s   bibibi_test %s — тестування ноутбука (%s)%s\n' "$C_M" "$BIBIBI_VERSION" "$OS_KIND" "$C_0"
  printf '%s=====================================================%s\n' "$C_M" "$C_0"
  echo "   Тривалість: близько 15 хвилин. Ctrl+C — пропустити поточний тест,"
  echo "   двічі Ctrl+C — перервати все (звіт все одно буде)."
  detect_user
  echo "   ${C_D}Користувач: $CU · звіт буде на робочому столі: $U_DESKTOP${C_0}"
  write_template

  if [ "$OS_KIND" = linux ]; then
    printf '\n%s%s>> Підготовка%s\n' "$C_C" "$C_B" "$C_0"
    linux_prepare_tools
    run_test "Система" 60 t_system_linux
    run_test "Процесор, пам'ять, відео" 90 t_hw_linux
    run_test "Накопичувачі" 180 t_disks_linux
    run_test "Батарея" 60 t_battery_linux
    run_test "Мережа" 60 t_net_linux
    run_test "Периферія" 90 t_periph_linux
    run_test "Драйвери" 60 t_drivers_linux
    run_test "Журнал ядра" 60 t_logs_linux
  else
    run_test "Обліковий запис: iCloud, Знайти Mac, блокування" 120 t_account_mac
    run_test "Система" 120 t_system_mac
    run_test "Процесор, пам'ять, відео" 120 t_hw_mac
    run_test "Накопичувачі" 120 t_disks_mac
    run_test "Батарея" 90 t_battery_mac
    run_test "Мережа" 90 t_net_mac
    run_test "Периферія" 180 t_periph_mac
    run_test "Журнал macOS" 60 t_logs_mac
  fi
  run_test "Навантаження процесора ($(calc "$CPU_SECONDS/60" 1) хв)" $((CPU_SECONDS + 90)) t_stress
  run_test "Швидкість диска ($(calc "$DISK_MB/1024" 1) ГБ)" 900 t_diskspeed

  if [ "$OS_KIND" = linux ] && [ -n "$INSTALLED" ]; then
    printf '\n%s%s>> Прибирання%s\n' "$C_C" "$C_B" "$C_0"
    linux_remove_tools
  fi

  # ---------- проміжний звіт
  printf '\n%s%s>> Звіт%s\n' "$C_C" "$C_B" "$C_0"
  [ -z "$M_HOST" ] && M_HOST=$(hostname 2>/dev/null || uname -n)
  local sn base
  sn=$(safe_name "$M_SERIAL"); [ -z "$sn" ] && sn="невідомо"
  base="$(safe_name "$M_HOST") - SN $sn - $(date +%Y-%m-%d)"
  [ -e "$U_DESKTOP/$base.html" ] && base="$base $(date +%H-%M)"
  REPORT_NAME="$base.html"
  REPORT_PATH="$U_DESKTOP/$REPORT_NAME"
  if ! { cat "$WORK/tpl_head"; build_json; cat "$WORK/tpl_tail"; } > "$REPORT_PATH" 2>/dev/null; then
    if [ "$OS_KIND" = macos ]; then U_DESKTOP=/Users/Shared; else U_DESKTOP=$CU_HOME; fi
    REPORT_PATH="$U_DESKTOP/$REPORT_NAME"
    { cat "$WORK/tpl_head"; build_json; cat "$WORK/tpl_tail"; } > "$REPORT_PATH"
    echo "   ${C_Y}Не вдалося записати на робочий стіл — звіт збережено в $U_DESKTOP${C_0}"
  fi
  own "$REPORT_PATH"
  echo "   Автоматичні тести: критично $(count_status fail) · зауважень $(count_status warn) · не перевірено $(count_status skip)"
  echo "   ${C_G}Проміжний звіт: $REPORT_PATH${C_0}"

  [ "$NO_BROWSER" = 1 ] && return 0
  touch "$WORK/opened"; sleep 1
  if ! open_in_browser "$REPORT_PATH"; then
    echo "   ${C_Y}Не вдалося відкрити браузер автоматично — відкрийте файл вручну.${C_0}"
  fi
  wait_final "$base"
}

main "$@"
