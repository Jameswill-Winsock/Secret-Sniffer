# q = 3329, n = 256, zeta = 17 is a primitive 256th root of unity mod q:
# 17^256 mod q == 1 and 17^128 mod q == q-1 (==-1)
# the ct dit schedule consumes twiddle factors as powers of zeta in bit reverse order
# so the ith table entry is zeta ^ brv7(i) (where brv 7 is to reverse the lower 7 bits)
# datapath works in montgomery domain (i.e. R=2^16) and fqmul does:
# redc(zeta_mont * b) = zeta * b mod q, so each entry is stored prescaled by R

# zetas[i] = (17^brv7(i) mod q) * r mod q, i = 0....127

# index used per butterfly group is k = (1<<layer)+group 
# (for reference check ntt_addr_gen)

q = 3329
r = 1<<16       # montgomery radix or 2^16
zeta = 17
n7 = 7          # 128 = 2^7 twiddles which means 7bit bit reversal

def brv(x, bits):
    return int(f"{x:0{bits}b}"[::-1],2)

# sanity check, just in case, to see if zeta really is a primitive 256th root of unity mod q
assert pow(zeta, 256, q) == 1, "17^256 != 1 mod q"
assert pow(zeta, 128, q) == q-1, "17^128 != -1 mod q"

zetas = [(pow(zeta, brv(i, n7), q)*r)%q for i in range(128)]

with open("zetas.hex", "w") as f:
    for z in zetas:
        f.write(f"{z:04x}\n") # one 16 bit value per line for $readmemh

print("wrote zetas.hex 128 entries. zetas[0...3] = ", zetas[0:4])