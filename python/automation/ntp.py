import socket
import struct
import time
import sys


def get_ntp_time_with_local_tz(ntp_server):
    NTP_PORT = 123
    NTP_FORMAT = "!12I"
    NTP_DELTA = 2208988800  # 1970-01-01 in NTP seconds since 1900-01-01

    # Create a message. This is a NTP request message.
    msg = b'\x1b' + 47 * b'\0'

    # Create the socket and send the request
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.sendto(msg, (ntp_server, NTP_PORT))
        msg, _ = s.recvfrom(48)

    # Unpack the data from the response
    unpacked_data = struct.unpack(NTP_FORMAT, msg)
    timestamp = unpacked_data[10] + float(unpacked_data[11]) / 2**32

    # Convert NTP time to UNIX timestamp
    unix_timestamp = timestamp - NTP_DELTA
    
    # Convert to local time
    local_time = time.localtime(unix_timestamp)
    
    return time.strftime('%Y-%m-%d %H:%M:%S %Z', local_time)


if __name__ == "__main__":
    if len(sys.argv) > 1:
        ntp_server = sys.argv[1]
    else:
        ntp_server = "pool.ntp.org"  # default NTP server
    
    print(f"Time ({ntp_server}): " + get_ntp_time_with_local_tz(ntp_server))
