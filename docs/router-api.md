# ASUS Router API Integration

This document describes the undocumented HTTP API used by ASUS routers running ASUSWRT firmware. This was reverse-engineered from the ASUS mobile app and community projects, then validated against an RT-AX58U (RT-AX3000).

## Overview

The ASUS router exposes an HTTP API at its local IP (typically `192.168.50.1`). Authentication uses a token-based session, and data is retrieved via "hooks" — named functions that return specific data.

**Important**: Each hook must be requested in a separate HTTP request. Combining multiple hooks in a single request only returns the first one.

## Authentication

### Endpoint

```
POST http://{router_ip}/login.cgi
```

### Request

```http
POST /login.cgi HTTP/1.1
Host: 192.168.50.1
Content-Type: application/x-www-form-urlencoded
User-Agent: asusrouter-Android-DUTUtil-1.0.0.245

login_authorization=YWRtaW46cGFzc3dvcmQ=
```

The `login_authorization` value is `base64("username:password")`.

### Response

```json
{"asus_token":"xH8mK9pL2qR5sT7v"}
```

### Usage

Include the token as a cookie in all subsequent requests:

```
Cookie: asus_token=xH8mK9pL2qR5sT7v
```

The token expires after some period of inactivity. If a request returns a non-200 status or a redirect to the login page, re-authenticate.

## Data Retrieval

All data is fetched from the same endpoint:

```
POST http://{router_ip}/appGet.cgi
```

With the hook name in the request body:

```
hook=wanlink()
```

### Common Headers

```http
Content-Type: application/x-www-form-urlencoded
User-Agent: asusrouter-Android-DUTUtil-1.0.0.245
Cookie: asus_token={token}
```

## Hooks

### `wanlink()`

Returns WAN connection status in a JavaScript function-return format.

**Request body**: `hook=wanlink()`

**Response**:

```
{
"wanlink":function wanlink_status() { return 1;}
function wanlink_statusstr() { return 'Connected';}
function wanlink_type() { return 'dhcp';}
function wanlink_ipaddr() { return '140.174.208.204';}
function wanlink_netmask() { return '255.255.255.192';}
function wanlink_gateway() { return '140.174.208.193';}
function wanlink_dns() { return '1.1.1.1 1.0.0.1';}
function wanlink_lease() { return 86400;}
function wanlink_expires() { return 25765;}
function is_private_subnet() { return '0';}
function wanlink_xtype() { return '';}
function wanlink_xipaddr() { return '0.0.0.0';}
function wanlink_xnetmask() { return '0.0.0.0';}
function wanlink_xgateway() { return '0.0.0.0';}
function wanlink_xdns() { return '';}
function wanlink_xlease() { return 0;}
function wanlink_xexpires() { return 0;}

}
```

**Key fields**:

| Function | Type | Description |
|---|---|---|
| `wanlink_status()` | int | `1` = connected, `0` = disconnected |
| `wanlink_statusstr()` | string | Human-readable status ("Connected") |
| `wanlink_type()` | string | Connection type ("dhcp", "pppoe", etc.) |
| `wanlink_ipaddr()` | string | External/WAN IP address |
| `wanlink_gateway()` | string | Gateway IP |
| `wanlink_dns()` | string | Space-separated DNS servers |
| `wanlink_lease()` | int | DHCP lease duration in seconds |
| `wanlink_expires()` | int | Seconds until lease expires |

The `wanlink_x*` fields are for dual-WAN secondary connection.

**Parsing**: Extract values with regex matching `function {name}() { return '{value}'; }` for strings or `function {name}() { return {value};}` for integers.

### `cpu_usage(appobj)`

Returns cumulative CPU counters per core.

**Request body**: `hook=cpu_usage(appobj)`

**Response**:

```json
{
"cpu_usage":{"cpu1_total":"14667241","cpu1_usage":"371951","cpu2_total":"14698559","cpu2_usage":"374842","cpu3_total":"14720181","cpu3_usage":"358368","cpu4_total":"14712905","cpu4_usage":"347241"}
}
```

**Important**: These are **cumulative counters**, not percentages. To get CPU usage percentage:

1. Record `total` and `usage` for each core
2. On the next poll, compute deltas: `delta_total = total_now - total_prev`, `delta_usage = usage_now - usage_prev`
3. Percentage = `delta_usage * 100 / delta_total`

This means the first poll after startup cannot show CPU usage — it needs two data points.

The RT-AX58U has 4 cores (`cpu1` through `cpu4`).

### `memory_usage(appobj)`

Returns current memory statistics in KB.

**Request body**: `hook=memory_usage(appobj)`

**Response**:

```json
{
"memory_usage":{"mem_total":"1048576","mem_free":"380636","mem_used":"667940"}
}
```

| Field | Description |
|---|---|
| `mem_total` | Total RAM in KB (1048576 KB = 1 GB for RT-AX58U) |
| `mem_free` | Free RAM in KB |
| `mem_used` | Used RAM in KB |

### `netdev(appobj)`

Returns cumulative byte counters per network interface in hexadecimal.

**Request body**: `hook=netdev(appobj)`

**Response**:

```json
{
"netdev":{ "BRIDGE_rx":"0x21175ccf1","BRIDGE_tx":"0xd207a737f","INTERNET_rx":"0xd30ad37f8","INTERNET_tx":"0x216aabb9d","WIRED_rx":"0x0","WIRED_tx":"0x0","WIRELESS0_rx":"0xc7200c6d","WIRELESS0_tx":"0x17f7d4eff","WIRELESS1_rx":"0x150d347ea","WIRELESS1_tx":"0xae818c914"}
}
```

**Interfaces**:

| Interface | Description |
|---|---|
| `INTERNET` | WAN connection (the one you care about for bandwidth monitoring) |
| `BRIDGE` | LAN bridge (all local traffic) |
| `WIRED` | Ethernet-connected clients |
| `WIRELESS0` | 2.4 GHz WiFi radio |
| `WIRELESS1` | 5 GHz WiFi radio |

**Important**: Values are **hexadecimal cumulative byte counters** with a `0x` prefix. To get bandwidth:

1. Strip the `0x` prefix, then parse hex to integer: `Int64("d30ad37f8", radix: 16)` (note: `Int64` does **not** accept the `0x` prefix — you must remove it first)
2. On the next poll, compute delta: `bytes_now - bytes_prev`
3. Divide by elapsed seconds to get bytes/sec
4. Handle counter resets (if delta is negative, treat as 0)

`_rx` = bytes received (download), `_tx` = bytes transmitted (upload).

## Other Available Hooks

These hooks are available but not currently used by WiFi Monitor:

| Hook | Description |
|---|---|
| `get_clientlist()` | Connected devices with MAC, IP, hostname |
| `uptime()` | System uptime |
| `nvram_get(key)` | Read NVRAM configuration values |
| `wl_sta_list_2g()` | 2.4 GHz WiFi client list |
| `wl_sta_list_5g()` | 5 GHz WiFi client list |

## Other Endpoints

| Endpoint | Method | Description |
|---|---|---|
| `/login.cgi` | POST | Authentication |
| `/Logout.asp` | GET | End session |
| `/appGet.cgi` | POST | Data retrieval (hooks) |
| `/apply.cgi` | POST | Apply settings changes |
| `/applyapp.cgi` | POST | Execute commands |

## References

- [asusrouter Python library](https://github.com/Vaskivskyi/asusrouter) — Most comprehensive reverse-engineering effort
- [node-asuswrt](https://github.com/StefanIndustries/node-asuswrt) — Node.js wrapper
- [ASUSWRT-Merlin wiki](https://github.com/RMerl/asuswrt-merlin/wiki) — Enhanced firmware documentation
- [SNBForums API discussion](https://www.snbforums.com/threads/rt-ac86u-api-calls.64467/) — Community reverse-engineering
