#!/usr/bin/env bash

#########################################
#      _     ___   ____  ____ ____      #
#     | |   / _ \ / ___|/ ___/ ___|     #
#     | |  | | | | |  _| |  _\___ \     #
#     | |__| |_| | |_| | |_| |___) |    #
#     |_____\___/ \____|\____|____/     #
#                                       #
#########################################

function usage() {
  clear
  echo -e "
  Usage: \033[1m`basename $0` [conf] logfile\033[0m

  \033[1mlogfile\033[0m: A log file. Any log file. Big. Small. Gzipped. Any log file

  Once viewing the file, the following commands are available:
  - \033[1mSearch\033[0m: Press \033[4mSpace\033[0m to enter a regex to filter for.
  - \033[1mExclude\033[0m: Press \033[4mTAB\033[0m to enter a regex to exclude from the filter.
  - Navigate with the arrow keys, Home, End, PgUp and PgDown, or the mouse scrollwheel.
  - Press \033[4mF\033[0m to enter Find mode. Enter a search regex, then use PgUp and PgDown to cycle.
  - Press \033[4mG\033[0m to go to a line number.
  - Press \033[4mQ\033[0m or \033[4mCtrl+C\033[0m to exit.
  - Modes: \033[1;4mE\033[0mrrors      \033[1;4mW\033[0marnings          \033[1;4mI\033[0mnfo        \033[1;4mD\033[0mebug
           \033[1;4mO\033[0mther       \033[1;4mC\033[0mase sensitivity  \033[1;4mL\033[0mine wrap   \033[1;4mP\033[0mower scroll
  - Press \033[1;4m?\033[0m for help.

  \033[1mconf\033[0m: Edit the syntax highlighting and macro config file
  "
  read -sn1
  read -s -t 0.05
}

if [[ -z $1 ]]; then
  usage
  exit
fi

if [[ $1 == 'conf' ]]; then
  ed=$(cat .config/loggs | grep -i '# *config *editor *:' | cut -d: -f2 | sed 's/ //g')
  eval "$ed ~/.config/loggs"
  exit
fi

i=$1
esc=`echo -en '\033'`
tab=`echo -en '\t'`
flen=$(cat $i | wc -l)
line=0
hpos=0
fil=''
excl=''
dim="$esc[0;37m"
corner="[$esc[0;35m$i$dim]"
hostlist=$(zcat -f $i | awk '{print $4}' | sort | uniq | tr '\n' '|' | sed 's/|$//g')

# Default filters, 0/true = exclude, 1/false = include
exE=1 # Error
exW=1 # Warning
exI=1 # Info
exD=0 # Debug
exO=1 # Other
exC=1 # Case sensitive. 0=sensitive, 1=insensitive

mscroll='1' # 1=1, r=$rows
lwrap=1 # 0=wrap, 1=don't wrap
searchterm=''
searchnum=1
ar=$(mktemp /tmp/ar.XXX)
ff=$(mktemp /tmp/ff.XXX)
sr=$(mktemp /tmp/sr.XXX)
ffd=$(mktemp -d /tmp/ffd.XXX)

if [[ ! -e ~/.config/loggs ]]; then
  mkdir -p ~/.config
  cat <<EOF >> ~/.config/loggs
# Syntax highlighting:

#Name,         Colour,         Regex

Error,         1;31,           \[(ERR|ERROR|CRITICAL|FATAL)\]
Warning,       1;33,           \[(WARN|WARNING)\]
Info,          1;36,           \[(INFO|NOTICE)\]
Debug,         1;34,           \[DEBUG\]
Braces,        0;32,           [{}]
Python error,  0;32,           #012 *File|, line [0-9]*,
Paths,         2;33,           \/[A-Za-z_\.\/]*\/[A-Za-z0-9_\.\/]*
Date,          0;3;97,         (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) *[0-9]{1,2}
Date,          0;3;97,         20[0-9][0-9][\/\-][01][0-9][\/\-][0-3][0-9]
Time,          0;3;97,         [0-2][0-9]:[0-6][0-9]:[0-6][0-9]
IP,            1;91,           [12]?[0-9]?[0-9]\.[12]?[0-9]?[0-9]\.[12]?[0-9]?[0-9]\.[12]?[0-9]?[0-9]
UUID,          0;36,           [A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}


# Macros

#%FIND%,       --- %FIND% is a special macro. It transfers the search term into the filter/exclude field ---
%IP%,          [12]?[0-9]?[0-9]\.[12]?[0-9]?[0-9]\.[12]?[0-9]?[0-9]\.[12]?[0-9]?[0-9]
%UUID%,        [A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}

#Config Editor: vi

# Regexes must be properly formed extended regular expressions, or stuff will break.
EOF
fi

function buildsedstring() {
  cat ~/.config/loggs | egrep -v -e "^[#%].*" -e "^$" | while read -r line; do
    local colour="$esc[$(echo -e $line | cut -d, -f2 | sed 's/^ *//g')m"
    local regex=$(echo -e $line | cut -d, -f3-999 | sed 's/^ *//g; s/\\/\\\\/g')
    echo -en "s/($regex)/$colour\1$dim/g; "
  done
}
sedstring="$(buildsedstring | sed 's/; $//g')"

if [[ ! -f $i ]]; then
  echo -e "
  File \"$i\" not found.
  "
  exit
fi

rlen=$flen
[[ $flen -lt $rows ]] && flen=$rows

function bye() {
  echo -en "\e[?9l" # turn mouse off
  echo -en "\e[?7h" # turn wrap back on
  rm -f $ar
  rm -f $sr
  rm -f $ff
  rm -rf $ffd
  clear
  exit
}
trap bye SIGHUP SIGINT SIGQUIT SIGABRT

function termcheck() {
  rows=$(stty -a | grep -o 'rows [0-9]*;' | grep -o '[0-9]*')
  columns=$(stty -a | grep -o 'columns [0-9]*;' | grep -o '[0-9]*')
}

function tint() {
  [[ $exC -eq 0 ]] && local cS='i' || local cS='I'
  [[ -z $searchterm ]] && local st='sfasdfac!axq45bydsarq234214qadsc' || local st=$searchterm
  [[ -z $fil ]] && local fl='sfasdfac!axq45bydsarq234214qadsc' || local fl=$fil
  sed -r "
   $sedstring;
   s/($hostlist)/$esc[2;31m\1$dim/g;
   s/($fl)/$esc[0;1;4;30;97m\1$dim/g$cS;
   s/($st)/$esc[0;1;4;30;92m\1$dim/g$cS"
}

function macro() {
  cat ~/.config/loggs | egrep "$1" | sed 's/^%[A-Za-z0-9]*%, *//g'
}

function filter() {
  function ggrep() {
    [[ $exC -eq 0 ]] && egrep "$@" || egrep -i "$@"
  }
  function include() { [[ -z "$1" ]] && cat || ggrep "$1";} # because cat is faster than grep if you don't need to filter
  function exclude() { [[ -z "$1" ]] && cat || ggrep -v "$1";}
  local exMode=''
  [[ $exE -eq 0 ]] && exMode="ERR|ERROR|CRITICAL|FATAL|$exMode"
  [[ $exW -eq 0 ]] && exMode="WARN|WARNING|$exMode"
  [[ $exI -eq 0 ]] && exMode="INFO|NOTICE|$exMode"
  [[ $exD -eq 0 ]] && exMode="DEBUG|$exMode"
  exMode="$(echo $exMode | sed 's/^|//g; s/|$//g')"
  if [[ $exO -eq 0 ]]; then
    zcat -f $i | include "$fil" | exclude "$excl" | exclude "$exMode" | egrep '\[ERR|ERROR|CRITICAL|FATAL|WARN|WARNING|INFO|NOTICE|DEBUG\]' > $ff
  else
    zcat -f $i | include "$fil" | exclude "$excl" | exclude "$exMode" > $ff
  fi
  unset -f include
  unset -f ggrep
  unset -f exclude
  rm -f $ffd/ff*
  if [[ -s $ff ]]; then
    split $ff -d $ffd/ff
    local prev='/dev/null'
    for fl in $(ls -1 $ffd/); do         # Split the file into 1000 line sections, then add a 100 line overlap
      head -n100 "$ffd/$fl" >> $prev
      prev="$ffd/$fl"
    done
  else
    echo "No matching lines." > $ffd/ff01
  fi
}


function searchbar() {
  if [[ -n $searchterm ]]; then
    [[ ${#searchterm} -gt 16 ]] && local dsearchterm="${searchterm:0:15}…" || local dsearchterm=$searchterm
    echo -en "\e[1;97m[\e[1;92m$dsearchterm: $searchnum/$(cat $sr | wc -l)\e[1;97m]\e[0m"
  fi
}

function hwin() {
  local printedrows=0
  local actualrows=0
  if [[ $lwrap -eq 0 ]]; then
    while read hl; do
      local pl="$esc[1;92m---$esc[0m $hl"
      linelen=$(( $(( ${#hl} + 3 )) / columns + 1 ))
      printedrows=$(( printedrows + linelen ))
      actualrows=$(( actualrows + 1 ))
      [[ $printedrows -ge rows ]] && break
      echo "$pl"
    done
  else
    echo -en "\033[?7l"
    while read hl; do # line wrap is off, lines truncate
      echo "$esc[2K$([[ $hpos -gt 0 ]] && echo -en "$esc[1;32m| $dim")$(echo $hl | tail -c+$hpos) "
      actualrows=$(( actualrows + 1 ))
      printedrows=$(( printedrows + 1 ))
      [[ $printedrows -ge $rows ]] && break
    done
    echo -en "\033[?7h"
  fi
  if [[ $printedrows -lt $rows ]]; then # clear rest of screen if $printedrows < $rows
    echo -e '\033[J'
  fi
  echo $actualrows > $ar
}

function statusbar() {
  rw=$(cat $ar)
  lline=$(( line + rw ))
  [[ $exE -eq 1 ]] && local bE="$esc[0;1;91mE" || local bE="$esc[0;2;37mE"
  [[ $exW -eq 1 ]] && local bW="$esc[0;1;93mW" || local bW="$esc[0;2;37mW"
  [[ $exI -eq 1 ]] && local bI="$esc[0;1;96mI" || local bI="$esc[0;2;37mI"
  [[ $exD -eq 1 ]] && local bD="$esc[0;1;94mD" || local bD="$esc[0;2;37mD"
  [[ $exO -eq 1 ]] && local bO="$esc[0;1;97mO" || local bO="$esc[0;2;37mO"
  [[ $exC -eq 0 ]] && local bC="$esc[0;1;97mAa" || local bC="$esc[0;2;37mAa"
  [[ $mscroll == '1' ]] && local marrow="/" || local marrow="⥮"
  [[ ${#fil} -gt 16 ]] && local dfil="${fil:0:15}…" || local dfil=$fil
  [[ ${#excl} -gt 16 ]] && local dexcl="${excl:0:15}…" || local dexcl=$excl
  local bar="[$bC $bE$bW$bI$bD$bO $esc[0;4;97m$dfil$dim $esc[9;97m$dexcl$dim][$esc[0;97m$line-$lline $marrow $rlen$dim]"
  local offset=$(( columns - ${#bar} + 99 ))
  echo -ne "\033[${rows};${offset}H\033[2K${bar}"
}

function display() {
  termcheck
  echo -ne "\033[3J\033[1;1H"
  rw=$(cat $ar)
  echo -ne "\033[1;1H\033[?25l" # top left, cursor invisible
  rlen=$(cat $ff | wc -l)
  local searchcount=$(cat $sr | wc -l)
  if [[ -n $searchterm ]]; then
    [[ $searchnum -gt $searchcount ]] && searchnum=1
    [[ $searchnum -lt 1 ]] && searchnum=$searchcount
    [[ $pup -eq 1 ]] && line=$(( $(cat $sr | head -n $searchnum | tail -n1) - 3 ))
  fi
  if [[ $(( line + rw )) -ge $rlen ]]; then
    [[ $lwrap -eq 0 ]] && line=$(( rlen - rw )) || line=$(( rlen - rows ))
  fi
  [[ $line -lt 0 ]] && line=0
  [[ $hpos -lt 0 ]] && hpos=0
  local segment=$(( line / 1000 + 1))
  local segline=$(( line % 1000 ))
  segfile="$(ls -1 $ffd | head -n $segment | tail -n1)"
  [[ $exC -eq 0 ]] && local cS='i' || local cS='I'
  cat "$ffd/$segfile" | tail -n+$segline | hwin | tint
  statusbar
  echo -ne "\033[$rows;1H$corner\033[?25h" # corner block, make cursor visible again
  searchbar
}

trap display SIGWINCH


################################ Initialise

filter
display

while true; do
  echo -en "\e[?9h" # turn mouse on
  a=
  while [[ -z $a ]]; do # this loop enables the SIGWINCH detection
    IFS= read -sn1 -t 0.1 a
  done
  IFS= read -sn1 -t 0.01 b
  IFS= read -sn1 -t 0.01 c
  IFS= read -sn1 -t 0.01 d
  IFS= read -s -t 0.01 r
  echo -en "\e[?9l" # turn mouse off
  [[ $mscroll == '1' ]] && mp=3 || mp=$(( rlen / 100 + 3 ))
  rw=$(cat $ar)
  pup=0
  case $a in
    e ) [[ $exE -eq 0 ]] && exE=1 || exE=0; line=0; hpos=0; filter; display ;;      # toggle ERROR
    w ) [[ $exW -eq 0 ]] && exW=1 || exW=0; line=0; hpos=0; filter; display ;;      # toggle WARNING
    i ) [[ $exI -eq 0 ]] && exI=1 || exI=0; line=0; hpos=0; filter; display ;;      # toggle INFO
    d ) [[ $exD -eq 0 ]] && exD=1 || exD=0; line=0; hpos=0; filter; display ;;      # toggle DEBUG
    o ) [[ $exO -eq 0 ]] && exO=1 || exO=0; line=0; hpos=0; filter; display ;;      # toggle Other
    E ) exE=1; exW=0; exI=0; exD=0; exO=0; line=0; hpos=0; filter; display ;;       # only ERROR
    W ) exE=0; exW=1; exI=0; exD=0; exO=0; line=0; hpos=0; filter; display ;;       # only WARNING
    I ) exE=0; exW=0; exI=1; exD=0; exO=0; line=0; hpos=0; filter; display ;;       # only INFO
    D ) exE=0; exW=0; exI=0; exD=1; exO=0; line=0; hpos=0; filter; display ;;       # only DEBUG
    O ) exE=0; exW=0; exI=0; exD=0; exO=1; line=0; hpos=0; filter; display ;;       # only Other
    C | c ) [[ $exC -eq 0 ]] && exC=1 || exC=0; line=0; hpos=0; filter; display ;;  # Case sensitivity
    L | l ) clear; [[ $lwrap -eq 0 ]] && lwrap=1 || lwrap=0; display ;;             # Line wrap
    P | p ) [[ $mscroll == '1' ]] && mscroll='r' || mscroll='1'; clear; display ;;  # Power scroll
    Q | q ) bye ;;
    S | s ) echo -en "\e[?9l"; IFS= read -sn1 aa; IFS= read -s -t 0.01 r ;;         # briefly turn mouse off so you can select
    $esc )
      if [[ $b == '[' ]]; then                        # Navigation
        case $c in
          A ) line=$(( line - 1 )) ;;                                                                     # Up arrow
          B ) line=$(( line + 1 )) ;;                                                                     # Down arrow
          C ) hpos=$(( hpos + (columns/4) )) ;;                                                           # Right arrow
          D ) hpos=$(( hpos - (columns/4) )) ;;                                                           # Left arrow
          5 ) [[ -z $searchterm ]] && line=$(( line - rw )) || searchnum=$(( searchnum - 1 )); pup=1 ;;   # PgUp
          6 ) [[ -z $searchterm ]] && line=$(( line + rw )) || searchnum=$(( searchnum + 1 )); pup=1 ;;   # PgDown
          H ) line=0 ;;                                                                                   # Home
          F ) line=$(( rlen - rw )) ;;                                                                    # End
          # Z ) echo "you pressed shift+tab" ;;                                                           # Shift+tab
          M )
          case $d in                                                                                    # Mouse
            '`' ) line=$(( line - mp )) ;;                                                                # scroll up
            'a' ) line=$(( line + mp )) ;;                                                                # scroll down
          esac
          ;;
        esac
      fi
      if [[ -z $b && -z $searchterm ]]; then
        fil=''
        excl=''
        filter
      fi
      if [[ -z $b && -n $searchterm ]]; then
        searchterm=''
      fi
      display
    ;;
    G | g )
      echo -ne "\033[1K\033[$rows;1H\033[1;97m"
      read -e -p " Go to Line: " gtl
      if [[ $gtl =~ [0-9][0-9]* ]]; then
        hpos=0
        line=$gtl
      else
        echo -ne "\033[1K\033[$rows;1H\033[1;97m Not a line number."
        read -sn1 -t 1 aa
      fi
      display
    ;;
    F | f )
      echo -ne "\033[1K\033[$rows;1H\033[1;97m"
      read -re -i "$searchterm" -p " Find: " st
      [[ $st =~ %[A-Za-z1-9]*% ]] && searchterm="$(macro "${st^^}")" || searchterm="$st"
      searchnum=1
      if [[ $exC -eq 0 ]]; then
        egrep -n "$searchterm" $ff | cut -d: -f1 > $sr
      else
        egrep -in "$searchterm" $ff | cut -d: -f1 > $sr
      fi
      display
    ;;
    $tab )
      echo -ne "\033[1K\033[$rows;1H\033[1;97m"
      read -re -i "$excl" -p " Exclude: " excl
      case ${excl^^} in
        %FIND% ) excl=$searchterm; searchterm='' ;;
        %*% ) excl="$(macro "${excl^^}" )" ;;
      esac
      filter
      line=0
      display
    ;;
    ' ' )
      echo -ne "\033[1K\033[$rows;1H \033[1;97m"
      read -re -i "$fil" -p " Filter: " fil
      case ${fil^^} in
        %FIND% ) fil=$searchterm; searchterm='' ;;
        %*% ) fil="$(macro "${fil^^}" )" ;;
      esac
      filter
      line=0
      display
    ;;
    '?' )
      clear
      echo -e '\n\n\n'
      usage
      display
    ;;
  esac
done
