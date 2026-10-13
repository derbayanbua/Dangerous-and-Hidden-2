"""PuTTY-Schl?ssel (PPK v3, unverschl?sselt) -> OpenSSH-Privatschl?ssel. Gibt keine Schl?sseldaten aus.
Aufruf: python -I ppk_to_openssh.py <eingabe.txt|ppk> <ausgabe>"""
import base64, struct, sys
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import serialization

def read_block(lines, key):
    for i, l in enumerate(lines):
        if l.startswith(key + ":"):
            n = int(l.split(":", 1)[1])
            return base64.b64decode("".join(lines[i + 1:i + 1 + n]))
    raise SystemExit("Block fehlt: " + key)

def fields(b):
    out, o = [], 0
    while o < len(b):
        (n,) = struct.unpack(">I", b[o:o + 4]); o += 4
        out.append(b[o:o + n]); o += n
    return out

lines = [l.strip() for l in open(sys.argv[1], encoding="ascii", errors="replace")]
assert any(l.startswith("PuTTY-User-Key-File-3: ssh-rsa") for l in lines)
assert any(l == "Encryption: none" for l in lines)
pub = fields(read_block(lines, "Public-Lines"))
prv = fields(read_block(lines, "Private-Lines"))
i = lambda b: int.from_bytes(b, "big")
e, n = i(pub[1]), i(pub[2])
d, p, q, iqmp = i(prv[0]), i(prv[1]), i(prv[2]), i(prv[3])
key = rsa.RSAPrivateNumbers(p, q, d, d % (p - 1), d % (q - 1), iqmp, rsa.RSAPublicNumbers(e, n)).private_key()
open(sys.argv[2], "wb").write(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.OpenSSH,
                                                serialization.NoEncryption()))
open(sys.argv[2] + ".pub", "wb").write(key.public_key().public_bytes(serialization.Encoding.OpenSSH,
                                                                     serialization.PublicFormat.OpenSSH) + b" hd2-deploy\n")
print("ok, Bits:", key.key_size)
