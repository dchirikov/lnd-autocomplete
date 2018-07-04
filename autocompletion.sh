#!/bin/bash
function _lncli_autocomplete() {

    compopt +o bashdefault +o default +o dirnames +o filenames +o nospace +o plusdirs
    local EXEC=${COMP_WORDS[0]}
    function get_main_help() {
        local SUGGEST_DASHES=$1
        eval "${EXEC} help 2>/dev/null" | awk -v suggest_dashes=${SUGGEST_DASHES} '
            /^COMMANDS:/{                    # check if we in COMMANDS: section
                in_comm = 1;
                next;
            }

            ((/^\w.*/) && (in_comm == 1)){   # if in COMMANDS: and hit another line
                                             # starting not with space,
                                             # then we are not in COMMANDS: anymore
                in_comm = 0;
            }

            /^GLOBAL OPTIONS:/{              # same with GLOBAL OPTIONS:
                glob_opt = 1;
                next;
            }

            ((/^\w.*/) && (glob_opt == 1)){
                glob_opt = 0;
            }

            ((in_comm == 1) || (glob_opt == 1)) {    # here we are inside COMMANDS:
                                                     # or GLOBAL OPTIONS: sections

                if ((suggest_dashes == 0) && (substr($i, 0, 1) == "-")) {
                    next;
                }
                if (($0 ~ "\\w+") && ($0 !~ ":$")) { # skip empty lines and
                                                     # lines end with ":"

                    for (i = 1; i <= NF; i++) {      # need to handle both
                                                     #  cmd       Exmplanation
                                                     # and
                                                     #  cmd, cm   Explanation
                        last_symbol = substr($i, length($i), 1);
                        if (last_symbol != ",") {
                            print $i;
                            break;
                        }
                        cmd = substr($i, 0, length($i) - 1);    # word ends
                                                                # with ","
                        printf "%s ", cmd;
                    }
                }
            }
        ' | sort 2>/dev/null
    }

    function get_command() {
        local LNCLI_OPTIONS=($(get_main_help 0))
        for WORD in "${COMP_WORDS[@]}"; do
            for OPT in "${LNCLI_OPTIONS[@]}"; do
                if [[ "x${WORD}" == "x${OPT}" ]]; then
                    echo ${WORD}
                    return
                fi
            done
        done 2>/dev/null
    }

    function get_options() {
        local CMD=$1
        local ARG=$2
        eval "${EXEC} ${CMD} -h 2>/dev/null" | awk -v cmd=${CMD} -v arg=${ARG} '
            /^OPTIONS:/{                     # check if we in OPTIONS: section
                in_opt = 1;
                next;
            }

            ((/^\w.*/) && (in_opt == 1)){    # if in OPTIONS: and hit another line
                                             # starting not with space,
                                             # then we are not in OPTIONS: anymore
                in_opt = 0;
            }

            (in_opt == 1) {
                if (($0 ~ "\\w+") && ($0 !~ ":$")) { # skip empty lines and
                                                     # lines end with ":"
                    if (($1 == arg) && ($2 == "value")) {
                        # not boolean argument
                        need_value = 1;
                    }
                    args = args" "$1;

                }
            }
            END {
                # argument requires value, so do not sugest other arguments
                if (need_value != 1) {
                    print args;
                }
            }

        ' | sort 2>/dev/null
    }

    function get_channels_info() {
        local CMD=$1
        local WORD=$2
        local PRED=$3
        local ID_IP=$(
            eval "${EXEC} listpeers 2>/dev/null" \
                | awk '
                    /pub_key/ {
                        k = $2;
                    }
                    /address/ {
                        a = $2;
                        o = k"@"a;
                        gsub("[\",]", "", o);
                        print o;
                    }' | sort
        )
        local CHANNELS_UNRESOLVED=$(
            eval "${EXEC} listchannels 2>/dev/null" \
                | awk -v idip="${ID_IP}" '
                    BEGIN{
                        n = split(idip,ids,"\n");
                        for (i=1; i<n; i++) {
                            t = split(ids[i], m, "@");
                            id_map[m[1]] = m[2];
                        }
                    }
                    /remote_pubkey/ {
                        gsub("[\",]", "", $2);
                        k = $2
                    }
                    /chan_id/ {
                        i = $2;
                        count[k] += 1
                        o = i" "k" "id_map[k]" "count[k];
                        gsub("[\",]", "", o);
                        print o
                    }' | sort
        )
        # if we have les than 30 channels it would be not that expensive
        # to resolve them for readability
        if [[ $(echo "${CHANNELS_UNRESOLVED}" | wc -l) -le 30 ]]; then
            local CHANNELS=$(echo "${CHANNELS_UNRESOLVED}" \
                | while read i k a n; do
                    local alias=$(eval "${EXEC} getnodeinfo --pub_key ${k} 2>/dev/null" \
                        | sed -n '/alias/{s/.*": "\(.*\)",/\1/;p}')
                    if [[ ${n} -eq 1 ]]; then
                        echo -e "${i} ${a/:/\\:}\\/${alias/[:\/ ]/_}"
                    else
                        echo -e "${i} ${a/:/\\:}\\/${alias/[:\/ ]/_}\\(${n}\\)"
                    fi
                  done
            )
        else
            local CHANNELS=${CHANNELS_UNRESOLVED}
        fi
        if [[ "x${WORD}" == "x" ]]; then
            COMPREPLY=($(echo ${CHANNELS}))
            return
        fi
        local MATCHES=$(echo -ne ${CHANNELS} | tr ' ' '\n' | grep -F "${WORD}")
        local N_OCCURENCES=$(echo "${MATCHES}" | wc -l)
        if [[ ${N_OCCURENCES} -eq 1 ]]; then
            COMPREPLY=($(echo -ne "${CHANNELS}" | grep -F "${WORD}" | awk  '{print $1}'))
            return
        fi
        COMPREPLY=($(echo ${MATCHES}))
        return
    }

    function get_peer_ips() {
        local CMD=$1
        local WORD=$2
        local PRED=$3
        local PEERS_UNRESOLVED=$(
            eval "${EXEC} listpeers 2>/dev/null" \
                | awk '
                    /pub_key/ {
                        k = $2;
                    }
                    /address/ {
                        a = $2;
                        o = a" "k;
                        gsub("[\",]", "", o);
                        print o;
                    }' | sort
        )
        # if we have less than 30 peers it would be not that expensive
        # to resolve them for readability
        if [[ $(echo "${PEERS_UNRESOLVED}" | wc -l) -le 30 ]]; then
            local PEERS=$(echo "${PEERS_UNRESOLVED}" \
                | while read a k; do
                    local alias=$(eval "${EXEC} getnodeinfo --pub_key ${k} 2>/dev/null" \
                        | sed -n '/alias/{s/.*": "\(.*\)",/\1/;p}')
                    echo "${k} ${a/:/\\:}\\/${alias/[:\/ ]/_}" \
                        | tr -cd '\11\12\40-\176'
                  done
            )
        else
            local PEERS=${PEERS_UNRESOLVED}
        fi
        if [[ "x${WORD}" == "x" ]]; then
            COMPREPLY=($(echo ${PEERS}))
            return
        fi
        local MATCHES=$(echo "${PEERS}" | grep -E "${WORD}")
        if [[ "$(echo "${MATCHES}" | wc -l)" -eq 1 ]]; then
            COMPREPLY=($(echo "${MATCHES}" | awk '{print $1}'))
            return
        fi
        COMPREPLY=($(echo ${MATCHES}))
        return
    }

    local CUR=${COMP_WORDS[COMP_CWORD]}
    # Suggest first argument. Just dump 'lncli help'
    if [[ ${COMP_CWORD} -eq 1 ]]; then
        local LNCLI_OPTIONS=$(get_main_help 1)
        COMPREPLY=($(compgen -W "${LNCLI_OPTIONS}" -- "${CUR}"))
        return
    fi
    # Second argument is available
    local PREV=${COMP_WORDS[COMP_CWORD-1]}
    if [[ "x${PREV}" == "x=" ]]; then
        local PREV=${COMP_WORDS[COMP_CWORD-2]}
    fi
    # Now we need to find what's the subcomand we are in
    # find first argument which matches any subcomand
    # from "lncli help" output
    CMD=$(get_command)
    if [[ "x${CMD}" == "x" ]]; then
        # Arguments starting with "-"
        if [[ "${PREV:0:1}" == "-" ]]; then
            # arguments -*path or -*dir will be considered as
            # seeking for some system path
            if echo "${PREV}" | grep -qE "path|dir" ; then
                compopt -o bashdefault -o default -o dirnames -o filenames -o nospace -o plusdirs
                return
            fi
            return
        fi
    fi

    # get help for command
    CMD_OPT=$(get_options ${CMD} ${PREV})
    if [[ "x${CMD_OPT[*]}" != "x" ]]; then
        COMPREPLY=($(compgen -W "${CMD_OPT}" -- "${CUR}"))
        return
    fi

    # no CMD_OPT suggested, so do some handy stuff
    # which can't be handle from command help

    # list peers
    if [[ "x${PREV}" == "x--node_key" || "x${PREV}" == "x--pub_key" ]]; then
        COMPREPLY=($(compgen -F get_peer_ips -- "${CUR}" 2>/dev/null))
        return
    fi

    # suggest address type
    if [[ "x${CMD}" == "xnewaddress" ]]; then
        COMPREPLY=($(compgen -W "p2wkh np2wkh" -- "${CUR}"))
        return
    fi

    # suggest channels
    if [[ "x${CMD}" == "xgetchaninfo" && "x${PREV} == "x--chan_id"" ]]; then
        COMPREPLY=($(compgen -F get_channels_info -- "${CUR}" 2>/dev/null))
        return
    fi

}

complete -F _lncli_autocomplete lncli
complete -F _lncli_autocomplete lncli-debug
