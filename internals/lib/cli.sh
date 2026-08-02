#!/usr/bin/env bash
# Shared operator argv parsing (ADR-0039).
# Grammar: positionals, then flags (flag order free). Optional rest: peel known
# flags from anywhere; remaining tokens preserved (ssh-style passthrough).
# Sourced by operator entrypoints. Bash 3.2-safe (no assoc arrays / namerefs).
#
# cli_parse <prefix> <spec...> -- "$@"
# cli_operator_parse <prefix> <spec...> -- "$@"   # same, always adds flag:env:value
#
# Spec tokens:
#   pos:<name>:required|optional
#   flag:<name>:bool
#   flag:<name>:value
#   flag:<name>:value:required
#   rest:<name>
#
# Results: PREFIX_<name> (pos/bool 0|1 / value string), PREFIX_<name>_set (value flags),
# PREFIX_<restname> as a Bash array when rest is declared.

cli_parse() {
  local prefix="${1-}"
  shift || true
  if [[ -z "${prefix}" ]]; then
    echo "FAIL: cli_parse: prefix required" >&2
    return 1
  fi

  local -a pos_names=() pos_req=()
  local -a flag_names=() flag_kinds=() flag_req=()
  local rest_name=""
  local saw_optional_pos=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --)
        shift
        break
        ;;
      pos:*)
        local spec="${1#pos:}"
        local pname="${spec%%:*}"
        local pmode="${spec#*:}"
        if [[ -z "${pname}" || "${pname}" == "${spec}" ]]; then
          echo "FAIL: cli_parse: bad pos spec '$1'" >&2
          return 1
        fi
        case "${pmode}" in
          required)
            if [[ "${saw_optional_pos}" == true ]]; then
              echo "FAIL: cli_parse: required positional after optional" >&2
              return 1
            fi
            pos_names+=("${pname}")
            pos_req+=(1)
            ;;
          optional)
            saw_optional_pos=true
            pos_names+=("${pname}")
            pos_req+=(0)
            ;;
          *)
            echo "FAIL: cli_parse: bad pos mode in '$1'" >&2
            return 1
            ;;
        esac
        shift
        ;;
      flag:*)
        local fspec="${1#flag:}"
        local fname="${fspec%%:*}"
        local restf="${fspec#*:}"
        if [[ -z "${fname}" || "${fname}" == "${fspec}" ]]; then
          echo "FAIL: cli_parse: bad flag spec '$1'" >&2
          return 1
        fi
        local fkind freql=0
        case "${restf}" in
          bool)
            fkind=bool
            ;;
          value)
            fkind=value
            ;;
          value:required)
            fkind=value
            freql=1
            ;;
          *)
            echo "FAIL: cli_parse: bad flag kind in '$1'" >&2
            return 1
            ;;
        esac
        flag_names+=("${fname}")
        flag_kinds+=("${fkind}")
        flag_req+=("${freql}")
        shift
        ;;
      rest:*)
        rest_name="${1#rest:}"
        if [[ -z "${rest_name}" ]]; then
          echo "FAIL: cli_parse: bad rest spec '$1'" >&2
          return 1
        fi
        if [[ ${#pos_names[@]} -gt 0 ]]; then
          echo "FAIL: cli_parse: rest cannot combine with positionals" >&2
          return 1
        fi
        shift
        ;;
      *)
        echo "FAIL: cli_parse: unexpected spec token '$1'" >&2
        return 1
        ;;
    esac
  done

  # Initialize results under set -u.
  local i name got setv _CLI_SHIFT
  i=0
  while [[ "${i}" -lt ${#pos_names[@]} ]]; do
    name="${pos_names[i]}"
    eval "${prefix}_${name}=\"\""
    i=$((i + 1))
  done
  i=0
  while [[ "${i}" -lt ${#flag_names[@]} ]]; do
    name="${flag_names[i]}"
    if [[ "${flag_kinds[i]}" == bool ]]; then
      eval "${prefix}_${name}=0"
    else
      eval "${prefix}_${name}=\"\""
      eval "${prefix}_${name}_set=0"
    fi
    i=$((i + 1))
  done
  if [[ -n "${rest_name}" ]]; then
    eval "${prefix}_${rest_name}=()"
  fi

  _cli_flag_index() {
    local want="$1"
    local j=0
    while [[ "${j}" -lt ${#flag_names[@]} ]]; do
      if [[ "${flag_names[j]}" == "${want}" ]]; then
        printf '%s\n' "${j}"
        return 0
      fi
      j=$((j + 1))
    done
    return 1
  }

  # Sets _CLI_SHIFT to 1 or 2 on success. Return 0 ok, 1 fail (set -e safe).
  _cli_bind_flag() {
    local tok="$1"
    local next="${2-}"
    local fname fval idx kind already
    _CLI_SHIFT=1
    if [[ "${tok}" == --*=* ]]; then
      fname="${tok#--}"
      fname="${fname%%=*}"
      fval="${tok#*=}"
      idx="$(_cli_flag_index "${fname}")" || {
        echo "FAIL: unknown flag: --${fname}" >&2
        return 1
      }
      kind="${flag_kinds[idx]}"
      if [[ "${kind}" == bool ]]; then
        echo "FAIL: flag --${fname} does not take a value" >&2
        return 1
      fi
      if [[ -z "${fval}" ]]; then
        echo "FAIL: --${fname} requires a value" >&2
        return 1
      fi
      eval "already=\"\${${prefix}_${fname}_set}\""
      if [[ "${already}" == "1" ]]; then
        echo "FAIL: duplicate --${fname}" >&2
        return 1
      fi
      eval "${prefix}_${fname}=\"\${fval}\""
      eval "${prefix}_${fname}_set=1"
      return 0
    fi

    if [[ "${tok}" != --* ]]; then
      echo "FAIL: cli_parse: internal: not a flag: ${tok}" >&2
      return 1
    fi
    fname="${tok#--}"
    idx="$(_cli_flag_index "${fname}")" || {
      echo "FAIL: unknown flag: --${fname}" >&2
      return 1
    }
    kind="${flag_kinds[idx]}"
    if [[ "${kind}" == bool ]]; then
      eval "${prefix}_${fname}=1"
      return 0
    fi
    if [[ -z "${next}" || "${next}" == --* ]]; then
      echo "FAIL: --${fname} requires a value" >&2
      return 1
    fi
    eval "already=\"\${${prefix}_${fname}_set}\""
    if [[ "${already}" == "1" ]]; then
      echo "FAIL: duplicate --${fname}" >&2
      return 1
    fi
    eval "${prefix}_${fname}=\"\${next}\""
    eval "${prefix}_${fname}_set=1"
    _CLI_SHIFT=2
    return 0
  }

  if [[ -n "${rest_name}" ]]; then
    # Rest mode: peel known flags from anywhere; other tokens → rest array.
    while [[ $# -gt 0 ]]; do
      local tok="$1"
      if [[ "${tok}" == -- ]]; then
        shift
        while [[ $# -gt 0 ]]; do
          eval "${prefix}_${rest_name}+=(\"\$1\")"
          shift
        done
        break
      fi
      if [[ "${tok}" == --* ]]; then
        if ! _cli_bind_flag "${tok}" "${2-}"; then
          return 1
        fi
        shift "${_CLI_SHIFT}"
        continue
      fi
      eval "${prefix}_${rest_name}+=(\"\$tok\")"
      shift
    done
  else
    # Strict mode: positionals, then flags only.
    local pos_i=0
    local phase=pos
    while [[ $# -gt 0 ]]; do
      local tok="$1"
      if [[ "${phase}" == pos ]]; then
        if [[ "${tok}" == -- ]]; then
          phase=flags
          shift
          continue
        fi
        if [[ "${tok}" == --* ]]; then
          if [[ "${pos_i}" -lt ${#pos_names[@]} ]]; then
            local need_more=false
            local k="${pos_i}"
            while [[ "${k}" -lt ${#pos_names[@]} ]]; do
              if [[ "${pos_req[k]}" -eq 1 ]]; then
                need_more=true
                break
              fi
              k=$((k + 1))
            done
            if [[ "${need_more}" == true ]]; then
              echo "FAIL: flag before positional: ${tok}" >&2
              return 1
            fi
          fi
          phase=flags
          continue
        fi
        if [[ "${pos_i}" -ge ${#pos_names[@]} ]]; then
          echo "FAIL: unexpected positional: ${tok}" >&2
          return 1
        fi
        eval "${prefix}_${pos_names[pos_i]}=\"\${tok}\""
        pos_i=$((pos_i + 1))
        shift
        continue
      fi

      # flags phase
      if [[ "${tok}" == -- ]]; then
        echo "FAIL: unexpected '--' after flags" >&2
        return 1
      fi
      if [[ "${tok}" != --* ]]; then
        echo "FAIL: unexpected positional after flags: ${tok}" >&2
        return 1
      fi
      if ! _cli_bind_flag "${tok}" "${2-}"; then
        return 1
      fi
      shift "${_CLI_SHIFT}"
    done

    # Required positionals
    i=0
    while [[ "${i}" -lt ${#pos_names[@]} ]]; do
      if [[ "${pos_req[i]}" -eq 1 ]]; then
        eval "got=\"\${${prefix}_${pos_names[i]}}\""
        if [[ -z "${got}" ]]; then
          echo "FAIL: missing required positional: ${pos_names[i]}" >&2
          return 1
        fi
      fi
      i=$((i + 1))
    done
  fi

  # Required value flags
  i=0
  while [[ "${i}" -lt ${#flag_names[@]} ]]; do
    if [[ "${flag_req[i]}" -eq 1 ]]; then
      eval "setv=\"\${${prefix}_${flag_names[i]}_set}\""
      if [[ "${setv}" != "1" ]]; then
        echo "FAIL: missing required flag: --${flag_names[i]}" >&2
        return 1
      fi
    fi
    i=$((i + 1))
  done

  return 0
}

# Always includes optional --env (ADR-0019). Extra specs allowed before --.
cli_operator_parse() {
  local prefix="${1-}"
  shift || true
  if [[ -z "${prefix}" ]]; then
    echo "FAIL: cli_operator_parse: prefix required" >&2
    return 1
  fi
  local -a specs=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --)
        shift
        break
        ;;
      *)
        specs+=("$1")
        shift
        ;;
    esac
  done
  cli_parse "${prefix}" flag:env:value ${specs[@]+"${specs[@]}"} -- "$@"
}
