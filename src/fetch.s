# The code deployed at an address, from an Ethereum node: python's
# decompile_address (Loader.load_addr: web3's automatic provider, then
# eth_getCode at "latest"). The provider is the one web3's AutoProvider
# finds: $WEB3_PROVIDER_URI (file://PATH - the node's IPC socket - or
# http://URL), else the first of the default IPC sockets that exists
# (geth's, parity's, trinity's: web3's get_default_ipc_path), else
# $WEB3_HTTP_PROVIDER_URI or http://localhost:8545, each tried when the
# one before can't be reached. JSON-RPC over the socket, or over
# HTTP/1.0. No TLS nor websockets: https:// and ws:// are refused with a
# message (a local node's http:// or IPC socket, then).

.include "defs.inc"

        .set RPC_TIMEOUT, 10            # seconds (web3's)
        .set RPC_UNREACHABLE, -1        # the provider can't be reached: the next one
        .set RPC_FAILED, -2             # no code out of the answer: the message

        .section .rodata
.Ls_env_uri:        .asciz "WEB3_PROVIDER_URI"
.Ls_env_http:       .asciz "WEB3_HTTP_PROVIDER_URI"
.Ls_http_default:   .asciz "http://localhost:8545"
.Ls_env_home:       .asciz "HOME"
.Ls_ipc_geth:       .asciz "/.ethereum/geth.ipc"
.Ls_ipc_parity:     .asciz "/.local/share/io.parity.ethereum/jsonrpc.ipc"
.Ls_ipc_trinity:    .asciz "/.local/share/trinity/mainnet/ipcs-eth1/jsonrpc.ipc"
.Ls_loader:         .asciz "panoramix.loader"
.Ls_fetching:       .asciz "Fetching code for %s..."
.Ls_code_dbg:       .asciz "Code: %s"
.Ls_req_a:          .asciz "{\"jsonrpc\": \"2.0\", \"method\": \"eth_getCode\", \"params\": [\""
.Ls_req_b:          .asciz "\", \"latest\"], \"id\": 1}"
.Ls_bad_addr:       .asciz "not an address (0x and 40 hex digits): "
.Ls_no_provider:    .asciz "Could not discover provider while making request: method:eth_getCode\nparams:('"
.Ls_no_provider_b:  .asciz "', 'latest')"
.Ls_scheme_a:       .asciz "Web3 does not know how to connect to scheme '"
.Ls_scheme_b:       .asciz "' in '"
.Ls_quote:          .asciz "'"
.Ls_no_tls:         .asciz "panasm has no TLS nor websockets: give the http:// address of a node or its IPC socket (file://PATH), not "
.Ls_http:           .asciz "http://"
.Ls_https:          .asciz "https://"
.Ls_ws:             .asciz "ws://"
.Ls_wss:            .asciz "wss://"
.Ls_file:           .asciz "file://"
.Ls_post:           .asciz "POST "
.Ls_http10:         .asciz " HTTP/1.0\r\nHost: "
.Ls_headers:        .asciz "\r\nContent-Type: application/json\r\nUser-Agent: panoramix-asm\r\nContent-Length: "
.Ls_crlf2:          .asciz "\r\n\r\n"
.Ls_slash:          .asciz "/"
.Ls_bad_answer:     .asciz "the node's answer isn't JSON-RPC: "
.Ls_rpc_error:      .asciz "the node answered an error: "
.Ls_no_code:        .asciz "the node gave no code: "
.Ls_for_url:        .asciz " for url: "
.Ls_client_err:     .asciz " Client Error: "
.Ls_server_err:     .asciz " Server Error: "
.Ls_http_answer:    .asciz "the node's HTTP answer: "
.Ls_key_result:     .asciz "result"
.Ls_key_error:      .asciz "error"
.Ls_null:           .asciz "null"
.Ls_chunked:        .asciz "chunked"
.Ls_too_long:       .asciz "the IPC socket's path is too long: "
.Ls_cant_send:      .asciz "the request couldn't be sent to "

        .text

# fetch_code(address, out) -> eax: 0 with the code's hex (no 0x) in the
# builder out, or -1 with the message in it
FUNC fetch_code
        ENTER
        sub rsp, 64
        .set FC_OUT, 0
        .set FC_REQ, 8                  # the request's body
        .set FC_RESP, 16                # the answer's JSON (or a message)
        .set FC_ADDR, 24                # the address, lowercase: 43 bytes
        mov [rsp + FC_OUT], rsi
        mov rbx, rdi
        call strlen@PLT
        cmp rax, 42                     # 0x and 40 hex digits
        jne .Lfc_bad_addr
        cmp byte ptr [rbx], '0'
        jne .Lfc_bad_addr
        movzx eax, byte ptr [rbx + 1]
        or eax, 0x20
        cmp eax, 'x'
        jne .Lfc_bad_addr
        mov word ptr [rsp + FC_ADDR], 0x7830    # "0x"
        mov ecx, 2
1:      movzx eax, byte ptr [rbx + rcx]
        lea edx, [rax - '0']
        cmp edx, 9
        jbe 2f
        or eax, 0x20                    # (lowercase, as python's address.lower())
        lea edx, [rax - 'a']
        cmp edx, 5
        ja .Lfc_bad_addr
2:      mov [rsp + FC_ADDR + rcx], al
        inc ecx
        cmp ecx, 42
        jb 1b
        mov byte ptr [rsp + FC_ADDR + 42], 0
        mov edi, LOG_INFO
        lea rsi, [rip + .Ls_loader]
        lea rdx, [rip + .Ls_fetching]
        lea rcx, [rsp + FC_ADDR]
        call log_fmt
        call sb_new                     # the request
        mov [rsp + FC_REQ], rax
        mov rdi, rax
        lea rsi, [rip + .Ls_req_a]
        call sb_append_c
        mov rdi, [rsp + FC_REQ]
        lea rsi, [rsp + FC_ADDR]
        call sb_append_c
        mov rdi, [rsp + FC_REQ]
        lea rsi, [rip + .Ls_req_b]
        call sb_append_c
        call sb_new
        mov [rsp + FC_RESP], rax
        # the provider of the environment
        lea rdi, [rip + .Ls_env_uri]
        call getenv@PLT
        test rax, rax
        jz 3f
        cmp byte ptr [rax], 0
        je 3f
        mov rdi, rax
        mov rsi, [rsp + FC_REQ]
        mov rdx, [rsp + FC_RESP]
        call rpc_uri
        test eax, eax
        jz .Lfc_answer
        cmp eax, RPC_UNREACHABLE
        jne .Lfc_failed
3:      # the first default IPC socket that exists
        lea r12, [rip + .Ls_ipc_geth]
        call ipc_default
        test rax, rax
        jnz 4f
        lea r12, [rip + .Ls_ipc_parity]
        call ipc_default
        test rax, rax
        jnz 4f
        lea r12, [rip + .Ls_ipc_trinity]
        call ipc_default
        test rax, rax
        jz 5f
4:      mov r12, rax
        mov rdi, rax
        mov rsi, [rsp + FC_REQ]
        mov rdx, [rsp + FC_RESP]
        call rpc_ipc
        mov r13d, eax
        mov rdi, r12
        call free@PLT
        test r13d, r13d
        jz .Lfc_answer
        cmp r13d, RPC_UNREACHABLE
        jne .Lfc_failed
5:      # http://localhost:8545 (or $WEB3_HTTP_PROVIDER_URI)
        lea rdi, [rip + .Ls_env_http]
        call getenv@PLT
        test rax, rax
        jz 6f
        cmp byte ptr [rax], 0
        jne 7f
6:      lea rax, [rip + .Ls_http_default]
7:      mov rdi, rax
        mov rsi, [rsp + FC_REQ]
        mov rdx, [rsp + FC_RESP]
        call rpc_uri
        test eax, eax
        jz .Lfc_answer
        cmp eax, RPC_UNREACHABLE
        jne .Lfc_failed
        # (web3's websocket provider comes next: not here) none
        mov rdi, [rsp + FC_OUT]
        call sb_reset
        mov rdi, [rsp + FC_OUT]
        lea rsi, [rip + .Ls_no_provider]
        call sb_append_c
        mov rdi, [rsp + FC_OUT]
        lea rsi, [rsp + FC_ADDR]
        call sb_append_c
        mov rdi, [rsp + FC_OUT]
        lea rsi, [rip + .Ls_no_provider_b]
        call sb_append_c
        jmp .Lfc_fail
.Lfc_answer:
        mov rax, [rsp + FC_RESP]
        mov rdi, [rax + SB_BUF]
        mov rsi, [rax + SB_LEN]
        mov rdx, [rsp + FC_OUT]
        call rpc_code
        test eax, eax
        jnz .Lfc_fail
        mov edi, LOG_DEBUG
        lea rsi, [rip + .Ls_loader]
        lea rdx, [rip + .Ls_code_dbg]
        mov rcx, [rsp + FC_OUT]
        mov rcx, [rcx + SB_BUF]
        call log_fmt
        xor ebx, ebx
        jmp .Lfc_free
.Lfc_failed:                            # the message is the answer's builder's
        mov rdi, [rsp + FC_OUT]
        call sb_reset
        mov rax, [rsp + FC_RESP]
        mov rdi, [rsp + FC_OUT]
        mov rsi, [rax + SB_BUF]
        mov rdx, [rax + SB_LEN]
        call sb_append
.Lfc_fail:
        mov ebx, -1
.Lfc_free:
        mov rdi, [rsp + FC_REQ]
        call sb_free
        mov rdi, [rsp + FC_RESP]
        call sb_free
        mov eax, ebx
        add rsp, 64
        LEAVE
.Lfc_bad_addr:
        mov rdi, [rsp + FC_OUT]
        call sb_reset
        mov rdi, [rsp + FC_OUT]
        lea rsi, [rip + .Ls_bad_addr]
        call sb_append_c
        mov rdi, [rsp + FC_OUT]
        mov rsi, rbx
        call sb_append_c
        mov eax, -1
        add rsp, 64
        LEAVE
ENDF fetch_code

# ipc_default(r12: the path under $HOME) -> rax: the malloc'ed path when
# the file exists, else 0 (keeps r12, rbx, r13, r14)
FUNC ipc_default
        ENTER
        lea rdi, [rip + .Ls_env_home]
        call getenv@PLT
        test rax, rax
        jz 1f
        mov rbx, rax
        call sb_new
        mov r13, rax
        mov rdi, r13
        mov rsi, rbx
        call sb_append_c
        mov rdi, r13
        mov rsi, r12
        call sb_append_c
        mov rbx, [r13 + SB_BUF]
        mov rdi, r13
        call free@PLT                   # (the builder, not its buffer)
        mov rdi, rbx
        xor esi, esi                    # F_OK
        call access@PLT
        test eax, eax
        jnz 2f
        mov rax, rbx
        LEAVE
2:      mov rdi, rbx
        call free@PLT
1:      xor eax, eax
        LEAVE
ENDF ipc_default

# rpc_uri(uri, body, resp) -> eax: 0 (the answer in resp), RPC_UNREACHABLE
# or RPC_FAILED (the message in resp): by the scheme of the uri
FUNC rpc_uri
        ENTER
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        lea rsi, [rip + .Ls_http]
        call prefix_nocase
        test eax, eax
        jz 1f
        mov rdi, rbx
        mov rsi, r12
        mov rdx, r13
        call rpc_http
        LEAVE
1:      mov rdi, rbx
        lea rsi, [rip + .Ls_file]
        call prefix_nocase
        test eax, eax
        jz 3f
        lea rdi, [rbx + 7]              # file://PATH (file://host/PATH: the path)
        cmp byte ptr [rdi], '/'
        je 2f
        mov esi, '/'
        call strchr@PLT
        mov rdi, rax
        test rax, rax
        jnz 2f
        lea rdi, [rip + .Ls_slash + 1]  # (none: "", which can't be reached)
2:      mov rsi, r12
        mov rdx, r13
        call rpc_ipc
        LEAVE
3:      mov rdi, rbx                    # TLS, websockets: refused
        lea rsi, [rip + .Ls_https]
        call prefix_nocase
        test eax, eax
        jnz 4f
        mov rdi, rbx
        lea rsi, [rip + .Ls_ws]
        call prefix_nocase
        test eax, eax
        jnz 4f
        mov rdi, rbx
        lea rsi, [rip + .Ls_wss]
        call prefix_nocase
        test eax, eax
        jnz 4f
        mov rdi, r13                    # python's NotImplementedError
        call sb_reset
        mov rdi, r13
        lea rsi, [rip + .Ls_scheme_a]
        call sb_append_c
        mov rdi, rbx                    # (the scheme: up to the ':', if any)
        mov esi, ':'
        call strchr@PLT
        mov rdx, rax
        sub rdx, rbx
        test rax, rax
        jnz 5f
        xor edx, edx
5:      mov rdi, r13
        mov rsi, rbx
        call sb_append
        mov rdi, r13
        lea rsi, [rip + .Ls_scheme_b]
        call sb_append_c
        mov rdi, r13
        mov rsi, rbx
        call sb_append_c
        mov rdi, r13
        lea rsi, [rip + .Ls_quote]
        call sb_append_c
        mov eax, RPC_FAILED
        LEAVE
4:      mov rdi, r13
        call sb_reset
        mov rdi, r13
        lea rsi, [rip + .Ls_no_tls]
        call sb_append_c
        mov rdi, r13
        mov rsi, rbx
        call sb_append_c
        mov eax, RPC_FAILED
        LEAVE
ENDF rpc_uri

# prefix_nocase(cstr, prefix) -> eax 0/1 (the prefix's letters in any case)
FUNC prefix_nocase
1:      movzx ecx, byte ptr [rsi]
        test ecx, ecx
        jz 2f
        movzx eax, byte ptr [rdi]
        or eax, 0x20
        or ecx, 0x20
        cmp eax, ecx
        jne 3f
        inc rdi
        inc rsi
        jmp 1b
2:      mov eax, 1
        ret
3:      xor eax, eax
        ret
ENDF prefix_nocase

# sock_timeouts(fd): web3's 10 s for the connection, the sending, the
# answer
FUNC sock_timeouts
        ENTER
        sub rsp, 16
        mov ebx, edi
        mov qword ptr [rsp], RPC_TIMEOUT        # struct timeval
        mov qword ptr [rsp + 8], 0
        mov edi, ebx
        mov esi, 1                      # SOL_SOCKET
        mov edx, 20                     # SO_RCVTIMEO
        mov rcx, rsp
        mov r8d, 16
        call setsockopt@PLT
        mov edi, ebx
        mov esi, 1
        mov edx, 21                     # SO_SNDTIMEO (connect's too, on linux)
        mov rcx, rsp
        mov r8d, 16
        call setsockopt@PLT
        add rsp, 16
        LEAVE
ENDF sock_timeouts

# rpc_ipc(path, body, resp) -> eax: the request on the node's unix socket,
# the answer read until it is a whole JSON value
FUNC rpc_ipc
        ENTER
        sub rsp, 128                    # struct sockaddr_un (110 bytes)
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        call strlen@PLT
        cmp rax, 107
        ja .Lri_too_long
        mov edi, 1                      # AF_UNIX
        mov esi, 1                      # SOCK_STREAM
        xor edx, edx
        call socket@PLT
        test eax, eax
        js .Lri_unreachable
        mov r14d, eax
        mov edi, r14d
        call sock_timeouts
        mov word ptr [rsp], 1           # sun_family
        lea rdi, [rsp + 2]
        mov rsi, rbx
        call strcpy@PLT
        mov edi, r14d
        mov rsi, rsp
        mov edx, 110
        call connect@PLT
        test eax, eax
        jnz .Lri_close_unreachable
        mov edi, r14d
        mov rsi, [r12 + SB_BUF]
        mov rdx, [r12 + SB_LEN]
        call write_all
        test eax, eax
        jnz .Lri_cant_send
        mov rdi, r13
        call sb_reset
        mov edi, 65536
        call xmalloc
        mov r12, rax                    # (the body sent: its register reused)
1:      mov edi, r14d
        mov rsi, r12
        mov edx, 65536
        call read@PLT
        test rax, rax
        jle 2f
        mov rdi, r13
        mov rsi, r12
        mov rdx, rax
        call sb_append
        mov rdi, [r13 + SB_BUF]         # a whole answer yet?
        mov rsi, rdi
        add rsi, [r13 + SB_LEN]
        call json_skip_value
        test rax, rax
        jz 1b
2:      mov rdi, r12
        call free@PLT
        mov edi, r14d
        call close@PLT
        xor eax, eax                    # (whole or not: rpc_code says)
        add rsp, 128
        LEAVE
.Lri_cant_send:
        mov edi, r14d
        call close@PLT
        mov rdi, r13
        call sb_reset
        mov rdi, r13
        lea rsi, [rip + .Ls_cant_send]
        call sb_append_c
        mov rdi, r13
        mov rsi, rbx
        call sb_append_c
        mov eax, RPC_FAILED
        add rsp, 128
        LEAVE
.Lri_too_long:
        mov rdi, r13
        call sb_reset
        mov rdi, r13
        lea rsi, [rip + .Ls_too_long]
        call sb_append_c
        mov rdi, r13
        mov rsi, rbx
        call sb_append_c
        mov eax, RPC_UNREACHABLE
        add rsp, 128
        LEAVE
.Lri_close_unreachable:
        mov edi, r14d
        call close@PLT
.Lri_unreachable:
        mov eax, RPC_UNREACHABLE
        add rsp, 128
        LEAVE
ENDF rpc_ipc

# rpc_http(uri, body, resp) -> eax: the request POSTed to http://host[:port]
# [/path] in HTTP/1.0 (the server closes after its answer: read to the
# end), the answer's body in resp (a chunked one put together)
FUNC rpc_http
        ENTER
        sub rsp, 400
        .set RH_URI, 0
        .set RH_BODY, 8
        .set RH_RESP, 16
        .set RH_AUTH, 24                # the authority (userinfo dropped)
        .set RH_AUTHLEN, 32
        .set RH_PATH, 40                # from the '/' (or the '?'), to the '#'
        .set RH_PATHLEN, 48
        .set RH_RES, 56                 # getaddrinfo's list
        .set RH_FD, 64
        .set RH_REQ, 72
        .set RH_ANS, 80                 # the answer (malloc'ed), its length
        .set RH_ANSLEN, 88
        .set RH_HINTS, 96               # struct addrinfo (48 bytes)
        .set RH_PORT, 144               # 16 bytes
        .set RH_HOST, 160               # 240 bytes
        mov [rsp + RH_URI], rdi
        mov [rsp + RH_BODY], rsi
        mov [rsp + RH_RESP], rdx
        lea rbx, [rdi + 7]              # after "http://"
        mov r12, rbx                    # the authority's end
1:      movzx eax, byte ptr [r12]
        test eax, eax
        jz 2f
        cmp eax, '/'
        je 2f
        cmp eax, '?'
        je 2f
        cmp eax, '#'
        je 2f
        inc r12
        jmp 1b
2:      mov rax, r12                    # the path: to the '#' or the end
3:      movzx ecx, byte ptr [rax]
        test ecx, ecx
        jz 4f
        cmp ecx, '#'
        je 4f
        inc rax
        jmp 3b
4:      mov [rsp + RH_PATH], r12
        sub rax, r12
        mov [rsp + RH_PATHLEN], rax
        mov rax, r12                    # userinfo@: dropped
5:      cmp rax, rbx
        jbe 6f
        dec rax
        cmp byte ptr [rax], '@'
        jne 5b
        lea rbx, [rax + 1]
6:      mov [rsp + RH_AUTH], rbx
        mov rax, r12
        sub rax, rbx
        mov [rsp + RH_AUTHLEN], rax
        # the host and the port
        mov dword ptr [rsp + RH_PORT], 0x3038   # "80"
        mov r13, rbx                    # the host's start
        mov r14, r12                    # its end
        cmp byte ptr [rbx], '['         # [ipv6]:port
        jne 8f
        lea r13, [rbx + 1]
        mov rax, r13
7:      cmp rax, r12
        jae .Lrh_bad_uri
        cmp byte ptr [rax], ']'
        je 71f
        inc rax
        jmp 7b
71:     mov r14, rax
        inc rax
        cmp rax, r12
        jae 10f
        cmp byte ptr [rax], ':'
        jne .Lrh_bad_uri
        jmp 9f
8:      mov rax, r12                    # host:port - the last ':'
81:     cmp rax, rbx
        jbe 10f
        dec rax
        cmp byte ptr [rax], ':'
        jne 81b
        mov r14, rax
9:      inc rax                         # the port: rax to r12
        mov rcx, r12
        sub rcx, rax
        jz 10f                          # ("host:": 80)
        cmp rcx, 15
        ja .Lrh_bad_uri
        lea rdi, [rsp + RH_PORT]
        mov rsi, rax
        mov rdx, rcx
        mov byte ptr [rsp + RH_PORT + rcx], 0
        call memcpy@PLT
10:     mov rcx, r14
        sub rcx, r13
        jz .Lrh_bad_uri
        cmp rcx, 239
        ja .Lrh_bad_uri
        mov byte ptr [rsp + RH_HOST + rcx], 0
        lea rdi, [rsp + RH_HOST]
        mov rsi, r13
        mov rdx, rcx
        call memcpy@PLT
        # getaddrinfo, and the first address that takes the connection
        lea rdi, [rsp + RH_HINTS]
        xor esi, esi
        mov edx, 48
        call memset@PLT
        mov dword ptr [rsp + RH_HINTS + 8], 1   # ai_socktype = SOCK_STREAM
        lea rdi, [rsp + RH_HOST]
        lea rsi, [rsp + RH_PORT]
        lea rdx, [rsp + RH_HINTS]
        lea rcx, [rsp + RH_RES]
        call getaddrinfo@PLT
        test eax, eax
        jnz .Lrh_unreachable
        mov qword ptr [rsp + RH_FD], -1
        mov rbx, [rsp + RH_RES]
11:     test rbx, rbx
        jz 13f
        mov edi, [rbx + 4]              # ai_family
        mov esi, [rbx + 8]              # ai_socktype
        mov edx, [rbx + 12]             # ai_protocol
        call socket@PLT
        test eax, eax
        js 12f
        mov r12d, eax
        mov edi, eax
        call sock_timeouts
        mov edi, r12d
        mov rsi, [rbx + 24]             # ai_addr
        mov edx, [rbx + 16]             # ai_addrlen
        call connect@PLT
        test eax, eax
        jz 14f
        mov edi, r12d
        call close@PLT
12:     mov rbx, [rbx + 40]             # ai_next
        jmp 11b
14:     mov [rsp + RH_FD], r12
13:     mov rdi, [rsp + RH_RES]
        call freeaddrinfo@PLT
        cmp qword ptr [rsp + RH_FD], 0
        jl .Lrh_unreachable
        # the request
        call sb_new
        mov [rsp + RH_REQ], rax
        mov rdi, rax
        lea rsi, [rip + .Ls_post]
        call sb_append_c
        mov rax, [rsp + RH_PATH]
        cmp byte ptr [rax], '/'
        je 15f
        mov rdi, [rsp + RH_REQ]
        lea rsi, [rip + .Ls_slash]
        call sb_append_c
15:     mov rdi, [rsp + RH_REQ]
        mov rsi, [rsp + RH_PATH]
        mov rdx, [rsp + RH_PATHLEN]
        call sb_append
        mov rdi, [rsp + RH_REQ]
        lea rsi, [rip + .Ls_http10]
        call sb_append_c
        mov rdi, [rsp + RH_REQ]
        mov rsi, [rsp + RH_AUTH]
        mov rdx, [rsp + RH_AUTHLEN]
        call sb_append
        mov rdi, [rsp + RH_REQ]
        lea rsi, [rip + .Ls_headers]
        call sb_append_c
        mov rax, [rsp + RH_BODY]
        mov rdi, [rsp + RH_REQ]
        mov rsi, [rax + SB_LEN]
        call sb_append_u64
        mov rdi, [rsp + RH_REQ]
        lea rsi, [rip + .Ls_crlf2]
        call sb_append_c
        mov rax, [rsp + RH_BODY]
        mov rdi, [rsp + RH_REQ]
        mov rsi, [rax + SB_BUF]
        mov rdx, [rax + SB_LEN]
        call sb_append
        mov rax, [rsp + RH_REQ]
        mov edi, [rsp + RH_FD]
        mov rsi, [rax + SB_BUF]
        mov rdx, [rax + SB_LEN]
        call write_all
        mov ebx, eax
        mov rdi, [rsp + RH_REQ]
        call sb_free
        test ebx, ebx
        jnz .Lrh_cant_send
        mov edi, [rsp + RH_FD]
        call read_fd
        mov [rsp + RH_ANS], rax
        mov [rsp + RH_ANSLEN], rdx
        mov edi, [rsp + RH_FD]
        call close@PLT
        # "HTTP/1.x 200 OK": the status
        mov rbx, [rsp + RH_ANS]
        mov r12, rbx
        add r12, [rsp + RH_ANSLEN]      # the end
        mov rdi, rbx
        mov esi, ' '
        call strchr@PLT
        test rax, rax
        jz .Lrh_bad_answer
        lea r13, [rax + 1]              # the status's digits
        mov rdi, r13
        xor esi, esi
        mov edx, 10
        call strtol@PLT
        mov r14, rax
        cmp r14, 200
        jl .Lrh_status
        cmp r14, 299
        jg .Lrh_status
        # the headers' end
        mov rdi, rbx
        lea rsi, [rip + .Ls_crlf2]
        call strstr@PLT
        test rax, rax
        jz .Lrh_bad_answer
        lea r13, [rax + 4]              # the body
        mov byte ptr [rax], 0           # (the headers: a string of their own)
        mov rdi, rbx
        lea rsi, [rip + .Ls_chunked]
        call strcasestr@PLT
        mov r14, rax
        mov rdi, [rsp + RH_RESP]
        call sb_reset
        test r14, r14
        jnz .Lrh_chunked
        mov rdi, [rsp + RH_RESP]
        mov rsi, r13
        mov rdx, r12
        sub rdx, r13
        call sb_append
        jmp .Lrh_done
.Lrh_chunked:                           # size in hex, CRLF, the bytes, CRLF...
        cmp r13, r12
        jae .Lrh_done
        mov rdi, r13
        lea rsi, [rsp + RH_HINTS]       # (strtoul's end pointer, in the scratch)
        mov edx, 16
        call strtoul@PLT
        test rax, rax
        jz .Lrh_done
        mov r14, rax
        mov rdi, [rsp + RH_HINTS]
        mov esi, 10                     # to the end of the size's line
        call strchr@PLT
        test rax, rax
        jz .Lrh_done
        lea r13, [rax + 1]
        mov rax, r12
        sub rax, r13
        cmp r14, rax
        cmova r14, rax                  # (cut short: what there is)
        mov rdi, [rsp + RH_RESP]
        mov rsi, r13
        mov rdx, r14
        call sb_append
        add r13, r14
        add r13, 2                      # CRLF
        jmp .Lrh_chunked
.Lrh_done:
        mov rdi, [rsp + RH_ANS]
        call free@PLT
        xor eax, eax
        add rsp, 400
        LEAVE
.Lrh_status:                            # requests' raise_for_status
        mov rdi, [rsp + RH_RESP]
        call sb_reset
        mov rdi, r13                    # "SSS Reason\r\n": up to the line's end
        mov esi, 13
        call strchr@PLT
        test rax, rax
        jnz 1f
        mov rax, r12
1:      mov byte ptr [rax], 0
        cmp r14, 400
        jl 3f
        cmp r14, 600
        jge 3f
        mov rdi, [rsp + RH_RESP]
        mov rsi, r14
        call sb_append_u64
        lea rsi, [rip + .Ls_client_err]
        cmp r14, 500
        jl 2f
        lea rsi, [rip + .Ls_server_err]
2:      mov rdi, [rsp + RH_RESP]
        call sb_append_c
        mov rdi, r13                    # the reason: past the digits and the space
        mov esi, ' '
        call strchr@PLT
        lea rsi, [rax + 1]
        test rax, rax
        jnz 21f
        mov rsi, r12                    # (none: "")
21:     mov rdi, [rsp + RH_RESP]
        call sb_append_c
        mov rdi, [rsp + RH_RESP]
        lea rsi, [rip + .Ls_for_url]
        call sb_append_c
        mov rdi, [rsp + RH_RESP]
        mov rsi, [rsp + RH_URI]
        call sb_append_c
        jmp 4f
3:      mov rdi, [rsp + RH_RESP]
        lea rsi, [rip + .Ls_http_answer]
        call sb_append_c
        mov rdi, [rsp + RH_RESP]
        mov rsi, rbx
        call sb_append_c
4:      mov rdi, [rsp + RH_ANS]
        call free@PLT
        mov eax, RPC_FAILED
        add rsp, 400
        LEAVE
.Lrh_bad_answer:
        mov rdi, [rsp + RH_RESP]
        call sb_reset
        mov rdi, [rsp + RH_RESP]
        lea rsi, [rip + .Ls_http_answer]
        call sb_append_c
        mov rdx, [rsp + RH_ANSLEN]
        cmp rdx, 200
        jbe 1f
        mov edx, 200
1:      mov rdi, [rsp + RH_RESP]
        mov rsi, [rsp + RH_ANS]
        call sb_append
        mov rdi, [rsp + RH_ANS]
        call free@PLT
        mov eax, RPC_FAILED
        add rsp, 400
        LEAVE
.Lrh_cant_send:
        mov edi, [rsp + RH_FD]
        call close@PLT
        mov rdi, [rsp + RH_RESP]
        call sb_reset
        mov rdi, [rsp + RH_RESP]
        lea rsi, [rip + .Ls_cant_send]
        call sb_append_c
        mov rdi, [rsp + RH_RESP]
        mov rsi, [rsp + RH_URI]
        call sb_append_c
        mov eax, RPC_FAILED
        add rsp, 400
        LEAVE
.Lrh_bad_uri:                           # (as a provider that can't be reached)
.Lrh_unreachable:
        mov eax, RPC_UNREACHABLE
        add rsp, 400
        LEAVE
ENDF rpc_http

# rpc_code(json, len, out) -> eax: 0 with the hex of the answer's "result"
# (no 0x) in out, or RPC_FAILED with the message (an "error" member: the
# node's; no "result", or not a string)
FUNC rpc_code
        ENTER
        sub rsp, 16
        mov rbx, rdi
        lea r12, [rdi + rsi]            # the end
        mov r13, rdx
        mov rdi, rbx
        mov rsi, r12
        lea rdx, [rip + .Ls_key_error]
        call json_member
        test rax, rax
        jz 1f
        mov r14, rax                    # an error, unless null
        mov [rsp], rdx
        mov rdi, rax
        lea rsi, [rip + .Ls_null]
        mov edx, 4
        call strncmp@PLT
        test eax, eax
        jz 1f
        mov rdi, r13
        call sb_reset
        mov rdi, r13
        lea rsi, [rip + .Ls_rpc_error]
        call sb_append_c
        mov rdi, r13
        mov rsi, r14
        mov rdx, [rsp]
        sub rdx, r14
        call sb_append
        jmp .Lrc_failed
1:      mov rdi, rbx
        mov rsi, r12
        lea rdx, [rip + .Ls_key_result]
        call json_member
        test rax, rax
        jz .Lrc_not_rpc
        mov r14, rax
        mov [rsp], rdx
        cmp byte ptr [r14], '"'
        jne .Lrc_no_code
        mov rdi, r13
        call sb_reset
        lea rsi, [r14 + 1]              # the string's inside (no escapes in hex)
        mov rdx, [rsp]
        sub rdx, rsi
        dec rdx
        cmp rdx, 2
        jb 2f
        cmp byte ptr [rsi], '0'
        jne 2f
        movzx eax, byte ptr [rsi + 1]
        or eax, 0x20
        cmp eax, 'x'
        jne 2f
        add rsi, 2
        sub rdx, 2
2:      mov rdi, r13
        call sb_append
        xor eax, eax
        add rsp, 16
        LEAVE
.Lrc_no_code:
        mov rdi, r13
        call sb_reset
        mov rdi, r13
        lea rsi, [rip + .Ls_no_code]
        call sb_append_c
        mov rdi, r13
        mov rsi, r14
        mov rdx, [rsp]
        sub rdx, r14
        call sb_append
        jmp .Lrc_failed
.Lrc_not_rpc:
        mov rdi, r13
        call sb_reset
        mov rdi, r13
        lea rsi, [rip + .Ls_bad_answer]
        call sb_append_c
        mov rdx, r12
        sub rdx, rbx
        cmp rdx, 200
        jbe 3f
        mov edx, 200
3:      mov rdi, r13
        mov rsi, rbx
        call sb_append
.Lrc_failed:
        mov eax, RPC_FAILED
        add rsp, 16
        LEAVE
ENDF rpc_code

# json_skip_ws(p, end) -> rax: past the whitespace (leaf: rax, rcx)
FUNC json_skip_ws
        mov rax, rdi
1:      cmp rax, rsi
        jae 2f
        movzx ecx, byte ptr [rax]
        cmp ecx, ' '
        je 3f
        cmp ecx, 9
        jb 2f
        cmp ecx, 10
        jbe 3f
        cmp ecx, 13
        jne 2f
3:      inc rax
        jmp 1b
2:      ret
ENDF json_skip_ws

# json_skip_value(p, end) -> rax: past the JSON value at p (after the
# whitespace), or 0 when there isn't a whole one (leaf: rax, rcx, rdx)
FUNC json_skip_value
        call json_skip_ws
        cmp rax, rsi
        jae .Lsv_fail
        xor edx, edx                    # the depth of the brackets
.Lsv_char:
        movzx ecx, byte ptr [rax]
        cmp ecx, 0x22                   # '"'
        je .Lsv_string
        cmp ecx, 0x7b                   # '{'
        je .Lsv_open
        cmp ecx, 0x5b                   # '['
        je .Lsv_open
        cmp ecx, 0x7d                   # '}'
        je .Lsv_close
        cmp ecx, 0x5d                   # ']'
        je .Lsv_close
        test rdx, rdx
        jnz .Lsv_next                   # (inside a bracket: anything else)
1:      inc rax                         # a scalar: to a delimiter
        cmp rax, rsi
        jae .Lsv_done
        movzx ecx, byte ptr [rax]
        cmp ecx, 0x2c                   # ','
        je .Lsv_done
        cmp ecx, 0x7d
        je .Lsv_done
        cmp ecx, 0x5d
        je .Lsv_done
        cmp ecx, ' '
        jbe .Lsv_done
        jmp 1b
.Lsv_string:
        inc rax
2:      cmp rax, rsi
        jae .Lsv_fail
        movzx ecx, byte ptr [rax]
        inc rax
        cmp ecx, 0x5c                   # '\': the next one escaped
        jne 3f
        inc rax
        jmp 2b
3:      cmp ecx, 0x22
        jne 2b
        test rdx, rdx
        jz .Lsv_done
        jmp .Lsv_more
.Lsv_open:
        inc rdx
        jmp .Lsv_next
.Lsv_close:
        test rdx, rdx
        jz .Lsv_fail
        dec rdx
        jnz .Lsv_next
        inc rax
        ret
.Lsv_next:
        inc rax
.Lsv_more:
        cmp rax, rsi
        jae .Lsv_fail
        jmp .Lsv_char
.Lsv_done:
        ret
.Lsv_fail:
        xor eax, eax
        ret
ENDF json_skip_value

# json_member(p, end, key) -> rax: the start of the value of the member
# key of the object at p (its key as written, no escapes), rdx its end;
# rax 0 if none
FUNC json_member
        ENTER
        sub rsp, 32
        .set JM_KEYLEN, 0
        .set JM_MATCH, 8
        .set JM_VALUE, 16
        mov rbx, rdi
        mov r12, rsi
        mov r13, rdx
        mov rdi, rdx
        call strlen@PLT
        mov [rsp + JM_KEYLEN], rax
        mov rdi, rbx
        mov rsi, r12
        call json_skip_ws
        cmp rax, r12
        jae .Ljm_none
        cmp byte ptr [rax], 0x7b        # '{'
        jne .Ljm_none
        lea rbx, [rax + 1]
.Ljm_member:
        mov rdi, rbx
        mov rsi, r12
        call json_skip_ws
        cmp rax, r12
        jae .Ljm_none
        cmp byte ptr [rax], 0x22        # a key (else '}' or junk: none)
        jne .Ljm_none
        mov rbx, rax
        mov rdi, rax
        mov rsi, r12
        call json_skip_value
        test rax, rax
        jz .Ljm_none
        mov r14, rax                    # past the key
        mov qword ptr [rsp + JM_MATCH], 0
        lea rcx, [r14 - 2]
        sub rcx, rbx                    # its length
        cmp rcx, [rsp + JM_KEYLEN]
        jne 1f
        lea rdi, [rbx + 1]
        mov rsi, r13
        mov rdx, rcx
        call memcmp@PLT
        test eax, eax
        jnz 1f
        mov qword ptr [rsp + JM_MATCH], 1
1:      mov rdi, r14
        mov rsi, r12
        call json_skip_ws
        cmp rax, r12
        jae .Ljm_none
        cmp byte ptr [rax], 0x3a        # ':'
        jne .Ljm_none
        lea rdi, [rax + 1]
        mov rsi, r12
        call json_skip_ws
        mov [rsp + JM_VALUE], rax
        mov rdi, rax
        mov rsi, r12
        call json_skip_value
        test rax, rax
        jz .Ljm_none
        cmp qword ptr [rsp + JM_MATCH], 0
        jne .Ljm_found
        mov rdi, rax
        mov rsi, r12
        call json_skip_ws
        cmp rax, r12
        jae .Ljm_none
        cmp byte ptr [rax], 0x2c        # ','
        jne .Ljm_none
        lea rbx, [rax + 1]
        jmp .Ljm_member
.Ljm_found:
        mov rdx, rax
        mov rax, [rsp + JM_VALUE]
        add rsp, 32
        LEAVE
.Ljm_none:
        xor eax, eax
        xor edx, edx
        add rsp, 32
        LEAVE
ENDF json_member

        .section .note.GNU-stack,"",@progbits
