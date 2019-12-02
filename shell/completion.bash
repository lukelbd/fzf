#     ____      ____
#    / __/___  / __/
#   / /_/_  / / /_
#  / __/ / /_/ __/
# /_/   /___/_/-completion.bash
#
# - $FZF_TMUX               (default: 0)
# - $FZF_TMUX_HEIGHT        (default: '40%')
# - $FZF_COMPLETION_TRIGGER (default: '**')
# - $FZF_COMPLETION_OPTS    (default: empty)
#
################################################################################
# lukelbd edits
# * Goal is to set completion trigger to '' (always on), bind tab key to
#   'cancel', and use the completion option 'maxdepth 1' -- this enables us
#   to succissively toggle completion on and off with tab, and lets us fuzzy
#   search the depth-1 directory contents.
# * To make this more similar to bash completion, have modified
#   __fzf_generic_path_completion to *test* whether an entry is a directory
#   or file. If it is a directory, we append it with a slash (and no space,
#   like in _fzf_dir_completion). If it is a file, we append it with zero
#   space. That way if you select a directory, you can immediately press tab
#   again to search *this* directory. This can be *critical* for huge
#   directory trees (e.g. $HOME). Inicidentally this means a complete command invoking
#   __fzf_generic_path_completion must *always* be called with the option
#   -o nospace -- spaces are added dynamically if the item is not a directory.
################################################################################
# General functions, helper functions
###########################################################
# Function for parsing new command-line option -- list of files to ignore
# For example, .DS_Store
_fzf_ignore() {
  if [ -z "$1" ]; then
    echo -false # -not -false == -true
  else
    echo -name $(echo "$1" | xargs | sed 's/ / -o -name /g')
  fi
}
# Similar idea here
_fzf_include() {
  if [ -z "$1" ]; then
    echo -true
  else
    echo -name $(echo "$1" | xargs | sed 's/ / -o -name /g')
  fi
}

# To use custom commands instead of find, override _fzf_compgen_{path,dir}
# They accept one argument -- the base directory
# Below prunes results in git directories, enforces some user variables,
# prunes input directory itself from find result, and remove leading './'
_fzf_compgen_path() {
  command find -L "$1" \
    $FZF_COMPLETION_FIND_OPTS \
    -name .git -prune -o -name .svn -prune -o \( -type d -o -type f -o -type l \) \
    -a -not \( $(_fzf_ignore $FZF_COMPLETION_FIND_IGNORE) \) \
    -a \( $(_fzf_include $FZF_COMPLETION_FIND_INCLUDE) \) \
    -a -not -path "$1" -print 2> /dev/null | sed 's@^\./@@'
}

_fzf_compgen_dir() {
  command find -L "$1" \
    $FZF_COMPLETION_FIND_OPTS \
    -name .git -prune -o -name .svn -prune -o -type d \
    -a -not \( $(_fzf_ignore $FZF_COMPLETION_FIND_IGNORE) \) \
    -a \( $(_fzf_include $FZF_COMPLETION_FIND_INCLUDE) \) \
    -a -not -path "$1" -print 2> /dev/null | sed 's@^\./@@'
}

# To redraw line after fzf closes (printf '\e[5n')
bind '"\e[0n": redraw-current-line'

# Fallback completion function
__fzf_orig_completion_filter() {
  # Records _fzf_orig_completion_[command]="complete <opts> -F function #<command>"
  # Also if has a 'nospace' option, and not already in the string, add to __fzf_nospace_commands string
  sed 's/^\(.*-F\) *\([^ ]*\).* \([^ ]*\)$/export _fzf_orig_completion_\3="\1 %s \3 #\2"; [[ "\1" = *" -o nospace "* ]] \&\& [[ ! "$__fzf_nospace_commands" = *" \3 "* ]] \&\& __fzf_nospace_commands="$__fzf_nospace_commands \3 ";/' |
  awk -F= '{OFS = FS} {gsub(/[^A-Za-z0-9_= ;]/, "_", $1);}1'
}

# Handle previous completion funcs or something
_fzf_handle_dynamic_completion() {
  local cmd ret orig orig_var orig_cmd orig_complete
  cmd="$1"
  shift
  orig_cmd="$1"
  orig_var="_fzf_orig_completion_$cmd"
  orig="${!orig_var##*#}" # trim comment
  if [ -n "$orig" ] && type "$orig" > /dev/null 2>&1; then
    $orig "$@" # call completion command
  elif [ -n "$_fzf_completion_loader" ]; then
    orig_complete=$(complete -p "$cmd" 2> /dev/null)
    _completion_loader "$@"
    ret=$?
    # _completion_loader may not have updated completion for the command
    if [ "$(complete -p "$cmd" 2> /dev/null)" != "$orig_complete" ]; then
      eval "$(complete | command grep " -F.* $orig_cmd$" | __fzf_orig_completion_filter)"
      if [[ "$__fzf_nospace_commands" = *" $orig_cmd "* ]]; then
        eval "${orig_complete/ -F / -o nospace -F }"
      else
        eval "$orig_complete"
      fi
    fi
    return $ret
  fi
}

# The name of FZF command
__fzfcmd_complete() {
  [ -n "$TMUX_PANE" ] && [ "${FZF_TMUX:-0}" != 0 ] && [ ${LINES:-40} -gt 15 ] &&
    echo "fzf-tmux -d${FZF_TMUX_HEIGHT:-40%}" || echo "fzf"
}

# Path completion
# Now takes just two arguments -- the compgen command, and fzf options
__fzf_generic_path_completion() {
  local cur base dir leftover matches trigger cmd fzf opts end varcomp generator
  fzf="$(__fzfcmd_complete)"
  cmd="${COMP_WORDS[0]//[^A-Za-z0-9_=]/_}"
  COMPREPLY=()
  trigger=${FZF_COMPLETION_TRIGGER-'**'}
  [ ${#COMP_WORDS[@]} -ge 1 ] && cur="${COMP_WORDS[COMP_CWORD]}" # cmd line word under cursor
  # Complete paths and variables
  varcomp=false
  [[ "$cur" == '$'* ]] && varcomp=true
  if [[ "$cur" == *"$trigger" ]]; then
    base=${cur:0:${#cur}-${#trigger}}
    eval "base=$base"
    [[ $base = *"/"* ]] && dir="$base"
    while true; do
      if [ -z "$dir" ] || [ -d "$dir" ]; then
        # Changed functionality here: make suffix dependent on whether
        # or not the item is a directory -- if so, slash, if not, space
        leftover=${base/#"$dir"}
        leftover=${leftover/#\/}
        [ -z "$dir" ] && dir='.'
        count=0
        if $varcomp; then # variable completion
          generator="compgen -v"
          leftover="${cur:1}"
          opts="+m" # one at a time!
        else
          generator="$1 $(printf %q "$dir")"
          opts="$2"
        fi
        matches=$(eval "$generator" | tr -s '/' | FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-40%} --reverse $FZF_DEFAULT_OPTS $FZF_COMPLETION_OPTS" $fzf $opts -q "$leftover" | while read -r item; do
          let count+=1
          if [ -d "$item" ]; then printf "%q/" "$item" | tr -s '/'
          else printf "%q " "$item"
          fi
          done)
        $varcomp && matches="${matches%% *}" # trim spaces!
        # If the command (i.e. word on first line of shell) is a
        # nospace command, add space.... what? This must be a bug, right?
        # [[ "$__fzf_nospace_commands" = *" ${COMP_WORDS[0]} "* ]] && matches="$matches "
        if [ -n "$matches" ]; then
          if $varcomp; then
            COMPREPLY=( "${!matches}" )
          else
            COMPREPLY=( "$matches" )
          fi
        else
          COMPREPLY=( "$cur" )
        fi
        printf '\e[5n' # redraws terminal line
        return 0
      fi
      dir=$(dirname "$dir")
      [[ "$dir" =~ /$ ]] || dir="$dir"/
    done
  # Trigger not active, defer to default completion
  else
    shift
    shift
    _fzf_handle_dynamic_completion "$cmd" "$@"
  fi
}

# Generic completion, suitable for more special cases
_fzf_complete() {
  local cur selected trigger cmd fzf post
  post="$(caller 0 | awk '{print $2}')_post"   # the func name, with a _post suffix
  type -t "$post" > /dev/null 2>&1 || post=cat # empty
  fzf="$(__fzfcmd_complete)"
  cmd="${COMP_WORDS[0]//[^A-Za-z0-9_=]/_}"
  trigger=${FZF_COMPLETION_TRIGGER-'**'}
  cur="${COMP_WORDS[COMP_CWORD]}"
  # Trigger active, collect standard input (the lone 'cat') and
  # run fzf with those options
  if [[ "$cur" == *"$trigger" ]]; then
    cur=${cur:0:${#cur}-${#trigger}}
    selected=$(cat | FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-40%} --reverse $FZF_DEFAULT_OPTS $FZF_COMPLETION_OPTS" $fzf $1 -q "$cur" | $post | tr '\n' ' ')
    selected=${selected% } # Strip trailing space not to repeat "-o nospace"
  # Trigger not active, defer to default completion
    if [ -n "$selected" ]; then
      COMPREPLY=("$selected")
    else
      COMPREPLY=("$cur")
    fi
    printf '\e[5n'
    return 0
  else
    shift
    _fzf_handle_dynamic_completion "$cmd" "$@"
  fi
}

###########################################################
# Completion functions
###########################################################
# Dunno what this does
if type _completion_loader > /dev/null 2>&1; then
  _fzf_completion_loader=1
fi

# Generic path completion
# Function to pass to 'complete -F [function]', receive command line
# text. Arg 1 is worker function, arg 2 are fzf executable commands.
# NOTE: Flag -m enables multi-select, +m disables it
_fzf_path_completion() {
  __fzf_generic_path_completion _fzf_compgen_path "-m" "$@"
}
complete -DE -F _fzf_path_completion -o nospace -o default -o bashdefault # ideal, but this seems to break stuff

# Directory name completion
# TODO: Disable the environment variables
_fzf_dir_completion() {
  __fzf_generic_path_completion _fzf_compgen_dir "+m" "$@"
}
_commands="${FZF_COMPLETION_DIR_COMMANDS:-cd pushd rmdir}"
for _cmd in $_commands; do
  complete -F _fzf_dir_completion -o nospace -o dirnames "$_cmd"
done

# Bindings completion
_fzf_complete_bindings() {
  _fzf_complete '+m' "$@" < <(bind -l)
}
complete -F _fzf_complete_bindings 'bind'


# Process id completion
# TODO: Expand to other versions of 'kill' command
_fzf_complete_kill() {
  [ -n "${COMP_WORDS[COMP_CWORD]}" ] && return 1

  local selected fzf
  fzf="$(__fzfcmd_complete)"
  selected=$(command ps -ef | sed 1d | FZF_DEFAULT_OPTS="--height ${FZF_TMUX_HEIGHT:-50%} --min-height 15 --reverse $FZF_DEFAULT_OPTS --preview 'echo {}' --preview-window down:3:wrap $FZF_COMPLETION_OPTS" $fzf -m | awk '{print $2}' | tr '\n' ' ')
  printf '\e[5n'

  if [ -n "$selected" ]; then
    COMPREPLY=( "$selected" )
    return 0
  fi
}
complete -F _fzf_complete_kill -o nospace -o default -o bashdefault kill

# Host completion
_fzf_complete_telnet() {
  _fzf_complete '+m' "$@" < <(
    command grep -v '^\s*\(#\|$\)' /etc/hosts | command grep -Fv '0.0.0.0' |
        awk '{if (length($2) > 0) {print $2}}' | sort -u
  )
}
complete -F _fzf_complete_telnet -o default -o bashdefault telnet

# SSH completion
_fzf_complete_ssh() {
  _fzf_complete '+m' "$@" < <(
    cat <(cat ~/.ssh/config /etc/ssh/ssh_config 2> /dev/null | command grep -i '^host ' | command grep -v '[*?]' | awk '{for (i = 2; i <= NF; i++) print $1 " " $i}') \
        <(command grep -oE '^[[a-z0-9.,:-]+' ~/.ssh/known_hosts | tr ',' '\n' | tr -d '[' | awk '{ print $1 " " $1 }') \
        <(command grep -v '^\s*\(#\|$\)' /etc/hosts | command grep -Fv '0.0.0.0') |
        awk '{if (length($2) > 0) {print $2}}' | sort -u
  )
}
complete -F _fzf_complete_ssh    -o default -o bashdefault ssh

# FZF option completion
# Change default behavior, now always complete options whether
# or not dash on line, and always use fuzzy complete
_fzf_opts_completion() {
  local cur prev opts
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  case "${prev}" in
    --tiebreak) opts="length begin end index" ;;
    --color)    opts="dark light 16 bw"       ;;
    *)          opts="
    -x --extended
    -e --exact
    --algo
    -i +i
    -n --nth
    --with-nth
    -d --delimiter
    +s --no-sort
    --tac
    --tiebreak
    -m --multi
    --no-mouse
    --bind
    --cycle
    --no-hscroll
    --jump-labels
    --height
    --literal
    --reverse
    --margin
    --inline-info
    --prompt
    --header
    --header-lines
    --ansi
    --tabstop
    --color
    --no-bold
    --history
    --history-size
    --preview
    --preview-window
    -q --query
    -1 --select-1
    -0 --exit-0
    -f --filter
    --print-query
    --expect
    --sync"
  esac
  _fzf_complete '-m' "$@" < <(compgen -W "$opts")
}
_fzf_opts_completion_post() {
  cat /dev/stdin | cut -d' ' -f1
}
complete -F _fzf_opts_completion 'fzf'

# Commands completion, including executables on PATH and functions
_fzf_complete_commands() {
  ! [ -r $HOME/.commands ] && compgen -c | grep -v '[!.:{}]' >$HOME/.commands
  _fzf_complete '+m' "$@" < <(cat $HOME/.commands)
}
complete -F _fzf_complete_commands 'help'
complete -F _fzf_complete_commands 'man'
complete -F _fzf_complete_commands 'type'
complete -F _fzf_complete_commands 'which'

# Shell option completion
_fzf_complete_shopt() {
  _fzf_complete '+m' "$@" < <(shopt | cut -d' ' -f1 | cut -d$'\t' -f1)
}
complete -F _fzf_complete_shopt 'shopt'

# Anything
__fzf_defc() {
  local cmd func opts orig_var orig def
  cmd="$1"
  func="$2"
  opts="$3"
  orig_var="_fzf_orig_completion_${cmd//[^A-Za-z0-9_]/_}"
  orig="${!orig_var}"
  if [ -n "$orig" ]; then
    printf -v def "$orig" "$func"
    eval "$def"
  else
    complete -F "$func" $opts "$cmd"
  fi
}
for cmd in $a_cmds; do
  __fzf_defc "$cmd" _fzf_path_completion "-o default -o bashdefault"
done
for cmd in $d_cmds; do
  __fzf_defc "$cmd" _fzf_dir_completion "-o nospace -o dirnames"
done

# Alias completion
_fzf_complete_aliases() {
  _fzf_complete '+m' "$@" < <(compgen -a)
}
complete -F _fzf_complete_aliases 'alias'
complete -F _fzf_complete_aliases 'unalias'

# Function name completion
_fzf_complete_functions() {
  _fzf_complete '+m' "$@" < <(compgen -a)
}
complete -F _fzf_complete_functions 'function'

# Exported variable name completion
_fzf_complete_variables() {
  _fzf_complete '+m' "$@" < <(compgen -v)
}
complete -F _fzf_complete_variables 'unset'
complete -F _fzf_complete_variables 'export'

# Git completion, includes command names
_fzf_complete_git() {
  _fzf_complete '+m' "$@" < <(cat <(_fzf_compgen_path .) \
    <(git commands | sed 's/$/ ::command/g' | column -t))
}
_fzf_complete_git_post() {
  cat | sed 's/::command *$//g' | sed 's/ *$//g'
}
complete -F _fzf_complete_git git

# CDO completion, includes command names
# WARNING: For some reason mac sed fails in regex
# search for 's/ \+(.*) *$' but not GNU sed, so break this in two
_fzf_complete_cdo() {
  _fzf_complete '+m' "$@" < <(cat <(_fzf_compgen_path .) \
    <(cdo --operators | sed 's/[ ]*[^ ]*$//g' | \
      sed 's/^\([^ ]*[ ]*\)\(.*\)$/\1(\2) /g' | \
      tr '[:upper:]' '[:lower:]'))
}
_fzf_complete_cdo_post() {
  cat | sed 's/(.*) *$//g' | sed 's/ *$//g'
}
complete -F _fzf_complete_cdo cdo

# Tool to bulk apply completion with file extension filtering
# For info on 'find' commands see: https://unix.stackexchange.com/a/15309/112647
# _ext='image'
# _filter='\( -iname \*.jpg -o -iname \*.png -o -iname \*.gif -o -iname \*.svg -o -iname \*.eps -o -iname \*.pdf \)' ;;
# eval "_fzf_compgen_$_ext() {
#   command find -L \"\$1\" \
#     \$FZF_COMPLETION_FIND_OPTS \
#     -name .git -prune -o -name .svn -prune -o \\( -type d -o -type f -o -type l \\) \
#     -a $_filter -a -not -path \"\$1\" -print 2> /dev/null | sed 's@^\\./@@'
# }"
# __fzf_generic_path_completion _fzf_compgen_image "-m" "$@"
# complete -o nospace -F _fzf_complete_image 'command'

# Mysterious function added recently
_fzf_setup_completion() {
  local kind fn cmd
  kind=$1
  fn=_fzf_${1}_completion
  if [[ $# -lt 2 ]] || ! type -t "$fn" > /dev/null; then
    echo "usage: ${FUNCNAME[0]} path|dir COMMANDS..."
    return 1
  fi
  shift
  for cmd in "$@"; do
    eval "$(complete -p "$cmd" 2> /dev/null | grep -v "$fn" | __fzf_orig_completion_filter)"
    case "$kind" in
      dir) __fzf_defc "$cmd" "$fn" "-o nospace -o dirnames" ;;
      *)   __fzf_defc "$cmd" "$fn" "-o default -o bashdefault" ;;
    esac
  done
}
