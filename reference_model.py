# reference file to generate the vectors
q = 0x0D01 #3329
qprime = 3327 #0x0CFF or q*qprime = -1 mod 2^16
r = 1 << 16

def redc(t):
    # reference montgomery reduction: redc(t) = t * r^-1 mod q, for 0 <= t < r*q
    assert 0 <= t < r*q
    t_low = t & 0xFFFF
    m = (t_low*qprime)%r
    mq = m*q
    u = (t+mq)>>16
    assert (t+mq) & 0xFFFF == 0, "redc invariant violation, t+mq indivisible by r"
    if u>=q:
        u-=q
    return u

# sanity check against precalc values i did on paper (NEEEEE NANDEEEEEE)
print("redc(1) =", redc(1), " expect 169")
print("redc(r) =", redc(r), " expect 1")
print("redc(0) =", redc(0), " expect 0")

# check actual montgomery domain use case, redc(a*b) should recover us (a*b*r^-1) mod q
# which is what is used mid NTT to bring a product back down out of montgomery form

import random
random.seed(42)
rmodq_inv = pow(r, -1, q)
ok = True
for _ in range(20000):
    a = random.randint(0, q-1)
    b = random.randint(0, q-1)
    t = a*b
    got = redc(t)
    want = (a*b*rmodq_inv) % q
    if got != want:
        print("error lol, ", a, b, got, want)
        ok = False
print("20k random a*b redc check passed:", ok)
