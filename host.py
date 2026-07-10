# shrike_host.py  --  RP2040 (MicroPython) host driver for the Shrike NTT accelerator.
#
# Talks to shrike_ntt_top over SPI (mode 0, MSB, 8-bit, one byte per CS pulse).
# The FPGA must already be configured with the bitstream before running this.
#
# Wiring (Shrike Lite):  MISO=GP0  CS=GP1  SCK=GP2  MOSI=GP3  FPGA reset(rst_n)=GP14
#
# Command set:
#   0x10 load A (512B)  0x11 load B (512B)  0x20 load zetas (256B)
#   0x30 fwd NTT  0x31 inv NTT  0x32 basemul  0x40 status  0x50 read A (512B)

from machine import Pin, SPI
import time, random

Q = 3329
R = 1 << 16

# ---------------------------------------------------------------- SPI setup
spi = SPI(0, baudrate=2_000_000, polarity=0, phase=0, bits=8,
          firstbit=SPI.MSB, sck=Pin(2), mosi=Pin(3), miso=Pin(0))
cs  = Pin(1,  Pin.OUT, value=1)
rst = Pin(14, Pin.OUT, value=1)

_rx = bytearray(1)
def xfer(b):
    """One byte out / one byte in, framed by its own CS pulse."""
    cs.value(0)
    spi.write_readinto(bytes([b & 0xFF]), _rx)
    cs.value(1)
    return _rx[0]

def fpga_reset():
    rst.value(0); time.sleep_ms(2); rst.value(1); time.sleep_ms(2)

# ---------------------------------------------------------------- protocol
def load_words(opcode, words):
    """opcode then len(words) 16-bit values as lo,hi bytes."""
    xfer(opcode)
    for w in words:
        xfer(w & 0xFF)
        xfer((w >> 8) & 0xFF)

def start_and_wait(opcode, timeout_ms=2000):
    xfer(opcode)                       # kick the operation
    t0 = time.ticks_ms()
    while not (xfer(0x40) & 0x01):     # poll STATUS until done bit set
        if time.ticks_diff(time.ticks_ms(), t0) > timeout_ms:
            raise RuntimeError("FPGA op timed out")

def read_A(n=256):
    """Read back the A buffer as n 16-bit coefficients."""
    xfer(0x50)                         # next 2n exchanges stream A, lo,hi
    out = []
    for _ in range(n):
        lo = xfer(0x00)
        hi = xfer(0x00)
        out.append(lo | (hi << 8))
    return out

def load_zetas(z):   load_words(0x20, z)
def load_A(poly):    load_words(0x10, poly)
def load_B(poly):    load_words(0x11, poly)
def ntt_forward():   start_and_wait(0x30)
def ntt_inverse():   start_and_wait(0x31)
def basemul():       start_and_wait(0x32)

# ---------------------------------------------------------------- zeta table
def brv7(i):
    r = 0
    for k in range(7):
        r |= ((i >> k) & 1) << (6 - k)
    return r

def gen_zetas():
    # zetas[i] = (17^brv7(i) mod q) * R mod q   (Montgomery form)
    return [(pow(17, brv7(i), Q) * R) % Q for i in range(128)]

ZETAS = gen_zetas()

# ---------------------------------------------------------------- software reference (self-check)
def redc(t):
    tl = t & 0xFFFF
    m  = (tl * 3327) & 0xFFFF
    u  = (t + m * Q) >> 16
    return u - Q if u >= Q else u

def fqmul(a, b):
    return redc(a * b)

def ref_ntt(r):
    r = list(r); k = 1; length = 128
    while length >= 2:
        start = 0
        while start < 256:
            z = ZETAS[k]; k += 1
            for j in range(start, start + length):
                t = fqmul(z, r[j + length])
                r[j + length] = (r[j] - t) % Q
                r[j]          = (r[j] + t) % Q
            start = j + 1 + length
        length >>= 1
    return r

def ref_basemul(a, b):
    r = [0] * 256
    for i in range(64):
        z = ZETAS[64 + i]
        for half in range(2):
            m = 2 * i + half
            zz = z if half == 0 else (Q - z)
            a0, a1 = a[2 * m], a[2 * m + 1]
            b0, b1 = b[2 * m], b[2 * m + 1]
            r[2 * m]     = (fqmul(fqmul(a1, b1), zz) + fqmul(a0, b0)) % Q
            r[2 * m + 1] = (fqmul(a0, b1) + fqmul(a1, b0)) % Q
    return r

# ---------------------------------------------------------------- demos
def demo_roundtrip():
    """Load a random poly, forward then inverse NTT, expect the original back.
       Self-verifying with no reference math -- the best headline demo."""
    x = [random.randint(0, Q - 1) for _ in range(256)]
    load_A(x)
    ntt_forward()
    ntt_inverse()
    y = read_A()
    ok = (y == x)
    print("ROUND-TRIP  fwd->inv :", "PASS (recovered original)" if ok else "FAIL")
    if not ok:
        print("  first diff:", next((i, x[i], y[i]) for i in range(256) if x[i] != y[i]))
    return ok

def demo_forward():
    """Forward NTT vs on-device software reference."""
    x = [(i * 7 + 3) % Q for i in range(256)]
    load_A(x); ntt_forward()
    hw = read_A()
    sw = ref_ntt(x)
    ok = (hw == sw)
    print("FORWARD NTT vs ref   :", "PASS" if ok else "FAIL", " hw[0:4]=", hw[0:4])
    return ok

def demo_basemul():
    """Pointwise multiply A(*)B vs software reference."""
    a = [random.randint(0, Q - 1) for _ in range(256)]
    b = [random.randint(0, Q - 1) for _ in range(256)]
    load_A(a); load_B(b); basemul()
    hw = read_A()
    sw = ref_basemul(a, b)
    ok = (hw == sw)
    print("BASEMUL     vs ref   :", "PASS" if ok else "FAIL", " hw[0:4]=", hw[0:4])
    return ok

def main():
    print("Shrike NTT accelerator -- RP2040 host")
    fpga_reset()
    load_zetas(ZETAS)
    print("zetas loaded (128 twiddles)\n")
    r1 = demo_roundtrip()
    r2 = demo_forward()
    r3 = demo_basemul()
    print("\n==>", "ALL PASS" if (r1 and r2 and r3) else "CHECK FAILURES ABOVE")

if __name__ == "__main__":
    main()